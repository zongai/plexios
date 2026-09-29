import SwiftUI

/// Chooses TabView (iPhone / compact) vs sidebar NavigationSplitView (iPad regular).
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedSection: AppSection? = .home

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadSplitView
            } else {
                phoneTabView
            }
        }
        .offlineBanner()
    }

    // MARK: - iPhone

    private var phoneTabView: some View {
        TabView(selection: Binding(
            get: { selectedSection ?? .home },
            set: { selectedSection = $0 }
        )) {
            HomeView()
                .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.systemImage) }
                .tag(AppSection.home)

            LibrariesView()
                .tabItem { Label(AppSection.libraries.title, systemImage: AppSection.libraries.systemImage) }
                .tag(AppSection.libraries)

            MoreBrowseView()
                .tabItem { Label(L10n.more, systemImage: "ellipsis.circle.fill") }
                .tag(AppSection.collections)

            IPTVView()
                .tabItem { Label(AppSection.iptv.title, systemImage: AppSection.iptv.systemImage) }
                .tag(AppSection.iptv)

            SettingsTabView()
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
                .tag(AppSection.settings)
        }
    }

    // MARK: - iPad

    private var iPadSplitView: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(AppSection.sidebarCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(Optional(section))
                }
            }
            .navigationTitle("Plex")
            .listStyle(.sidebar)
        } detail: {
            ZStack {
                sectionLayer(.home) { HomeView() }
                sectionLayer(.libraries) { LibrariesView() }
                sectionLayer(.collections) { NavigationStack { CollectionsView() } }
                sectionLayer(.playlists) { NavigationStack { PlaylistsView() } }
                sectionLayer(.iptv) { IPTVView() }
                sectionLayer(.settings) { SettingsTabView() }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionLayer<Content: View>(
        _ section: AppSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedSection == section ? 1 : 0)
            .allowsHitTesting(selectedSection == section)
            .accessibilityHidden(selectedSection != section)
    }
}

/// iPhone “More” tab — single NavigationStack for Collections / Playlists.
struct MoreBrowseView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CollectionsView()
                } label: {
                    Label(L10n.collections, systemImage: "square.stack.fill")
                }
                NavigationLink {
                    PlaylistsView()
                } label: {
                    Label(L10n.playlists, systemImage: "music.note.list")
                }
            }
            .navigationTitle(L10n.more)
        }
    }
}
