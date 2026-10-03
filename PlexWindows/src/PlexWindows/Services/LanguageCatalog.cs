
namespace PlexWindows.Services;

/// <summary>iOS-aligned language picker options (ISO / BCP-47).</summary>
public static class LanguageCatalog
{
    public sealed record Option(string Code, string Label)
    {
        public override string ToString() => string.IsNullOrEmpty(Code) ? Label : $"{Label} ({Code})";
    }

    public static IReadOnlyList<Option> All { get; } =
    [
        new("", "Auto"),
        new("en", "English"),
        new("zh", "Chinese"),
        new("zh-CN", "Chinese (Simplified)"),
        new("zh-TW", "Chinese (Traditional)"),
        new("ja", "Japanese"),
        new("ko", "Korean"),
        new("es", "Spanish"),
        new("fr", "French"),
        new("de", "German"),
        new("pt", "Portuguese"),
        new("ru", "Russian"),
        new("it", "Italian"),
        new("ar", "Arabic"),
        new("hi", "Hindi"),
        new("th", "Thai"),
        new("vi", "Vietnamese"),
    ];

    public static Option Find(string? code) =>
        All.FirstOrDefault(o => string.Equals(o.Code, code ?? "", StringComparison.OrdinalIgnoreCase))
        ?? All[0];
}
