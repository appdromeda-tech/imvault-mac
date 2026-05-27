import SwiftUI

/// The main detail pane. Doubles as the hero CTA zone — the placeholder used to
/// just say "select something"; now it surfaces both of the app's primary
/// actions as labeled cards. Toolbar carries only one button as a shortcut;
/// the primary discoverability happens here.
struct ChatDetailPlaceholder: View {
    let selectedCount: Int
    let totalCount: Int
    let sidecarVersion: String?
    let onBackUp: () -> Void
    let onOpenBackup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Header — name + tagline so the right pane isn't empty-feeling.
            VStack(spacing: 8) {
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("imvault")
                    .font(.title)
                    .bold()
                Text("Encrypted backups for your iMessage history")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 24)

            // Two hero action cards stacked vertically. Back Up is the primary
            // (filled accent) action when there's a selection; otherwise it's
            // disabled so the empty-state messaging carries the explanation.
            VStack(spacing: 12) {
                ActionCard(
                    icon: "square.and.arrow.down.fill",
                    title: backupTitle,
                    subtitle: backupSubtitle,
                    style: selectedCount > 0 ? .primary : .disabled,
                    action: onBackUp
                )

                ActionCard(
                    icon: "folder.fill",
                    title: "Open a Saved Backup",
                    subtitle: "Read messages from a backup file you've already made.",
                    style: .secondary,
                    action: onOpenBackup
                )
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            if let version = sidecarVersion {
                Text(version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backupTitle: String {
        if selectedCount == 0 {
            return "Back Up Your Conversations"
        }
        return "Back Up \(selectedCount) of \(totalCount) Selected"
    }

    private var backupSubtitle: String {
        if selectedCount == 0 {
            return "Pick conversations from the sidebar, then save them as an encrypted backup."
        }
        if selectedCount == 1 {
            return "Save the selected conversation as an encrypted backup."
        }
        return "Save \(selectedCount) conversations as a single encrypted backup file."
    }
}

/// A row-style action card: icon on the left, title + subtitle in the middle,
/// chevron on the right. Three visual styles: primary (filled accent), secondary
/// (subtle neutral background), disabled (low-contrast, non-interactive).
struct ActionCard: View {
    enum Style {
        case primary
        case secondary
        case disabled
    }

    let icon: String
    let title: String
    let subtitle: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: { if style != .disabled { action() } }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 36)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(titleColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chevronColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: style == .secondary ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(style == .disabled)
    }

    private var background: AnyShapeStyle {
        switch style {
        case .primary:   return AnyShapeStyle(Color.accentColor)
        case .secondary: return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        case .disabled:  return AnyShapeStyle(Color.secondary.opacity(0.08))
        }
    }

    private var borderColor: Color {
        style == .secondary ? Color.secondary.opacity(0.2) : .clear
    }

    private var iconColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return .accentColor
        case .disabled:  return .secondary.opacity(0.5)
        }
    }

    private var titleColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return .primary
        case .disabled:  return .secondary
        }
    }

    private var subtitleColor: Color {
        switch style {
        case .primary:   return .white.opacity(0.85)
        case .secondary: return .secondary
        case .disabled:  return .secondary.opacity(0.7)
        }
    }

    private var chevronColor: Color {
        switch style {
        case .primary:   return .white.opacity(0.6)
        case .secondary: return .secondary
        case .disabled:  return .secondary.opacity(0.3)
        }
    }
}

#Preview("No selection") {
    ChatDetailPlaceholder(
        selectedCount: 0,
        totalCount: 42,
        sidecarVersion: "imvault, version 0.4.1",
        onBackUp: {},
        onOpenBackup: {}
    )
    .frame(width: 700, height: 500)
}

#Preview("With selection") {
    ChatDetailPlaceholder(
        selectedCount: 3,
        totalCount: 42,
        sidecarVersion: "imvault, version 0.4.1",
        onBackUp: {},
        onOpenBackup: {}
    )
    .frame(width: 700, height: 500)
}
