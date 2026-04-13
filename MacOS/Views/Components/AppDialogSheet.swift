import SwiftUI

// MARK: - Reusable dialog sheet with consistent header, theme, and button styling

struct AppDialogSheet<Content: View>: View {
    var icon: String
    var title: String
    var cancelTitle: String = "Cancel"
    var onCancel: () -> Void
    var primaryTitle: String
    var primaryAction: () -> Void
    var secondaryPrimaryTitle: String? = nil
    var secondaryPrimaryAction: (() -> Void)? = nil
    var minWidth: CGFloat = 360
    var minHeight: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(CursorTheme.border)
                .padding(.bottom, 16)

            content()
        }
        .padding(24)
        .frame(minWidth: minWidth, minHeight: minHeight)
        .background(CursorTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CursorTheme.brandBlue)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary)
            Spacer()
            HStack(spacing: 8) {
                Button(cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(DialogSecondaryButtonStyle())

                if let secondaryPrimaryTitle, let secondaryPrimaryAction {
                    Button(secondaryPrimaryTitle, action: secondaryPrimaryAction)
                        .buttonStyle(DialogSecondaryButtonStyle())
                }

                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(DialogPrimaryButtonStyle())
            }
        }
        .padding(.bottom, 14)
    }
}
