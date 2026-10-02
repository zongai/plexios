using Microsoft.UI.Xaml.Media.Imaging;
using PlexWindows.Models;

namespace PlexWindows.Helpers;

/// <summary>
/// Builds BitmapImage sources for Plex posters/art with tokenized URLs.
/// Keeps a small in-memory URI→BitmapImage cache to avoid re-decoding while scrolling.
/// </summary>
public static class PosterImageLoader
{
    private static readonly Dictionary<string, BitmapImage> Cache = new(StringComparer.Ordinal);
    private static readonly object Gate = new();
    private const int MaxCache = 256;

    public static BitmapImage? GetThumb(ServerContext? ctx, string? path, int width = 300, int height = 450)
    {
        var uri = PlexImage.Thumb(ctx, path, width, height);
        return FromUri(uri);
    }

    public static BitmapImage? GetArt(ServerContext? ctx, string? path, int width = 1280, int height = 720)
    {
        var uri = PlexImage.Art(ctx, path, width, height);
        return FromUri(uri);
    }

    public static BitmapImage? FromUri(Uri? uri)
    {
        if (uri is null) return null;
        var key = uri.AbsoluteUri;
        lock (Gate)
        {
            if (Cache.TryGetValue(key, out var hit)) return hit;
            if (Cache.Count >= MaxCache)
            {
                // Simple eviction: clear half
                foreach (var k in Cache.Keys.Take(MaxCache / 2).ToList())
                    Cache.Remove(k);
            }
            var bmp = new BitmapImage(uri)
            {
                DecodePixelType = DecodePixelType.Logical,
                DecodePixelWidth = 300
            };
            Cache[key] = bmp;
            return bmp;
        }
    }

    public static void Clear()
    {
        lock (Gate) Cache.Clear();
    }
}

/// <summary>Lightweight card model with resolved poster for binding.</summary>
public sealed class MediaCardItem
{
    public required PlexMetadata Metadata { get; init; }
    public BitmapImage? Poster { get; init; }
    public string Title => Metadata.Title;
    public string? Year => Metadata.Year?.ToString();
    public string RatingKey => Metadata.RatingKey;
}
