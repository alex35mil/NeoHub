import Foundation
import Logging

private let envVar = "NEOHUB_LOG"
private let defaultLevel: Logger.Level = .info

private func bootstrapLogger() -> Logger {
    var logger = Logger(label: APP_BUNDLE_ID)

    let level =
    switch ProcessInfo.processInfo.environment[envVar] {
        case .some(let value): Logger.Level(rawValue: value) ?? defaultLevel
        case .none: defaultLevel
    }

    logger.logLevel = level

    return logger
}

let log = bootstrapLogger()
