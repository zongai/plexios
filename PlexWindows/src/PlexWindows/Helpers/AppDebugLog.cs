using System.Text;

namespace PlexWindows.Helpers;

/// <summary>
/// Append-only debug log under %LocalAppData%\PlexWindows\logs\debug-YYYYMMDD.log
/// Token values are partially redacted.
/// </summary>
public static class AppDebugLog
{
    private static readonly object Gate = new();
    private static string? _path;

    public static string LogDirectory
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PlexWindows", "logs");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string CurrentLogPath
    {
        get
        {
            if (_path is not null) return _path;
            _path = Path.Combine(LogDirectory, $"debug-{DateTime.Now:yyyyMMdd}.log");
            return _path;
        }
    }

    public static void Info(string area, string message) => Write("INFO", area, message);
    public static void Warn(string area, string message) => Write("WARN", area, message);
    public static void Error(string area, string message) => Write("ERROR", area, message);

    public static void Error(string area, Exception ex, string? message = null)
        => Write("ERROR", area, (message is null ? "" : message + " | ") + ex.GetType().Name + ": " + ex.Message);

    public static string RedactUrl(string? url)
    {
        if (string.IsNullOrEmpty(url)) return "";
        // Redact X-Plex-Token values
        return System.Text.RegularExpressions.Regex.Replace(
            url,
            @"(X-Plex-Token=)[^&\s]+",
            "$1***",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    }

    private static void Write(string level, string area, string message)
    {
        try
        {
            var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{level}] [{area}] {message}{Environment.NewLine}";
            lock (Gate)
            {
                File.AppendAllText(CurrentLogPath, line, Encoding.UTF8);
            }
        }
        catch
        {
            // never throw from logger
        }
    }
}
