using PlexWindows.Models;

namespace PlexWindows.Helpers;

/// <summary>
/// Builds absolute Plex image URLs (thumb / art) against the active server.
/// </summary>
public static class PlexImage
{
    public static Uri? Thumb(ServerContext? ctx, string? path, int width = 300, int height = 450)
    {
        if (ctx is null || string.IsNullOrEmpty(path)) return null;
        // path is typically "/library/metadata/.../thumb/..."
        var transcode = $"/photo/:/transcode?width={width}&height={height}&minSize=1&upscale=1&url={Uri.EscapeDataString(path)}&X-Plex-Token={Uri.EscapeDataString(ctx.Token)}";
        return new Uri(ctx.BaseUrl, transcode.TrimStart('/'));
    }

    public static Uri? Art(ServerContext? ctx, string? path, int width = 1280, int height = 720)
        => Thumb(ctx, path, width, height);

    public static Uri? Direct(ServerContext? ctx, string? path)
    {
        if (ctx is null || string.IsNullOrEmpty(path)) return null;
        var ub = new UriBuilder(new Uri(ctx.BaseUrl, path.TrimStart('/')));
        var sep = string.IsNullOrEmpty(ub.Query) ? "?" : "&";
        ub.Query = ub.Query.TrimStart('?') + $"{sep}X-Plex-Token={Uri.EscapeDataString(ctx.Token)}";
        return ub.Uri;
    }
}
