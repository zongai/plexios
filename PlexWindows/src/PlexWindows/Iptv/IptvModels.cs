namespace PlexWindows.Iptv;

public sealed class IptvPlaylist
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Url { get; set; } = "";
    public bool Enabled { get; set; } = true;
    public DateTimeOffset? LastUpdated { get; set; }
    public int ChannelCount { get; set; }
    public string? EpgUrl { get; set; }
}

public sealed class IptvChannel
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string? LogoUrl { get; set; }
    public string? Group { get; set; }
    public string? TvgId { get; set; }
    public string StreamUrl { get; set; } = "";
    public Guid PlaylistId { get; set; }
    public Dictionary<string, string> Headers { get; set; } = new();
}

public sealed class M3UEntry
{
    public string Name { get; set; } = "";
    public string? TvgId { get; set; }
    public string? TvgLogo { get; set; }
    public string? GroupTitle { get; set; }
    public string StreamUrl { get; set; } = "";
    public Dictionary<string, string> Headers { get; set; } = new();
}

public sealed class M3UParseResult
{
    public string? EpgUrl { get; set; }
    public List<M3UEntry> Entries { get; set; } = [];
}
