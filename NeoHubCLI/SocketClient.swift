import Foundation
import NIO
import NeoHubLib

enum SendError: Error {
    case appIsNotRunning
    case failedToSendRequest(Error)
}

extension SendError: LocalizedError {
    var errorDescription: String? {
        switch self {
            case .appIsNotRunning:
                return "NeoHub app is not running. Start the app and retry."
            case .failedToSendRequest(let error):
                return error.localizedDescription
        }
    }
}

class SocketClient {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    func send(_ request: Codable) -> Result<String?, SendError> {
        if !FileManager.default.fileExists(atPath: Socket.addr) {
            return .failure(.appIsNotRunning)
        }

        do {
            let encoder = JSONEncoder()
            let json = try encoder.encode(request)

            let responsePromise = group.next().makePromise(of: String.self)

            let bootstrap = ClientBootstrap(group: group).channelInitializer { channel in
                let responseHandler = ResponsePromiseHandler(promise: responsePromise)
                return channel.pipeline.addHandlers([ResponseHandler(), responseHandler])
            }

            let channel = try bootstrap.connect(unixDomainSocketPath: Socket.addr).wait()

            let length = UInt32(bigEndian: UInt32(json.count))
            let header = withUnsafeBytes(of: length) { Data($0) }
            var buffer = channel.allocator.buffer(capacity: header.count + json.count)

            buffer.writeBytes(header + json)

            try channel.writeAndFlush(buffer).wait()

            let response = try responsePromise.futureResult.wait()

            try channel.close().wait()

            return .success(response)
        } catch {
            return .failure(.failedToSendRequest(error))
        }
    }
}

class ResponseHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = String

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let response = buffer.readString(length: buffer.readableBytes) {
            context.fireChannelRead(self.wrapOutboundOut(response))
        }
    }
}

class ResponsePromiseHandler: ChannelInboundHandler {
    typealias InboundIn = String
    private let promise: EventLoopPromise<String>

    init(promise: EventLoopPromise<String>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        promise.succeed(response)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}
