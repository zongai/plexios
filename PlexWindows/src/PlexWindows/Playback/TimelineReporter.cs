using PlexWindows.Helpers;
using PlexWindows.Models;

namespace PlexWindows.Playback;

/// <summary>
/// Reports playback progress to PMS (rate-limited). Failures never stop local playback.
/// </summary>
public sealed class TimelineReporter
{
    private readonly HttpClient _http;
    private readonly ClientIdentity _identity;
    private DateTimeOffset _lastReport = DateTimeOffset.MinValue;
    private static readonly TimeSpan MinInterval = TimeSpan.FromSeconds(10);

    public TimelineReporter(HttpClient http, ClientIdentity identity)
    {
        _http = http;
        _identity = identity;
    }

    public async Task ReportAsync(
        ServerContext context,
        string ratingKey,
        long positionMs,
        long durationMs,
        string state, // playing | paused | stopped | buffering
        CancellationToken ct = default)
    {
        var now = DateTimeOffset.UtcNow;
        if (state is "playing" or "buffering" && now - _lastReport < MinInterval)
            return;

        try
        {
            // PMS timeline endpoint
            var path =
                $":/timeline?ratingKey={Uri.EscapeDataString(ratingKey)}" +
                $"&key={Uri.EscapeDataString("/library/metadata/" + ratingKey)}" +
                $"&state={Uri.EscapeDataString(state)}" +
                $"&time={positionMs}&duration={durationMs}" +
                $"&X-Plex-Token={Uri.EscapeDataString(context.Token)}" +
                $"&X-Plex-Client-Identifier={Uri.EscapeDataString(_identity.ClientIdentifier)}" +
                $"&X-Plex-Product={Uri.EscapeDataString(_identity.Product)}" +
                $"&X-Plex-Platform={Uri.EscapeDataString(_identity.Platform)}";

            var url = new Uri(context.BaseUrl, path);
            using var req = new HttpRequestMessage(HttpMethod.Post, url);
            _identity.ApplyTo(req);
            req.Headers.TryAddWithoutValidation("X-Plex-Token", context.Token);
            using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
            // Ignore non-success — reporting must not break playback
            _lastReport = now;
        }
        catch
        {
            // swallow
        }
    }
}
