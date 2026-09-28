import SwiftUI

/// Chooses TabView (iPhone / compact) vs sidebar NavigationSplitView (iPad regular).
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedSection: AppSection = .home

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
        TabView(selection: $selectedSection) {
            HomeView()
                .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.systemImage) }
                .tag(AppSection.home)

            LibrariesView()
                .tabItem { Label(AppSection.libraries.title, systemImage: AppSection.libraries.systemImage) }
                .tag(AppSection.libraries)

            MoreBrowseView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppSection.collections)

            SearchView()
                .tabItem { Label(AppSection.search.title, systemImage: AppSection.search.systemImage) }
                .tag(AppSection.search)

            SettingsTabView()
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
                .tag(AppSection.settings)
        }
    }

    // MARK: - iPad
    // Keep section views alive in a ZStack so NavigationPath / scroll position
    // are not destroyed when switching the sidebar selection.

    private var iPadSplitView: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Plex")
            .listStyle(.sidebar)
        } detail: {
            ZStack {
                sectionLayer(.home) { HomeView() }
                sectionLayer(.libraries) { LibrariesView() }
                sectionLayer(.collections) { NavigationStack { CollectionsView() } }
                sectionLayer(.playlists) { NavigationStack { PlaylistsView() } }
                sectionLayer(.search) { SearchView() }
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
                    Label("Collections", systemImage: "square.stack.fill")
                }
                NavigationLink {
                    PlaylistsView()
                } label: {
                    Label("Playlists", systemImage: "music.note.list")
                }
            }
            .navigationTitle("More")
        }
    }
}
