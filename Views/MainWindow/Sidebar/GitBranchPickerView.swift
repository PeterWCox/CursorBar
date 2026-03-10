import SwiftUI

// MARK: - New branch sheet

struct NewBranchSheet: View {
    var currentBranch: String
    /// Create the branch; returns nil on success, error message otherwise.
    var onCreate: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var branchName: String = ""
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    private let fieldBorder = Color(NSColor.separatorColor)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CursorTheme.brandBlue)
                Text("New branch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Button("Create") { submit() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 14)

            Divider()
                .opacity(0.5)
                .padding(.bottom, 16)

            Text("Create a new branch from \(currentBranch.isEmpty ? "HEAD" : currentBranch).")
                .font(.system(size: 13))
                .foregroundStyle(CursorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 6) {
                Text("Branch name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                TextField("branch-name", text: $branchName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(fieldBorder, lineWidth: 1))
                    .focused($isFieldFocused)
                    .onSubmit { submit() }
            }
            .padding(.bottom, 12)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.bottom, 8)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        .background(CursorTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CursorTheme.border, lineWidth: 1))
        .onAppear {
            isFieldFocused = true
        }
    }

    private func submit() {
        errorMessage = nil
        let name = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Branch name cannot be empty."
            return
        }
        if let err = onCreate(name) {
            errorMessage = err
            return
        }
        dismiss()
    }
}

// MARK: - Git branch picker menu

struct GitBranchPickerView: View {
    var branches: [String]
    var currentBranch: String
    var onSelectBranch: (String) -> Void
    /// Called when the user opens the dropdown so the parent can reload the branch list.
    var onOpenMenu: () -> Void = {}
    /// Create a new branch; returns nil on success, error message otherwise. If non-nil, a "New branch…" entry is shown.
    var onCreateBranch: ((String) -> String?)? = nil

    @State private var isPopoverPresented = false
    @State private var showNewBranchSheet = false

    var body: some View {
        Button {
            onOpenMenu()
            isPopoverPresented = true
        } label: {
            pickerLabel(
                icon: "arrow.triangle.branch",
                title: currentBranch.isEmpty ? "No branch" : currentBranch
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .colorScheme(.dark)
        .disabled(branches.isEmpty)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(branches, id: \.self) { branch in
                    Button {
                        onSelectBranch(branch)
                        isPopoverPresented = false
                    } label: {
                        if branch == currentBranch {
                            Label(branch, systemImage: "checkmark")
                        } else {
                            Text(branch)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if onCreateBranch != nil {
                    Divider()
                        .padding(.vertical, 6)
                    Button {
                        isPopoverPresented = false
                        showNewBranchSheet = true
                    } label: {
                        Label("New branch…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .frame(minWidth: 200)
            .background(CursorTheme.surfaceMuted)
        }
        .sheet(isPresented: $showNewBranchSheet) {
            NewBranchSheet(currentBranch: currentBranch) { name in
                onCreateBranch?(name) ?? nil
            }
        }
    }

    private func pickerLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(CursorTheme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
    }
}
