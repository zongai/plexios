using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Dispatching;
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
/// All observable state changes are marshalled to the UI dispatcher when available.
/// </summary>
public partial class AuthenticationService : ObservableObject
{
    private readonly PlexApiClient _api;
    private CancellationTokenSource? _pollCts;
    private DispatcherQueue? _uiQueue;

    [ObservableProperty] private AuthState _state = AuthState.Unknown;
    [ObservableProperty] private string? _authToken;
    [ObservableProperty] private string? _pinCode;
    [ObservableProperty] private string? _lastError;

    public AuthenticationService(PlexApiClient api)
    {
        _api = api;
    }

    /// <summary>Call once from the UI thread (e.g. MainWindow) so poll completion is safe.</summary>
    public void AttachUiDispatcher(DispatcherQueue queue) => _uiQueue = queue;

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
        try
        {
            var token = SecureStorage.LoadToken();
            if (!string.IsNullOrEmpty(token))
            {
                AuthToken = token;
                SetState(AuthState.SignedIn);
            }
            else
            {
                SetState(AuthState.SignedOut);
            }
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            SetState(AuthState.SignedOut);
        }
        await Task.CompletedTask;
    }

    public async Task StartPinSignInAsync(CancellationToken ct = default)
    {
        CancelPolling();
        LastError = null;
        try
        {
            var pin = await _api.CreatePinAsync(ct).ConfigureAwait(false);
            await RunOnUiAsync(() =>
            {
                PinCode = pin.Code;
                SetState(AuthState.SigningIn);
            }).ConfigureAwait(false);
            _ = PollUntilClaimedAsync(pin.Id, pin.Code);
        }
        catch (Exception ex)
        {
            await RunOnUiAsync(() =>
            {
                LastError = ex.Message;
                SetState(AuthState.SignedOut);
            }).ConfigureAwait(false);
            throw;
        }
    }

    public void CancelSignIn()
    {
        CancelPolling();
        if (State == AuthState.SigningIn)
            SetState(AuthState.SignedOut);
        PinCode = null;
    }

    public void SignOut()
    {
        CancelPolling();
        AuthToken = null;
        PinCode = null;
        SetState(AuthState.SignedOut);
        try { SecureStorage.ClearToken(); } catch { /* best effort */ }
    }

    private async Task PollUntilClaimedAsync(int pinId, string code)
    {
        _pollCts = new CancellationTokenSource();
        var ct = _pollCts.Token;
        try
        {
            while (!ct.IsCancellationRequested)
            {
                await Task.Delay(1500, ct).ConfigureAwait(false);
                var pin = await _api.CheckPinAsync(pinId, code, ct).ConfigureAwait(false);
                if (string.IsNullOrEmpty(pin.AuthToken))
                    continue;

                // Persist first, then publish SignedIn on UI thread
                try
                {
                    SecureStorage.SaveToken(pin.AuthToken);
                }
                catch (Exception ex)
                {
                    await RunOnUiAsync(() =>
                    {
                        LastError = "Failed to save token: " + ex.Message;
                        SetState(AuthState.SignedOut);
                    }).ConfigureAwait(false);
                    return;
                }

                await RunOnUiAsync(() =>
                {
                    AuthToken = pin.AuthToken;
                    PinCode = null;
                    LastError = null;
                    SetState(AuthState.SignedIn);
                }).ConfigureAwait(false);
                return;
            }
        }
        catch (OperationCanceledException)
        {
            // cancelled
        }
        catch (Exception ex)
        {
            await RunOnUiAsync(() =>
            {
                LastError = ex.Message;
                SetState(AuthState.SignedOut);
            }).ConfigureAwait(false);
        }
    }

    private void SetState(AuthState state)
    {
        // Always assign on the UI dispatcher when we have one, so PropertyChanged
        // subscribers (navigation) never run off-thread.
        if (_uiQueue is { } q && !q.HasThreadAccess)
        {
            q.TryEnqueue(() => State = state);
        }
        else
        {
            State = state;
        }
    }

    private Task RunOnUiAsync(Action action)
    {
        if (_uiQueue is null || _uiQueue.HasThreadAccess)
        {
            action();
            return Task.CompletedTask;
        }

        var tcs = new TaskCompletionSource();
        var ok = _uiQueue.TryEnqueue(() =>
        {
            try
            {
                action();
                tcs.SetResult();
            }
            catch (Exception ex)
            {
                tcs.SetException(ex);
            }
        });
        if (!ok)
        {
            action();
            return Task.CompletedTask;
        }
        return tcs.Task;
    }

    private void CancelPolling()
    {
        try
        {
            _pollCts?.Cancel();
            _pollCts?.Dispose();
        }
        catch
        {
            // ignore
        }
        _pollCts = null;
    }
}
