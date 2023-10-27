import Foundation

public struct Socket {
    public static let addr = "/tmp/neohub.sock"
}

public struct RunRequest: Codable {
    public let wd: URL
    public let bin: URL
    public let name: String?
    public let path: String?
    public let opts: [String]
    public let env: [String:String]

    public init(
        wd: URL,
        bin: URL,
        name: String?,
        path: String?,
        opts: [String],
        env: [String:String]
    ) {
        self.wd = wd
        self.bin = bin
        self.name = name
        self.path = path
        self.opts = opts
        self.env = env
    }
}
