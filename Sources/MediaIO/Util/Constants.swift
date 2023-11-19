import Logging

let MediaIOIdentifier = "com.mediaio.mediaio"

// MARK: - Logger
fileprivate(set) var logger = Logger(label: MediaIOIdentifier)

func setLogLevel(_ level: Logger.Level) {
    logger.logLevel = level
}

