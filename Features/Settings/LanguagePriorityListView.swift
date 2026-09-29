import SwiftUI

/// Editable, reorderable language priority list (audio or subtitle).
struct LanguagePriorityListView: View {
    enum Kind {
        case audio
        case subtitle

        var title: String {
            switch self {
            case .audio: return String(localized: "settings.audio_languages")
            case .subtitle: return String(localized: "settings.subtitle_languages")
            }
        }

        var footer: String {
            switch self {
            case .audio: return String(localized: "settings.audio_languages_footer")
            case .subtitle: return String(localized: "settings.subtitle_languages_footer")
            }
        }
    }

    let kind: Kind
    @State private var codes: [String] = []
    @State private var showAdd = false

    private var availableToAdd: [(code: String, labelKey: String)] {
        PlaybackPreferences.languageOptions.filter { opt in
            !opt.code.isEmpty && !codes.contains(opt.code)
        }
    }

    var body: some View {
        List {
            Section {
                if codes.isEmpty {
                    Text(String(localized: "settings.lang_list_empty"))
                        .foregroundStyle(AppColors.secondaryText)
                        .font(AppTypography.body)
                } else {
                    ForEach(Array(codes.enumerated()), id: \.element) { index, code in
                        HStack(spacing: AppSpacing.md) {
                            Text("\(index + 1)")
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundStyle(PlexColors.accent)
                                .frame(width: 24, alignment: .center)
                            Text(label(for: code))
                                .font(AppTypography.body)
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(AppColors.tertiaryText)
                                .accessibilityHidden(true)
                        }
                        .tag(code)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
            } header: {
                Text(String(localized: "settings.lang_priority_order"))
            } footer: {
                Text(kind.footer)
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label(String(localized: "settings.add_language"), systemImage: "plus.circle.fill")
                }
                .disabled(availableToAdd.isEmpty)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                List {
                    ForEach(availableToAdd, id: \.code) { opt in
                        Button {
                            add(opt.code)
                            showAdd = false
                        } label: {
                            Text(String(localized: String.LocalizationValue(opt.labelKey)))
                        }
                    }
                }
                .navigationTitle(String(localized: "settings.add_language"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { showAdd = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func label(for code: String) -> String {
        if let opt = PlaybackPreferences.languageOptions.first(where: { $0.code == code }) {
            return String(localized: String.LocalizationValue(opt.labelKey))
        }
        return code
    }

    private func reload() {
        let prefs = PlaybackSettingsStore.shared.preferences
        codes = kind == .audio ? prefs.preferredAudioLanguages : prefs.preferredSubtitleLanguages
    }

    private func persist() {
        var prefs = PlaybackSettingsStore.shared.preferences
        if kind == .audio {
            prefs.preferredAudioLanguages = codes
        } else {
            prefs.preferredSubtitleLanguages = codes
        }
        PlaybackSettingsStore.shared.preferences = prefs
    }

    private func move(from source: IndexSet, to destination: Int) {
        codes.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func delete(at offsets: IndexSet) {
        codes.remove(atOffsets: offsets)
        persist()
    }

    private func add(_ code: String) {
        guard !code.isEmpty, !codes.contains(code) else { return }
        codes.append(code)
        persist()
    }
}
