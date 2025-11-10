import Foundation
import os.log

enum AnalyticsLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TradeBase", category: "App")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
