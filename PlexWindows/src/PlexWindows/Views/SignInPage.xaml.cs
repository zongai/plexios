using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.ViewModels;
using Windows.System;

namespace PlexWindows.Views;

public sealed partial class SignInPage : Page
{
    public SignInViewModel ViewModel { get; }

    public SignInPage()
    {
        ViewModel = App.Services.GetRequiredService<SignInViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    private async void SignIn_Click(object sender, RoutedEventArgs e)
    {
        await ViewModel.StartSignInAsync();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.Cancel();
    }

    private async void OpenLink_Click(object sender, RoutedEventArgs e)
    {
        await Launcher.LaunchUriAsync(ViewModel.LinkUrl);
    }
}
