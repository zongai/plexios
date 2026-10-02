using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class SettingsPage : Page
{
    public SettingsViewModel ViewModel { get; }

    public SettingsPage()
    {
        ViewModel = App.Services.GetRequiredService<SettingsViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    private void Save_Click(object sender, RoutedEventArgs e) => ViewModel.Save();
    private void ClearCache_Click(object sender, RoutedEventArgs e) => ViewModel.ClearImageCache();
    private void SignOut_Click(object sender, RoutedEventArgs e) => ViewModel.SignOut();
}
