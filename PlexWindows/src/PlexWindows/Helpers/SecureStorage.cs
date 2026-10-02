using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace PlexWindows.Helpers;

/// <summary>
/// Windows secure storage for Plex auth token.
/// Uses DPAPI (CurrentUser) so the token is encrypted to the logged-in user.
/// Never writes the token in plain text.
/// </summary>
public static class SecureStorage
{
    private static readonly string StorePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PlexWindows",
        "auth.dat");

    public static void SaveToken(string token)
    {
        ArgumentException.ThrowIfNullOrEmpty(token);
        var dir = Path.GetDirectoryName(StorePath)!;
        Directory.CreateDirectory(dir);

        var plain = Encoding.UTF8.GetBytes(token);
        var encrypted = ProtectedData.Protect(plain, optionalEntropy: null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(StorePath, encrypted);
    }

    public static string? LoadToken()
    {
        if (!File.Exists(StorePath)) return null;
        try
        {
            var encrypted = File.ReadAllBytes(StorePath);
            var plain = ProtectedData.Unprotect(encrypted, optionalEntropy: null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException)
        {
            // Corrupted or different user — treat as signed out
            TryDelete();
            return null;
        }
    }

    public static void ClearToken() => TryDelete();

    private static void TryDelete()
    {
        try
        {
            if (File.Exists(StorePath)) File.Delete(StorePath);
        }
        catch
        {
            // best-effort
        }
    }
}
