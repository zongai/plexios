using System.Text;
using System.Text.RegularExpressions;

namespace PlexWindows.Iptv;

/// <summary>EXTM3U parser aligned with iOS M3UParser (EXTINF + URL pairing).</summary>
public static class M3UParser
{
    private static readonly Regex AttrRegex = new(
        @"([A-Za-z0-9_-]+)\s*=\s*""([^""]*)""",
        RegexOptions.Compiled);

    public static M3UParseResult Parse(string text)
    {
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        if (text.Length > 0 && text[0] == '\uFEFF') text = text[1..];

        string? epgUrl = null;
        var entries = new List<M3UEntry>();
        string? pendingName = null;
        Dictionary<string, string>? pendingAttrs = null;
        var pendingHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;

            var upper = line.ToUpperInvariant();
            if (upper.StartsWith("#EXTM3U"))
            {
                var attrs = ParseAttrs(line);
                if (attrs.TryGetValue("url-tvg", out var e1)) epgUrl = e1;
                else if (attrs.TryGetValue("x-tvg-url", out var e2)) epgUrl = e2;
                else if (attrs.TryGetValue("tvg-url", out var e3)) epgUrl = e3;
                continue;
            }

            if (upper.StartsWith("#EXTINF:"))
            {
                var body = line["#EXTINF:".Length..];
                var (attrs, name) = SplitAttrsAndName(body);
                pendingName = name;
                pendingAttrs = attrs;
                pendingHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                continue;
            }

            if (line.StartsWith('#'))
            {
                if (pendingName is null) continue;
                if (upper.StartsWith("#EXTVLCOPT:"))
                {
                    var body = line["#EXTVLCOPT:".Length..];
                    var lower = body.ToLowerInvariant();
                    var val = body.Contains('=') ? body[(body.IndexOf('=') + 1)..] : "";
                    if (lower.StartsWith("http-user-agent=")) pendingHeaders["User-Agent"] = val;
                    else if (lower.StartsWith("http-referrer=") || lower.StartsWith("http-referer="))
                        pendingHeaders["Referer"] = val;
                    else if (lower.StartsWith("http-origin=")) pendingHeaders["Origin"] = val;
                }
                else if (upper.StartsWith("#EXTGRP:"))
                {
                    var g = line["#EXTGRP:".Length..].Trim();
                    if (g.Length > 0)
                    {
                        pendingAttrs ??= new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                        pendingAttrs["group-title"] = g;
                    }
                }
                continue;
            }

            // URL line
            if (pendingName is not null && Uri.TryCreate(line, UriKind.Absolute, out _))
            {
                var attrs = pendingAttrs ?? new Dictionary<string, string>();
                entries.Add(new M3UEntry
                {
                    Name = pendingName,
                    TvgId = Get(attrs, "tvg-id"),
                    TvgLogo = Get(attrs, "tvg-logo"),
                    GroupTitle = Get(attrs, "group-title"),
                    StreamUrl = line,
                    Headers = new Dictionary<string, string>(pendingHeaders, StringComparer.OrdinalIgnoreCase)
                });
            }
            pendingName = null;
            pendingAttrs = null;
            pendingHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }

        return new M3UParseResult { EpgUrl = epgUrl, Entries = entries };
    }

    public static M3UParseResult Parse(byte[] data)
    {
        var text = Encoding.UTF8.GetString(data);
        if (text.Contains('\uFFFD'))
            text = Encoding.GetEncoding("ISO-8859-1").GetString(data);
        return Parse(text);
    }

    private static string? Get(Dictionary<string, string> attrs, string key) =>
        attrs.TryGetValue(key, out var v) && v.Length > 0 ? v : null;

    private static Dictionary<string, string> ParseAttrs(string line)
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match m in AttrRegex.Matches(line))
            dict[m.Groups[1].Value.ToLowerInvariant()] = m.Groups[2].Value;
        return dict;
    }

    private static (Dictionary<string, string> attrs, string name) SplitAttrsAndName(string body)
    {
        // strip duration prefix
        var i = 0;
        while (i < body.Length && body[i] is not (' ' or ',')) i++;
        var rest = body[i..].TrimStart();

        var inQuotes = false;
        int? lastComma = null;
        for (var j = 0; j < rest.Length; j++)
        {
            var c = rest[j];
            if (c == '"') inQuotes = !inQuotes;
            else if (c == ',' && !inQuotes) lastComma = j;
        }

        string attrPart, name;
        if (lastComma is int cidx)
        {
            attrPart = rest[..cidx];
            name = rest[(cidx + 1)..].Trim();
        }
        else
        {
            attrPart = rest;
            name = rest;
        }

        var attrs = ParseAttrs(attrPart);
        if (string.IsNullOrWhiteSpace(name))
            name = Get(attrs, "tvg-name") ?? "Channel";
        return (attrs, name);
    }
}
