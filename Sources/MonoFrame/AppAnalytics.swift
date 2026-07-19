//
//  AppAnalytics.swift
//  MonoFrame — thin Firebase Analytics wrapper.
//

import Foundation
import FirebaseAnalytics

/// Central place for every analytics event the app reports. Silent during
/// screenshot/UI-test automation runs so they never pollute stats.
enum AppAnalytics {
    /// ScreenshotTests launches the app with "-screenshots".
    private static let isAutomation =
        ProcessInfo.processInfo.arguments.contains("-screenshots")

    static func log(_ name: String, _ parameters: [String: Any]? = nil) {
        guard !isAutomation else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}
