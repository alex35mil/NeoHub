import AppKit
import Foundation

private struct GitHub {
    static let user = "alex35mil"
    static let repo = APP_NAME
}

struct BugReporter {
    static func report(_ error: ReportableError) {
        let url = BugReporter.buildUrl(title: error.message, error: String(describing: error))
        NSWorkspace.shared.open(url)
    }

    // Since NotificationCenter can't reliably transfer ReportableError, we have to accept string'ish error
    static func report(title: String, error: String) {
        let url = BugReporter.buildUrl(title: title, error: error)
        NSWorkspace.shared.open(url)
    }

    private static func buildUrl(title: String, error: String) -> URL {
        let title = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let body =
            """
            ## What happened?
            _Reproduction steps, context, etc._

            ## Error details
            ```
            \(error)
            ```
            """
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

        let path = "https://github.com/\(GitHub.user)/\(GitHub.repo)/issues/new"
        let query = "title=\(title ?? "")&body=\(body ?? "")&labels=user-report"
        let url = "\(path)?\(query)"

        if let url = URL(string: url) {
            return url
        } else {
            log.warning("Failed to create the reporter url from: \(url)")
            return URL(string: path)!
        }
    }
}

struct ReportableError: Error {
    private(set) var message: String
    private let appVersion: String
    private let appBuild: String
    private let code: Int?
    private(set) var context: String
    private var meta: [String: Any]?
    private let osVersion: String
    private let arch: String?
    private let originalError: Error?

    init(
        _ message: String,
        code: Int? = nil,
        meta: [String: Any]? = nil,
        file: NSString = #file,
        function: NSString = #function,
        error: Error? = nil
    ) {
        if let error, var reportableError = error as? Self {
            if message != reportableError.message {
                reportableError.message = "\(message) → \(reportableError.message)"
            }

            let context = Self.buildContext(from: (file: file, function: function))

            if context != reportableError.context  {
                reportableError.context = "\(context) → \(reportableError.context)"
            }

            switch (meta, reportableError.meta) {
                case (.some(let meta), .none):
                    reportableError.meta = meta
                case (.some(let meta), .some(var reportableErrorMeta)):
                    reportableErrorMeta.merge(meta) { c, _ in c }
                case
                    (.none, .some(_)),
                    (.none, .none):
                    ()
            }

            self = reportableError
        } else {
            self.message = message
            self.appVersion = APP_VERSION
            self.appBuild = APP_BUILD
            self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            self.arch = Self.getSystemArch()
            self.code = code
            self.context = Self.buildContext(from: (file: file, function: function))
            self.originalError = error

            switch (meta, error.flatMap { err in err as NSError }) {
                case (.some(var meta), .some(let nsError)) where !nsError.userInfo.isEmpty:
                    meta.merge(nsError.userInfo) { c, _ in c }
                    self.meta = meta
                case (.some(let meta), _):
                    self.meta = meta
                case (.none, .some(let nsError)) where !nsError.userInfo.isEmpty:
                    self.meta = nsError.userInfo
                case (.none, _):
                    self.meta = nil
            }
        }
    }

    var localizedDescription: String {
        String(describing: self)
    }

    private static func buildContext(from loc: (file: NSString, function: NSString)) -> String {
        "\((loc.file.lastPathComponent as NSString).deletingPathExtension)#\(loc.function)"
    }

    private static func getSystemArch() -> String? {
        var sysinfo = utsname()

        uname(&sysinfo)

        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))

        return String(bytes: data, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
    }
}

extension ReportableError: CustomStringConvertible {
    var description: String {
        var output =
            """
            \(message)
            App: Version \(appVersion) (Build \(appBuild))
            macOS: \(osVersion)
            Arch: \(arch ?? "?")
            Context: \(context)
            """

        if let code {
            output.append("\n")
            output.append("Code: \(code)")
        }

        if let error = originalError {
            output.append("\n")
            output.append("Original Error: \(error)")
        }

        if let meta, !meta.isEmpty {
            output.append(
                """

                Metadata:
                    \(meta.debugDescription)
                """
            )
        }

        return output
    }
}
