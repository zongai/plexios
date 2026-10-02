using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using PlexWindows.Plex.Auth;
using PlexWindows.Views;

namespace PlexWindows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        var auth = App.Services.GetRequiredService<AuthenticationService>();
        await auth.RestoreSessionAsync();

        if (auth.State == AuthState.SignedIn)
        {
            RootFrame.Navigate(typeof(ShellPage));
        }
        else
        {
            RootFrame.Navigate(typeof(SignInPage));
        }

        auth.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(AuthenticationService.State)) return;
            DispatcherQueue.TryEnqueue(() =>
            {
                if (auth.State == AuthState.SignedIn)
                    RootFrame.Navigate(typeof(ShellPage));
                else if (auth.State == AuthState.SignedOut)
                    RootFrame.Navigate(typeof(SignInPage));
            });
        };
    }
}
