import AppKit

enum ActivityMonitorTab: Int {
    case cpu = 1
    case memory
    case energy
    case disk
    case network
}

@MainActor
enum ActivityMonitorLauncher {
    private static let bundleIdentifier = "com.apple.ActivityMonitor"
    private static var hasShownPermissionAlert = false

    static func open(tab: ActivityMonitorTab) {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                selectTab(tab)
            }
        }
    }

    private static func selectTab(_ tab: ActivityMonitorTab) {
        // Verified on this Mac: the toolbar contains a Categories group with five
        // indexed radio buttons in the order represented by ActivityMonitorTab.
        let script = """
        tell application "System Events"
            tell process "Activity Monitor"
                repeat 20 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                end repeat
                if (count of windows) is 0 then error "Activity Monitor window did not appear"
                set frontmost to true
                click radio button \(tab.rawValue) of group 1 of toolbar 1 of window 1
            end tell
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            showPermissionAlertIfNeeded(errorInfo)
        }
    }

    private static func showPermissionAlertIfNeeded(_ error: NSDictionary) {
        let errorCode = error[NSAppleScript.errorNumber] as? Int
        guard (errorCode == -1743 || errorCode == -25211), !hasShownPermissionAlert else {
            return
        }
        hasShownPermissionAlert = true

        let alert = NSAlert()
        alert.messageText = String(
            localized: "activityMonitor.permission.title",
            defaultValue: "Permission Needed"
        )
        alert.informativeText = String(
            localized: "activityMonitor.permission.message",
            defaultValue: "Activity Monitor was opened, but Mectrics could not select its tab. Allow Mectrics under Privacy & Security in System Settings to enable direct tab selection."
        )
        alert.addButton(withTitle: String(
            localized: "activityMonitor.permission.openSettings",
            defaultValue: "Open Settings"
        ))
        alert.addButton(withTitle: String(
            localized: "activityMonitor.permission.cancel",
            defaultValue: "Cancel"
        ))

        if alert.runModal() == .alertFirstButtonReturn,
           let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Accessibility"
           ) {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
