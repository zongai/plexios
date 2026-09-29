import SwiftUI

struct IPTVSettingsView: View {
    @State private var playlists: [IPTVPlaylist] = []
    @State private var prefs = IPTVPreferences.default
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var busyId: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(playlists) { pl in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pl.name)
                                .font(AppTypography.headline)
                            Spacer()
                            Toggle("", isOn: bindingEnabled(pl))
                                .labelsHidden()
                        }
                        Text(pl.urlString)
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(2)
                        HStack {
                            Text("\(pl.channelCount) channels")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.tertiaryText)
                            if let d = pl.lastUpdated {
                                Text(d.formatted(date: .abbreviated, time: .shortened))
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(AppColors.tertiaryText)
                            }
                            Spacer()
                            if busyId == pl.id {
                                ProgressView()
                            } else {
                                Button(String(localized: "iptv.refresh")) {
                                    Task { await refresh(pl) }
                                }
                                .font(AppTypography.caption)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task {
                                await IPTVRepository.shared.deletePlaylist(id: pl.id)
                                await load()
                            }
                        } label: {
                            Label(String(localized: "common.cancel"), systemImage: "trash")
                        }
                    }
                }
                Button {
                    showAdd = true
                } label: {
                    Label(String(localized: "iptv.add_playlist"), systemImage: "plus.circle.fill")
                }
            } header: {
                Text(String(localized: "iptv.playlists"))
            }

            Section(String(localized: "iptv.playback")) {
                Picker(String(localized: "iptv.default_quality"), selection: $prefs.defaultQuality) {
                    ForEach(IPTVStreamQuality.allCases, id: \.self) { q in
                        Text(q.displayName).tag(q)
                    }
                }
                .onChange(of: prefs.defaultQuality) { _, _ in
                    Task { await IPTVRepository.shared.savePreferences(prefs) }
                }
                Toggle(String(localized: "iptv.auto_switch"), isOn: $prefs.autoSwitchSource)
                    .onChange(of: prefs.autoSwitchSource) { _, _ in
                        Task { await IPTVRepository.shared.savePreferences(prefs) }
                    }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppColors.destructive)
                        .font(AppTypography.caption)
                }
            }
        }
        .navigationTitle(String(localized: "iptv.title"))
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField(String(localized: "iptv.playlist_name"), text: $newName)
                    TextField(String(localized: "iptv.playlist_url"), text: $newURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                .navigationTitle(String(localized: "iptv.add_playlist"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { showAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.ok) {
                            Task { await addPlaylist() }
                        }
                        .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func bindingEnabled(_ pl: IPTVPlaylist) -> Binding<Bool> {
        Binding(
            get: { pl.enabled },
            set: { val in
                Task {
                    var copy = pl
                    copy.enabled = val
                    await IPTVRepository.shared.updatePlaylist(copy)
                    await load()
                }
            }
        )
    }

    private func load() async {
        playlists = await IPTVRepository.shared.playlists()
        prefs = await IPTVRepository.shared.preferences()
    }

    private func addPlaylist() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var pl = IPTVPlaylist(name: name.isEmpty ? "IPTV" : name, urlString: url)
        await IPTVRepository.shared.addPlaylist(pl)
        showAdd = false
        newName = ""
        newURL = ""
        await refresh(pl)
        await load()
    }

    private func refresh(_ pl: IPTVPlaylist) async {
        busyId = pl.id
        errorMessage = nil
        defer { busyId = nil }
        do {
            _ = try await IPTVRepository.shared.refreshPlaylist(pl)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
