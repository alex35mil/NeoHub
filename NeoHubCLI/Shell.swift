import Foundation

struct Shell {
    static func run(_ command: String) -> Result<String, Error> {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ProcessInfo.processInfo.environment
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

                let error = NSError(
                    domain: "NeoHubCLI",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            """
                            Exit code: \(process.terminationStatus)
                            Output: \(errorOutput != "" ? errorOutput : "-")
                            """
                    ]
                )
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }
}
