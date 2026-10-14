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

    var body: some View {
        HStack {
            Menu {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(Text("More"))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, ExperienceSpacing.small)
        .font(.callout)
    }
}
