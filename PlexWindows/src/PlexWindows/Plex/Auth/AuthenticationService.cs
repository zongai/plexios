using CommunityToolkit.Mvvm.ComponentModel;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;

namespace PlexWindows.Plex.Auth;

public enum AuthState
{
    Unknown,
    SignedOut,
    SigningIn,
    SignedIn
}

/// <summary>
/// PIN authentication flow. Token stored via DPAPI (SecureStorage).
/// Matches iOS AuthenticationService behavior.
/// </summary>
public partial class AuthenticationService : ObservableObject
{
    private readonly PlexApiClient _api;
    private CancellationTokenSource? _pollCts;

    [ObservableProperty] private AuthState _state = AuthState.Unknown;
    [ObservableProperty] private string? _authToken;
    [ObservableProperty] private string? _pinCode;
    [ObservableProperty] private string? _lastError;

    public AuthenticationService(PlexApiClient api)
    {
        _api = api;
    }

    public Uri LinkUrl
    {
        get
        {
            if (string.IsNullOrEmpty(PinCode))
                return new Uri("https://plex.tv/link");
            return new Uri($"https://plex.tv/link?pin={Uri.EscapeDataString(PinCode)}");
        }
    }

    public async Task RestoreSessionAsync()
    {
        var token = SecureStorage.LoadToken();
        if (!string.IsNullOrEmpty(token))
        {
            AuthToken = token;
            State = AuthState.SignedIn;
        }
        else
        {
            State = AuthState.SignedOut;
        }
        await Task.CompletedTask;
    }

    public async Task StartPinSignInAsync(CancellationToken ct = default)
    {
        CancelPolling();
        LastError = null;
        try
        {
            var pin = await _api.CreatePinAsync(ct).ConfigureAwait(true);
            PinCode = pin.Code;
            State = AuthState.SigningIn;
            _ = PollUntilClaimedAsync(pin.Id, pin.Code);
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            State = AuthState.SignedOut;
            throw;
        }
    }

    public void CancelSignIn()
    {
        CancelPolling();
        if (State == AuthState.SigningIn)
            State = AuthState.SignedOut;
        PinCode = null;
    }

    public void SignOut()
    {
        CancelPolling();
        AuthToken = null;
        PinCode = null;
        State = AuthState.SignedOut;
        SecureStorage.ClearToken();
    }

    private async Task PollUntilClaimedAsync(int pinId, string code)
    {
        _pollCts = new CancellationTokenSource();
        var ct = _pollCts.Token;
        try
        {
            while (!ct.IsCancellationRequested)
            {
                await Task.Delay(1500, ct).ConfigureAwait(true);
                var pin = await _api.CheckPinAsync(pinId, code, ct).ConfigureAwait(true);
                if (!string.IsNullOrEmpty(pin.AuthToken))
                {
                    AuthToken = pin.AuthToken;
                    SecureStorage.SaveToken(pin.AuthToken);
                    PinCode = null;
                    State = AuthState.SignedIn;
                    return;
                }
            }
        }
        catch (OperationCanceledException)
        {
            // cancelled
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            State = AuthState.SignedOut;
        }
    }

    private void CancelPolling()
    {
        _pollCts?.Cancel();
        _pollCts?.Dispose();
        _pollCts = null;
    }
}
