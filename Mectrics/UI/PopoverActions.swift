import AppKit
import SwiftUI

/// The action a popover exists to offer — opening Activity Monitor from Memory,
/// Storage settings from Disk, the Attention Log from Compact Health.
///
/// Full width so it reads as this panel's own action rather than one option among
/// several, but ordinary weight: the readings above it are the point of the popover.
struct PopoverPrimaryButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Shared bottom bar: app-level actions sit in one compact menu below the popover's
/// own action.
struct PopoverActionBar: View {
    let onOpenSettings: () -> Void
    let onMenuDismissed: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            PopoverActionMenuButton(
                onOpenSettings: onOpenSettings,
                onMenuDismissed: onMenuDismissed
            )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, ExperienceSpacing.small)
        .font(.callout)
    }
}

/// Presents the popover's app-level actions after the accessory app has finished
/// activating. SwiftUI's `Menu` can begin tracking while macOS is still activating
/// the app on the first interaction, which immediately dismisses the menu.
private struct PopoverActionMenuButton: NSViewRepresentable {
    let onOpenSettings: () -> Void
    let onMenuDismissed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenSettings: onOpenSettings,
            onMenuDismissed: onMenuDismissed
        )
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: String(localized: "More")
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        button.isBordered = false
        button.focusRingType = .none
        button.setButtonType(.momentaryChange)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityLabel(String(localized: "More"))
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 20)
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onOpenSettings = onOpenSettings
        context.coordinator.onMenuDismissed = onMenuDismissed
    }

    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        coordinator.cancelPendingPresentation()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onOpenSettings: () -> Void
        var onMenuDismissed: () -> Void
        private weak var button: NSButton?
        private var activationObserver: NSObjectProtocol?

        init(
            onOpenSettings: @escaping () -> Void,
            onMenuDismissed: @escaping () -> Void
        ) {
            self.onOpenSettings = onOpenSettings
            self.onMenuDismissed = onMenuDismissed
        }

        @objc func showMenu(_ sender: NSButton) {
            guard activationObserver == nil else { return }
            button = sender

            if NSApp.isActive {
                DispatchQueue.main.async { [weak self] in self?.presentMenu() }
                return
            }

            // Wait for the activation transition before starting native menu
            // tracking. Opening it in the same click that activates the accessory
            // app is what caused the first-click flash.
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.cancelActivationObserver()
                DispatchQueue.main.async { [weak self] in self?.presentMenu() }
            }
            NSApp.activate(ignoringOtherApps: true)
        }

        @objc private func openSettings() {
            onOpenSettings()
        }

        @objc private func quit() {
            NSApp.terminate(nil)
        }

        func cancelPendingPresentation() {
            cancelActivationObserver()
            button = nil
        }

        private func cancelActivationObserver() {
            if let activationObserver {
                NotificationCenter.default.removeObserver(activationObserver)
                self.activationObserver = nil
            }
        }

        private func presentMenu() {
            guard let button, button.window != nil else { return }

            let menu = NSMenu()
            let settingsItem = NSMenuItem(
                title: String(localized: "Settings"),
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
            settingsItem.target = self
            menu.addItem(settingsItem)

            let quitItem = NSMenuItem(
                title: String(localized: "Quit"),
                action: #selector(quit),
                keyEquivalent: ""
            )
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
            quitItem.target = self
            menu.addItem(quitItem)

            menu.popUp(
                positioning: nil,
                at: NSPoint(x: button.bounds.maxX, y: button.bounds.maxY),
                in: button
            )
            self.button = nil
            onMenuDismissed()
        }
    }
}
