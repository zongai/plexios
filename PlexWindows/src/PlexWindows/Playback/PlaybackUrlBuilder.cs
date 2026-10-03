using PlexWindows.Helpers;
using PlexWindows.Plex.Server;
using PlexWindows.Models;

namespace PlexWindows.Playback;

/// <summary>
/// Builds Direct Play / Direct Stream / Transcode URLs against PMS.
/// Query parameters aligned with iOS PlaybackURLBuilder.
/// </summary>
public sealed class PlaybackUrlBuilder
{
    private readonly ClientIdentity _identity;

    public PlaybackUrlBuilder(ClientIdentity identity)
    {
        _identity = identity;
    }

    public Uri Build(
        ServerContext context,
        PlexMetadata metadata,
        PlaybackDecision decision,
        NetworkClass network = NetworkClass.Unknown,
        long offsetMs = 0,
        string? sessionId = null)
    {
        // Prefer LAN HTTP when context is plex.direct HTTPS (LibVLC gnutls is unreliable)
        var syn = ConnectionManager.TrySynthesizeLanHttp(context.BaseUrl);
        if (syn is not null && context.BaseUrl.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase))
        {
            AppDebugLog.Info("UrlBuilder", $"plex.direct → LAN HTTP {context.BaseUrl} → {syn}");
            context = context with { BaseUrl = syn };
        }

        if (decision.Mode == PlaybackMode.DirectPlay &&
            TryGetPart(metadata, decision.MediaIndex, decision.PartIndex, out var part) &&
            !string.IsNullOrEmpty(part.Key))
        {
            return BuildDirectPlay(context, part);
        }

        return BuildTranscode(
            context,
            metadata,
            decision,
            directStream: decision.Mode == PlaybackMode.DirectStream,
            network,
            offsetMs,
            sessionId ?? Guid.NewGuid().ToString("N"));
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
        bool directStream,
        NetworkClass network,
        long offsetMs,
        string sessionId)
    {
        var path = "video/:/transcode/universal/start.m3u8";
        var baseUri = new Uri(context.BaseUrl, path);
        var mediaPath = string.IsNullOrEmpty(metadata.Key)
            ? $"/library/metadata/{metadata.RatingKey}"
            : metadata.Key;

        // Advertise codecs LibVLC can handle so PMS remuxes/transcodes appropriately.
        // Prefer H.264 in HLS for maximum compatibility when full transcode is requested.
        var videoCodecs = directStream
            ? "h264,hevc,mpeg4,mpeg2video,vp8,vp9"
            : "h264";
        var audioCodecs = directStream
            ? "aac,mp3,ac3,eac3,flac,opus,pcm"
            : "aac,mp3";
        var subtitleCodecs = "srt,vtt,ass,ssa";

        var q = new Dictionary<string, string>
        {
            ["path"] = mediaPath,
            ["mediaIndex"] = decision.MediaIndex.ToString(),
            ["partIndex"] = decision.PartIndex.ToString(),
            ["protocol"] = "hls",
            ["fastSeek"] = "1",
            ["directPlay"] = "0",
            ["directStream"] = directStream ? "1" : "0",
            ["directStreamAudio"] = directStream ? "1" : "0",
            ["videoCodecs"] = videoCodecs,
            ["audioCodecs"] = audioCodecs,
            ["subtitleCodecs"] = subtitleCodecs,
            ["session"] = sessionId,
            ["offset"] = Math.Max(0, offsetMs).ToString(),
            ["copyts"] = "1",
            ["location"] = network == NetworkClass.Local ? "lan" : "wan",
            ["X-Plex-Token"] = context.Token,
            ["X-Plex-Client-Identifier"] = _identity.ClientIdentifier,
            ["X-Plex-Product"] = _identity.Product,
            ["X-Plex-Platform"] = _identity.Platform,
            ["X-Plex-Platform-Version"] = _identity.PlatformVersion,
            ["X-Plex-Device"] = _identity.Device,
            ["X-Plex-Device-Name"] = _identity.DeviceName,
            ["X-Plex-Version"] = _identity.Version,
        };

        if (decision.BurnInSubtitles)
        {
            q["subtitles"] = "burn";
            q["advancedSubtitles"] = "burn";
        }
        else if (decision.SelectedSubtitleStreamId is not null)
        {
            q["subtitles"] = "segmented";
            q["advancedSubtitles"] = "text";
        }
        else
        {
            q["subtitles"] = "none";
        }

        if (decision.SelectedAudioStreamId is int audioId)
            q["audioStreamID"] = audioId.ToString();
        if (decision.SelectedSubtitleStreamId is int subId)
            q["subtitleStreamID"] = subId.ToString();
        if (decision.MaxBitrateKbps is int br)
        {
            q["maxVideoBitrate"] = br.ToString();
            q["videoQuality"] = "100";
        }

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
