import SwiftUI

/// In-app log viewer + export. Reads durable `FileLogStore` (survives relaunch after crash).
struct DiagnosticsLogView: View {
    @State private var text: String = ""
    @State private var sizeLabel: String = ""
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showClearConfirm = false
    @State private var autoRefresh = true

    var body: some View {
        VStack(spacing: 0) {
            if text.isEmpty {
                ContentUnavailableView(
                    String(localized: "settings.logs_empty"),
                    systemImage: "doc.text",
                    description: Text(String(localized: "settings.logs_empty_hint"))
                )
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle(String(localized: "settings.logs"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        reload()
                    } label: {
                        Label(String(localized: "settings.logs_refresh"), systemImage: "arrow.clockwise")
                    }
                    Button {
                        prepareExport()
                    } label: {
                        Label(String(localized: "settings.logs_export"), systemImage: "square.and.arrow.up")
                    }
                    Toggle(String(localized: "settings.logs_auto_refresh"), isOn: $autoRefresh)
                    Divider()
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label(String(localized: "settings.logs_clear"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(sizeLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                Spacer()
                Button {
                    prepareExport()
                } label: {
                    Label(String(localized: "settings.logs_export"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .onAppear { reload() }
        .task(id: autoRefresh) {
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { reload() }
            }
        }
        .sheet(isPresented: $showShare) {
            if let exportURL {
                ActivityShareView(items: [exportURL])
            }
        }
        .confirmationDialog(
            String(localized: "settings.logs_clear_confirm"),
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.logs_clear"), role: .destructive) {
                FileLogStore.shared.clearAll()
                reload()
            }
            Button(L10n.cancel, role: .cancel) {}
        }
    }

    private func reload() {
        text = FileLogStore.shared.readRecentText()
        let bytes = FileLogStore.shared.approximateSizeBytes()
        if bytes > 1_000_000 {
            sizeLabel = String(format: String(localized: "settings.logs_size_mb"), Double(bytes) / 1_000_000)
        } else {
            sizeLabel = String(format: String(localized: "settings.logs_size_kb"), Double(bytes) / 1000)
        }
    }

    private func prepareExport() {
        FileLogStore.shared.flush()
        do {
            exportURL = try FileLogStore.shared.exportMergedLogURL()
            showShare = true
        } catch {
            FileLogStore.shared.append(level: .error, category: "app", message: "Log export failed: \(error)")
        }
    }
}

/// Minimal UIActivityViewController wrapper for exporting files.
struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
