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
        ExtendsContentIntoTitleBar = true;
        try
        {
            // Dark content root so we never show an empty transparent hole
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
            // Critical: poll completion and State changes must marshal to this queue
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
            // Last-resort: show sign-in with error instead of a black window
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
            // SigningIn: stay on current page (SignIn shows PIN)
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("NavigateForState failed: " + ex);
        }
    }
}
