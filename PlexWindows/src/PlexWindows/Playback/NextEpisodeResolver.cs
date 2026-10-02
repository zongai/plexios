using PlexWindows.Models;
using PlexWindows.Plex.Api;

namespace PlexWindows.Playback;

/// <summary>
/// Resolves the next episode after playback completes (same-season then cross-season).
/// Matches iOS next-episode semantics.
/// </summary>
public static class NextEpisodeResolver
{
    public static async Task<PlexMetadata?> FindNextAsync(
        PlexApiClient api,
        ServerContext context,
        PlexMetadata current,
        CancellationToken ct = default)
    {
        if (current.Type != PlexMetadataType.Episode)
            return null;

        // 1) Siblings in the same season (parent)
        if (!string.IsNullOrEmpty(current.ParentRatingKey))
        {
            var siblings = await api.FetchChildrenAsync(current.ParentRatingKey, context.BaseUrl, context.Token, ct)
                .ConfigureAwait(false);
            var ordered = siblings
                .Where(e => e.Type == PlexMetadataType.Episode)
                .OrderBy(e => e.Index ?? int.MaxValue)
                .ToList();
            var idx = ordered.FindIndex(e => e.RatingKey == current.RatingKey);
            if (idx >= 0 && idx + 1 < ordered.Count)
                return ordered[idx + 1];
        }

        // 2) Next season → first episode
        if (!string.IsNullOrEmpty(current.GrandparentRatingKey))
        {
            var seasons = await api.FetchChildrenAsync(current.GrandparentRatingKey, context.BaseUrl, context.Token, ct)
                .ConfigureAwait(false);
            var seasonList = seasons
                .Where(s => s.Type == PlexMetadataType.Season)
                .OrderBy(s => s.Index ?? int.MaxValue)
                .ToList();
            var currentSeasonIndex = current.ParentIndex ?? current.Index;
            var nextSeason = seasonList.FirstOrDefault(s =>
                (s.Index ?? int.MinValue) > (currentSeasonIndex ?? int.MinValue));
            if (nextSeason is null) return null;

            var episodes = await api.FetchChildrenAsync(nextSeason.RatingKey, context.BaseUrl, context.Token, ct)
                .ConfigureAwait(false);
            return episodes
                .Where(e => e.Type == PlexMetadataType.Episode)
                .OrderBy(e => e.Index ?? int.MaxValue)
                .FirstOrDefault();
        }

        return null;
    }
}
