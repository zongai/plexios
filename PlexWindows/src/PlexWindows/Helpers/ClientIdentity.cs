namespace PlexWindows.Helpers;

/// <summary>
/// Stable client identity for X-Plex-* headers. Matches iOS ClientIdentity semantics.
/// </summary>
public sealed class ClientIdentity
{
    public string ClientIdentifier { get; }
    public string Product { get; } = "Plex Windows Native";
    public string Version { get; }
    public string Platform { get; } = "Windows";
    public string PlatformVersion { get; }
    public string Device { get; }
    public string DeviceName { get; }
    public string DeviceVendor { get; } = "Microsoft";

    public ClientIdentity()
    {
        ClientIdentifier = LoadOrCreateId();
        Version = typeof(ClientIdentity).Assembly.GetName().Version?.ToString(3) ?? "0.1.0";
        PlatformVersion = Environment.OSVersion.Version.ToString();
        Device = Environment.Is64BitOperatingSystem ? "PC-x64" : "PC";
        DeviceName = Environment.MachineName;
    }

    public void ApplyTo(HttpRequestMessage request)
    {
        request.Headers.TryAddWithoutValidation("X-Plex-Client-Identifier", ClientIdentifier);
        request.Headers.TryAddWithoutValidation("X-Plex-Product", Product);
        request.Headers.TryAddWithoutValidation("X-Plex-Version", Version);
        request.Headers.TryAddWithoutValidation("X-Plex-Platform", Platform);
        request.Headers.TryAddWithoutValidation("X-Plex-Platform-Version", PlatformVersion);
        request.Headers.TryAddWithoutValidation("X-Plex-Device", Device);
        request.Headers.TryAddWithoutValidation("X-Plex-Device-Name", DeviceName);
        request.Headers.TryAddWithoutValidation("X-Plex-Device-Vendor", DeviceVendor);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
    }

    private static string LoadOrCreateId()
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PlexWindows",
            "client-id.txt");
        try
        {
            if (File.Exists(path))
            {
                var existing = File.ReadAllText(path).Trim();
                if (!string.IsNullOrEmpty(existing)) return existing;
            }
        }
        catch { /* create new */ }

        var id = Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, id);
        }
        catch { /* non-fatal */ }
        return id;
    }
}
