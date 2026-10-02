using PlexWindows.Helpers;
using PlexWindows.Models;

namespace PlexWindows.Playback;

/// <summary>
/// Builds Direct Play / Direct Stream / Transcode URLs against PMS.
/// Semantics aligned with iOS PlaybackURLBuilder.
/// </summary>
public sealed class PlaybackUrlBuilder
{
    private readonly ClientIdentity _identity;

    public PlaybackUrlBuilder(ClientIdentity identity)
    {
        _identity = identity;
    }

    public Uri Build(ServerContext context, PlexMetadata metadata, PlaybackDecision decision)
    {
        // Prefer Direct Play only when media/part indices are valid
        if (decision.Mode == PlaybackMode.DirectPlay &&
            TryGetPart(metadata, decision.MediaIndex, decision.PartIndex, out var part) &&
            !string.IsNullOrEmpty(part.Key))
        {
            return BuildDirectPlay(context, part);
        }

        // DirectStream / Transcode (or DirectPlay fallback when no part key)
        return BuildTranscode(
            context,
            metadata,
            decision,
            directStream: decision.Mode == PlaybackMode.DirectStream);
    }

    private static bool TryGetPart(
        PlexMetadata metadata,
        int mediaIndex,
        int partIndex,
        out PlexPart part)
    {
        part = null!;
        if (metadata.Media is null || metadata.Media.Count == 0)
            return false;
        var mi = Math.Clamp(mediaIndex, 0, metadata.Media.Count - 1);
        var media = metadata.Media[mi];
        if (media.Parts is null || media.Parts.Count == 0)
            return false;
        var pi = Math.Clamp(partIndex, 0, media.Parts.Count - 1);
        part = media.Parts[pi];
        return true;
    }

    private Uri BuildDirectPlay(ServerContext context, PlexPart part)
    {
        var path = part.Key.TrimStart('/');
        var baseUri = new Uri(context.BaseUrl, path);
        return AppendQuery(baseUri, new Dictionary<string, string>
        {
            ["X-Plex-Token"] = context.Token,
            ["X-Plex-Client-Identifier"] = _identity.ClientIdentifier
        });
    }

    private Uri BuildTranscode(
        ServerContext context,
        PlexMetadata metadata,
        PlaybackDecision decision,
        bool directStream)
    {
        var path = "video/:/transcode/universal/start.m3u8";
        var baseUri = new Uri(context.BaseUrl, path);
        // metadata.Key is like /library/metadata/123 — required by universal transcoder
        var mediaPath = string.IsNullOrEmpty(metadata.Key)
            ? $"/library/metadata/{metadata.RatingKey}"
            : metadata.Key;
        var q = new Dictionary<string, string>
        {
            ["path"] = mediaPath,
            ["mediaIndex"] = decision.MediaIndex.ToString(),
            ["partIndex"] = decision.PartIndex.ToString(),
            ["protocol"] = "hls",
            ["fastSeek"] = "1",
            ["directPlay"] = "0",
            ["directStream"] = directStream ? "1" : "0",
            ["subtitleSize"] = "100",
            ["X-Plex-Token"] = context.Token,
            ["X-Plex-Client-Identifier"] = _identity.ClientIdentifier,
            ["X-Plex-Product"] = _identity.Product,
            ["X-Plex-Platform"] = _identity.Platform,
            ["subtitles"] = decision.BurnInSubtitles ? "burn" : "auto",
            ["subtitleStreamID"] = decision.SelectedSubtitleStreamId?.ToString() ?? "0"
        };
        if (decision.SelectedAudioStreamId is int audioId)
            q["audioStreamID"] = audioId.ToString();
        if (decision.MaxBitrateKbps is int br)
            q["maxVideoBitrate"] = br.ToString();
        return AppendQuery(baseUri, q);
    }

    private static Uri AppendQuery(Uri baseUri, Dictionary<string, string> parameters)
    {
        var ub = new UriBuilder(baseUri);
        var parts = parameters.Select(kv =>
            $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}");
        ub.Query = string.Join("&", parts);
        return ub.Uri;
    }
}
