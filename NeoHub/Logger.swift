import Logging
import LoggingSyslog

private func bootstrapLogger() -> Logger {
    LoggingSystem.bootstrap(SyslogLogHandler.init)

    var logger = Logger(label: APP_BUNDLE_ID)

    #if DEBUG
    logger.logLevel = .debug
    #else
    logger.logLevel = .info
    #endif

    return logger
}

let log = bootstrapLogger()
