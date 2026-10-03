using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using PlexWindows.Models;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class SettingsPage : Page
{
    public SettingsViewModel ViewModel { get; }

    public SettingsPage()
    {
        ViewModel = App.Services.GetRequiredService<SettingsViewModel>();
        InitializeComponent();
        Loaded += (_, _) => ViewModel.Load();
    }

    private void Save_Click(object sender, RoutedEventArgs e) => ViewModel.Save();

    private void ClearCache_Click(object sender, RoutedEventArgs e) => ViewModel.ClearImageCache();

    private void SignOut_Click(object sender, RoutedEventArgs e) => ViewModel.SignOut();

    private async void RefreshServers_Click(object sender, RoutedEventArgs e) =>
        await ViewModel.RefreshServersAsync();

    private void Server_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: PlexServer server })
            ViewModel.SelectServer(server);
    }
}
