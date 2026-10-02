using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.Models;
using PlexWindows.Plex.Auth;
using PlexWindows.Plex.Server;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class ShellPage : Page
{
    public ShellViewModel ViewModel { get; }

    public ShellPage()
    {
        ViewModel = App.Services.GetRequiredService<ShellViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
        Loaded += async (_, _) => await ViewModel.InitializeAsync();
        ContentFrame.Navigate(typeof(HomePage));
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(SettingsPage));
            return;
        }

        if (args.SelectedItem is not NavigationViewItem item) return;
        var tag = item.Tag as string;
        switch (tag)
        {
            case "home":
                ContentFrame.Navigate(typeof(HomePage));
                break;
            case "movies":
                ContentFrame.Navigate(typeof(LibrariesPage), PlexLibraryType.Movie);
                break;
            case "shows":
                ContentFrame.Navigate(typeof(LibrariesPage), PlexLibraryType.Show);
                break;
            case "music":
                ContentFrame.Navigate(typeof(LibrariesPage), PlexLibraryType.Artist);
                break;
            case "collections":
                ContentFrame.Navigate(typeof(CollectionsPage));
                break;
            case "playlists":
                ContentFrame.Navigate(typeof(PlaylistsPage));
                break;
            case "favorites":
                ContentFrame.Navigate(typeof(FavoritesPage));
                break;
            case "signout":
                App.Services.GetRequiredService<AuthenticationService>().SignOut();
                break;
        }
    }

    private async void Servers_Click(object sender, RoutedEventArgs e)
    {
        var connections = App.Services.GetRequiredService<ConnectionManager>();
        var auth = App.Services.GetRequiredService<AuthenticationService>();

        if (!string.IsNullOrEmpty(auth.AuthToken))
            await connections.DiscoverAsync(auth.AuthToken);

        var list = new ListView
        {
            SelectionMode = ListViewSelectionMode.Single,
            Width = 420,
            MaxHeight = 360
        };

        foreach (var server in connections.Servers)
        {
            foreach (var conn in server.Connections.OrderBy(c => c.RankScore))
            {
                var label = $"{server.Name}  ·  {(conn.Local ? "LAN" : conn.Relay ? "Relay" : "Remote")}  ·  {conn.ProtocolName}://{conn.Address}:{conn.Port}";
                list.Items.Add(new ServerPickItem
                {
                    Label = label,
                    Server = server,
                    Connection = conn
                });
            }
        }

        list.ItemTemplate = null;
        // Display via ToString
        for (var i = 0; i < list.Items.Count; i++)
        {
            if (list.Items[i] is ServerPickItem pi)
            {
                // Prefer active
                if (connections.ActiveServer?.MachineIdentifier == pi.Server.MachineIdentifier &&
                    connections.ActiveServer?.PreferredConnection?.Uri == pi.Connection.Uri)
                    list.SelectedIndex = i;
            }
        }

        var dialog = new ContentDialog
        {
            Title = "Select server / connection",
            Content = list,
            PrimaryButtonText = "Use selected",
            CloseButtonText = "Cancel",
            XamlRoot = XamlRoot,
            DefaultButton = ContentDialogButton.Primary
        };

        // Simple text presentation
        list.DisplayMemberPath = nameof(ServerPickItem.Label);

        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary) return;
        if (list.SelectedItem is not ServerPickItem pick) return;

        connections.SelectConnection(pick.Server, pick.Connection);
        ViewModel.ActiveServerName = pick.Server.Name;
        // Refresh current page content
        if (ContentFrame.Content is HomePage)
            ContentFrame.Navigate(typeof(HomePage));
    }

    private void Search_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        ContentFrame.Navigate(typeof(SearchPage), args.QueryText);
    }

    private sealed class ServerPickItem
    {
        public required string Label { get; init; }
        public required PlexServer Server { get; init; }
        public required PlexConnection Connection { get; init; }
    }
}
