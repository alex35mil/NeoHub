import Foundation
import ArgumentParser
import NeoHubLib

let APP_BUNDLE_ID = "com.alex35mil.NeoHub.CLI"

enum CLIError: Error {
    case failedToGetBin(Error)
    case failedToCommunicateWithNeoHub(SendError)
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
            case .failedToGetBin(let error):
                return
                    """
                    Failed to get a path to Neovide binary. Make sure it is available in your PATH.
                    \(error.localizedDescription)
                    """
            case .failedToCommunicateWithNeoHub(let error):
                return
                    """
                    Failed to communicate with NeoHub.
                    \(error.localizedDescription)
                    """
        }
    }
}

@main
struct CLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "neohub",
        abstract: "A CLI interface to NeoHub. Launch new or activate already running Neovide instance.",
        version: "0.2.0"
    )

    @Argument(help: "Optional path passed to Neovide.")
    var path: String?

    @Option(help: "Optional editor name. Used for display only. If not provided, a file or directory name will be used.")
    var name: String?

    @Option(parsing: .remaining, help: "Options passed to Neovide")
    var opts: [String] = []

    mutating func run() {
        let wd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let bin: URL
        switch Shell.run("command -v neovide") {
            case .success(let path):
                bin = URL(fileURLWithPath: path)
            case .failure(let error):
                Self.exit(withError: CLIError.failedToGetBin(error))
        }

        let path: String? = switch self.path {
        case nil, "": nil
        case .some(let path): .some(path)
        }

        let env = ProcessInfo.processInfo.environment

        let req = RunRequest(
            wd: wd,
            bin: bin,
            name: self.name,
            path: path,
            opts: self.opts,
            env: env
        )

        log.debug(
            """

            ====================== OUTGOING REQUEST ======================
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

            =================== END OF OUTGOING REQUEST ==================
            """
        )

        let client = SocketClient()
        let result = client.send(req)

        switch result {
            case .success(let res):
                log.debug("Response: \(res ?? "-")")
                Self.exit(withError: nil)
            case .failure(let error):
                Self.exit(withError: CLIError.failedToCommunicateWithNeoHub(error))
        }
    }
}

