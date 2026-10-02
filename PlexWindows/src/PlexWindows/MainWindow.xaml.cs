using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.Plex.Auth;
using PlexWindows.Views;

namespace PlexWindows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        // Content draws under the title bar chrome, but only inside AppTitleBar.
        // SetTitleBar reserves the caption-button region so UI never overlaps min/max/close.
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        try
        {
            if (Content is FrameworkElement root)
                root.RequestedTheme = ElementTheme.Dark;
        }
        catch
        {
            // ignore
        }

        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            var auth = App.Services.GetRequiredService<AuthenticationService>();
            auth.AttachUiDispatcher(DispatcherQueue);

            await auth.RestoreSessionAsync().ConfigureAwait(true);

            NavigateForState(auth.State);

            auth.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName != nameof(AuthenticationService.State)) return;
                DispatcherQueue.TryEnqueue(() => NavigateForState(auth.State));
            };
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("MainWindow.InitializeAsync failed: " + ex);
            try
            {
                RootFrame.Navigate(typeof(SignInPage));
            }
            catch
            {
                // nothing more we can do
            }
        }
    }

    private void NavigateForState(AuthState state)
    {
        try
        {
            if (state == AuthState.SignedIn)
            {
                if (RootFrame.Content is ShellPage) return;
                RootFrame.Navigate(typeof(ShellPage));
            }
            else if (state is AuthState.SignedOut or AuthState.Unknown)
            {
                if (RootFrame.Content is SignInPage) return;
                RootFrame.Navigate(typeof(SignInPage));
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("NavigateForState failed: " + ex);
        }
    }
}
