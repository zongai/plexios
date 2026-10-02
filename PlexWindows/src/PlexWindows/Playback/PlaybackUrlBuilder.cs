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
        var media = metadata.Media[decision.MediaIndex];
        var part = media.Parts[decision.PartIndex];

        return decision.Mode switch
        {
            PlaybackMode.DirectPlay => BuildDirectPlay(context, part),
            PlaybackMode.DirectStream => BuildTranscode(context, metadata, decision, directStream: true),
            _ => BuildTranscode(context, metadata, decision, directStream: false)
        };
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
        var q = new Dictionary<string, string>
        {
            ["path"] = metadata.Key,
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

