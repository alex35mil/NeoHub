import Foundation
import NIO
import NeoHubLib

final class SocketServer {
    let store: EditorStore

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    init(store: EditorStore) {
        self.store = store
    }

    func start() {
        DispatchQueue.global(qos: .background).async {
            do {
                let bootstrap = ServerBootstrap(group: self.group)
                    .serverChannelOption(ChannelOptions.backlog, value: 256)
                    .childChannelInitializer { channel in
                        channel.pipeline.addHandler(MessageHandler(store: self.store))
                    }

                if FileManager.default.fileExists(atPath: Socket.addr) {
                    log.warning("Socket \(Socket.addr) exists. Removing it.")
                    try? FileManager.default.removeItem(atPath: Socket.addr)
                }

                self.channel = try bootstrap.bind(unixDomainSocketPath: Socket.addr).wait()

                log.info("Bound to the \(Socket.addr) socket")

                try self.channel?.closeFuture.wait()
            } catch {
                let error = ReportableError("Failed to start the socket server", error: error)
                log.critical("\(error)")
                FailedToLaunchServerNotification(error: error).send()
            }
        }
    }

    func stop() {
        do {
            log.info("Stopping the socket server...")
            try group.syncShutdownGracefully()
            log.info("Socket server successfully stopped")
            if FileManager.default.fileExists(atPath: Socket.addr) {
                log.warning("The socket at \(Socket.addr) still exists. Removing it.")
                try? FileManager.default.removeItem(atPath: Socket.addr)
                log.info("Socket at \(Socket.addr) is removed")
            }
        } catch {
            log.error("There was an issue dunring the socket server termination. Details: \(error)")
        }
    }
}

enum MessageHandlerState {
    case ready
    case reading(
        length: UInt32,
        buffer: ByteBuffer
    )
}

class MessageHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    let store: EditorStore
    var state: MessageHandlerState = .ready

    init(store: EditorStore) {
        self.store = store
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        log.trace("Incoming data from the CLI")

        var message = unwrapInboundIn(data)

        switch self.state {
            case .ready:
                log.trace("First packet. Getting message size.")

                var header = message.readSlice(length: 4)!
                let length = header.readInteger(endianness: .big, as: UInt32.self)!

                log.trace("Message size is \(length) bytes")

                if length > message.readableBytes {
                    log.trace("There will be more packets. Waiting.")
                    self.state = .reading(length: length, buffer: message)
                } else {
                    log.trace("Message fully received")
                    self.handleRequest(context: context, buffer: &message)
                }
            case .reading(let length, var buffer):
                log.trace("Next packet received")

                buffer.writeBuffer(&message)

                if length > buffer.readableBytes {
                    log.trace("There will be more packets. Waiting.")
                    self.state = .reading(length: length, buffer: buffer)
                } else {
                    log.trace("Message fully received")
                    self.handleRequest(context: context, buffer: &buffer)
                }
        }
    }

    func handleRequest(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        if let json = buffer.readDispatchData(length: buffer.readableBytes) {
            do {
                log.trace("Decoding incoming JSON...")

                let decoder = JSONDecoder()
                let req = try decoder.decode(RunRequest.self, from: Data(json))

                log.debug(
                    """

                    ====================== INCOMING REQUEST ======================
                    wd: \(req.wd)
                    bin: \(req.bin)
                    name: \(req.name ?? "-")
                    path: \(req.path ?? "-")
                    opts: \(req.opts)
                    """
                )
                log.trace("env: \(req.env)")
                log.debug(
                    """

                    ================== END OF INCOMING REQUEST ===================
                    """
                )

                DispatchQueue.global().async {
                    self.store.runEditor(request: req)
                }
            } catch {
                let error = ReportableError("Failed to decode request from the CLI", error: error)
                log.error("\(error)")
                FailedToHandleRequestFromCLINotification(error: error).send()
            }

            let response = "OK"

            var buffer = context.channel.allocator.buffer(capacity: response.count)

            buffer.writeString(response)

            let dataToSend = NIOAny(buffer)

            context.writeAndFlush(dataToSend, promise: nil)

            log.trace("Response sent")
        }
    }
}
