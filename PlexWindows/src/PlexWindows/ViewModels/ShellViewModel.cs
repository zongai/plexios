using CommunityToolkit.Mvvm.ComponentModel;
using PlexWindows.Plex.Auth;
using PlexWindows.Plex.Server;

namespace PlexWindows.ViewModels;

public partial class ShellViewModel : ObservableObject
{
    private readonly AuthenticationService _auth;
    private readonly ConnectionManager _connections;

    [ObservableProperty] private string _activeServerName = "No server";
    [ObservableProperty] private bool _isLoading;

    public ShellViewModel(AuthenticationService auth, ConnectionManager connections)
    {
        _auth = auth;
        _connections = connections;
        _connections.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(ConnectionManager.ActiveServer))
                ActiveServerName = _connections.ActiveServer?.Name ?? "No server";
        };
    }

    public async Task InitializeAsync()
    {
        if (string.IsNullOrEmpty(_auth.AuthToken)) return;
        IsLoading = true;
        try
        {
            await _connections.DiscoverAsync(_auth.AuthToken);
            ActiveServerName = _connections.ActiveServer?.Name ?? "No server";
        }
        finally
        {
            IsLoading = false;
        }
    }
}
