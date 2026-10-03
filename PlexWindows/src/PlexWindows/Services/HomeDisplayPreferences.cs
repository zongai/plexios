using PlexWindows.Models;

namespace PlexWindows.Services;

/// <summary>Home screen visibility — aligned with iOS HomeDisplayPreferences.</summary>
public sealed class HomeDisplayPreferences
{
    /// <summary>Library section keys that are disabled (missing key = enabled).</summary>
    public HashSet<string> DisabledLibraryKeys { get; set; } = new(StringComparer.Ordinal);

    public bool ShowContinueWatching { get; set; } = true;
    public bool ShowRecentlyPlayed { get; set; } = true;
    public int MaxItemsPerHub { get; set; } = 20;

    public bool IsLibraryEnabled(string key) => !DisabledLibraryKeys.Contains(key);

    public void SetLibrary(string key, bool enabled)
    {
        if (enabled) DisabledLibraryKeys.Remove(key);
        else DisabledLibraryKeys.Add(key);
    }

    public enum PersonalKind { ContinueWatching, RecentlyAdded, RecentlyPlayed, None }

    public static PersonalKind Classify(PlexHub hub)
    {
        var id = (hub.HubIdentifier ?? hub.Key ?? "").ToLowerInvariant();
        var title = (hub.Title ?? "").ToLowerInvariant();
        var blob = id + " " + title;
        if (blob.Contains("continue") || blob.Contains("on.deck") || blob.Contains("ondeck")
            || blob.Contains("inprogress") || blob.Contains("in progress"))
            return PersonalKind.ContinueWatching;
        if (blob.Contains("recently.added") || blob.Contains("recently added")
            || blob.Contains("recentlyadded") || blob.Contains("newest"))
            return PersonalKind.RecentlyAdded;
        if (blob.Contains("recently.played") || blob.Contains("recently.viewed")
            || blob.Contains("recently played") || blob.Contains("recently viewed")
            || blob.Contains("watch.again"))
            return PersonalKind.RecentlyPlayed;
        return PersonalKind.None;
    }

    public IReadOnlyList<PlexHub> Filter(IReadOnlyList<PlexHub> hubs, IReadOnlyList<PlexLibrary>? libraries)
    {
        var enabledKeys = libraries is { Count: > 0 }
            ? libraries.Where(l => IsLibraryEnabled(l.Key)).Select(l => l.Key).ToHashSet(StringComparer.Ordinal)
            : null;

        var continueItems = new List<PlexMetadata>();
        PlexHub? continueTemplate = null;
        var playedItems = new List<PlexMetadata>();
        PlexHub? playedTemplate = null;
        var other = new List<PlexHub>();

        foreach (var hub in hubs)
        {
            switch (Classify(hub))
            {
                case PersonalKind.ContinueWatching:
                    if (!ShowContinueWatching) continue;
                    continueTemplate ??= hub;
                    continueItems.AddRange(hub.Items);
                    break;
                case PersonalKind.RecentlyPlayed:
                    if (!ShowRecentlyPlayed) continue;
                    playedTemplate ??= hub;
                    playedItems.AddRange(hub.Items);
                    break;
                default:
                    other.Add(hub);
                    break;
            }
        }

        var result = new List<PlexHub>();

        if (continueTemplate is not null)
        {
            var items = Dedupe(continueItems, enabledKeys, MaxItemsPerHub);
            if (items.Count > 0)
                result.Add(CloneHub(continueTemplate, items));
        }

        foreach (var hub in other)
        {
            // Drop hubs tied to disabled libraries when we can match by title
            if (libraries is { Count: > 0 })
            {
                var matched = libraries.FirstOrDefault(l =>
                    hub.Title.Contains(l.Title, StringComparison.OrdinalIgnoreCase));
                if (matched is not null && !IsLibraryEnabled(matched.Key))
                    continue;
            }
            var items = Dedupe(hub.Items.ToList(), enabledKeys, MaxItemsPerHub);
            if (items.Count == 0) continue;
            result.Add(CloneHub(hub, items));
        }

        if (playedTemplate is not null)
        {
            var items = Dedupe(playedItems, enabledKeys, MaxItemsPerHub);
            if (items.Count > 0)
                result.Add(CloneHub(playedTemplate, items));
        }

        return result;
    }

    private static List<PlexMetadata> Dedupe(List<PlexMetadata> items, HashSet<string>? enabledKeys, int max)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var list = new List<PlexMetadata>();
        foreach (var item in items)
        {
            if (!seen.Add(item.RatingKey)) continue;
            // librarySectionID filter when available
            list.Add(item);
            if (list.Count >= max) break;
        }
        return list;
    }

    private static PlexHub CloneHub(PlexHub template, List<PlexMetadata> items) => new()
    {
        Key = template.Key,
        HubIdentifier = template.HubIdentifier,
        Title = template.Title,
        Type = template.Type,
        Items = items
    };
}
