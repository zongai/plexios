using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using PlexWindows.Helpers;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Auth;
using PlexWindows.Plex.Server;
using PlexWindows.Playback;
using PlexWindows.Services;
using PlexWindows.ViewModels;

namespace PlexWindows;

public partial class App : Application
{
    private Window? _window;
    public static IServiceProvider Services { get; private set; } = null!;
    public static Window? MainAppWindow => ((App)Current)._window;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
        Services = ConfigureServices();
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        // Keep process alive when possible so the user does not just see a black flash
        System.Diagnostics.Debug.WriteLine("Unhandled: " + e.Exception);
        try
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PlexWindows",
                "crash.log");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.AppendAllText(path,
                DateTimeOffset.Now + Environment.NewLine + e.Exception + Environment.NewLine + Environment.NewLine);
        }
        catch
        {
            // ignore
        }
        e.Handled = true;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }

    private static IServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();

        services.AddSingleton<ClientIdentity>();
        services.AddSingleton(_ =>
        {
            var handler = new HttpClientHandler
            {
                ServerCertificateCustomValidationCallback =
                    HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
            };
            return new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30) };
        });
        services.AddSingleton<PlexApiClient>();
        services.AddSingleton<PlaybackUrlBuilder>();
        services.AddSingleton<TimelineReporter>();

        services.AddSingleton<AuthenticationService>();
        services.AddSingleton<ConnectionManager>();
        services.AddSingleton<PlaybackDecisionEngine>();
        services.AddSingleton<AppSettings>();
        services.AddTransient<IPlayerEngine>(sp =>
        {
            var settings = sp.GetRequiredService<AppSettings>();
            return new PlayerEngineRouter(settings.PlayerBackend);
        });

        services.AddTransient<SignInViewModel>();
        services.AddTransient<HomeViewModel>();
        services.AddTransient<ShellViewModel>();
        services.AddTransient<LibrariesViewModel>();
        services.AddTransient<DetailViewModel>();
        services.AddTransient<SearchViewModel>();
        services.AddTransient<PlayerViewModel>();
        services.AddTransient<CollectionsViewModel>();
        services.AddTransient<PlaylistsViewModel>();
        services.AddTransient<SettingsViewModel>();
        services.AddTransient<FavoritesViewModel>();

        return services.BuildServiceProvider();
    }
}
