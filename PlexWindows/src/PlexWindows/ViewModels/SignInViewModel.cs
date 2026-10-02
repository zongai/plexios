using CommunityToolkit.Mvvm.ComponentModel;
using PlexWindows.Plex.Auth;

namespace PlexWindows.ViewModels;

public partial class SignInViewModel : ObservableObject
{
    private readonly AuthenticationService _auth;

    [ObservableProperty] private string? _pinCode;
    [ObservableProperty] private string? _errorMessage;
    [ObservableProperty] private bool _isSigningIn;
    [ObservableProperty] private bool _showStartButton = true;

    public Uri LinkUrl => _auth.LinkUrl;

    public SignInViewModel(AuthenticationService auth)
    {
        _auth = auth;
        _auth.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AuthenticationService.PinCode))
                PinCode = _auth.PinCode;
            if (e.PropertyName == nameof(AuthenticationService.State))
            {
                IsSigningIn = _auth.State == AuthState.SigningIn;
                ShowStartButton = _auth.State is AuthState.SignedOut or AuthState.Unknown;
            }
            if (e.PropertyName == nameof(AuthenticationService.LastError))
                ErrorMessage = _auth.LastError;
        };
    }

    public async Task StartSignInAsync()
    {
        ErrorMessage = null;
        try
        {
            await _auth.StartPinSignInAsync();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }

    public void Cancel() => _auth.CancelSignIn();
}
