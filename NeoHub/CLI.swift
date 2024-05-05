import AppKit
import Foundation

private struct Bin {
    static let source = Bundle.main.bundlePath + "/Contents/SharedSupport/neohub"
    static let destination = "/usr/local/bin/neohub"
}

private struct Lib {
    static let source = Bundle.main.bundlePath + "/Contents/Frameworks/NeoHubLib.framework"
    static let destination = "/usr/local/lib/NeoHubLib.framework"

    static var parent: String {
        return URL(fileURLWithPath: destination).deletingLastPathComponent().path
    }
}

enum CLIOperation {
    case install
    case uninstall
}

enum CLIStatus {
    case ok
    case error(reason: CLIError)
}

enum CLIError {
    case notInstalled
    case versionMismatch
    case unexpectedError(Error)
}

enum CLIInstallationError: Error {
    case failedToCreateAppleScript
    case userCanceledOperation
    case failedToExecuteAppleScript(error: NSDictionary)
}

final class CLI: ObservableObject {
    @Published private(set) var status: CLIStatus = .ok

    func updateStatusOnLaunch(_ cb: @escaping (CLIStatus) -> Void) {
        DispatchQueue.global().async {
            log.info("Getting the CLI status...")

            let status = Self.getStatus()

            log.info("CLI status: \(status)")

            DispatchQueue.main.async {
                if case .ok = status {
                    cb(status)
                } else {
                    self.status = status
                    cb(status)
                }
            }
        }
    }

    static func getStatus() -> CLIStatus {
        let fs = FileManager.default

        let installed = fs.fileExists(atPath: Bin.destination) && fs.fileExists(atPath: Lib.destination)

        if !installed {
            return .error(reason: .notInstalled)
        }

        let version = Self.getVersion()

        switch version {
            case .success(let version):
                if version == APP_VERSION {
                    return .ok
                } else {
                    return .error(reason: .versionMismatch)
                }
            case .failure(let error):
                log.error("Failed to get a CLI version. \(error)")
                return .error(reason: .unexpectedError(error))
        }
    }

    func perform(_ operation: CLIOperation, andThen callback: @escaping (Result<Void, CLIInstallationError>, CLIStatus) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let script =
            switch operation {
                case .install:
                    "do shell script \"mkdir -p \(Lib.parent) && cp -Rf \(Lib.source) \(Lib.destination) && cp -f \(Bin.source) \(Bin.destination)\" with administrator privileges"
                case .uninstall:
                    "do shell script \"rm \(Bin.destination) && rm -rf \(Lib.destination)\" with administrator privileges"
            }
            let result = CLI.runAppleScript(script)

            let status =
            switch result {
                case .success():
                    CLI.getStatus()
                case .failure(_):
                    self.status
            }

            DispatchQueue.main.async {
                self.status = status
                callback(result, status)
            }
        }
    }

    private static func getVersion() -> Result<String, Error> {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(filePath: Bin.destination)
        process.arguments = ["--version"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
                return .success(result)
            } else {
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)

                let error = ReportableError(
                    "Failed to get CLI version",
                    code: Int(process.terminationStatus),
                    meta: [
                        "StdErr": errorOutput.isEmpty ? "-" : errorOutput
                    ]
                )
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }

    private static func runAppleScript(_ script: String) -> Result<Void, CLIInstallationError> {
        var error: NSDictionary?

        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)

            switch error {
                case .some(let error):
                    if error["NSAppleScriptErrorNumber"] as? Int == -128 /* User canceled */ {
                        return .failure(.userCanceledOperation)
                    } else {
                        return .failure(.failedToExecuteAppleScript(error: error))
                    }
                case .none:
                    return .success(())
            }
        } else {
            return .failure(.failedToCreateAppleScript)
        }
    }
}
