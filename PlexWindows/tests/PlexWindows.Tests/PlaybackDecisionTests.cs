using PlexWindows.Models;
using PlexWindows.Playback;
using Xunit;

namespace PlexWindows.Tests;

public class PlaybackDecisionTests
{
    private readonly PlaybackDecisionEngine _engine = new(ClientCapabilities.WindowsDefault);

    [Fact]
    public void H264_Aac_Mp4_Is_DirectPlay()
    {
        var meta = Meta("mp4", "h264", "aac");
        var d = _engine.Decide(meta, NetworkClass.Local);
        Assert.Equal(PlaybackMode.DirectPlay, d.Mode);
        Assert.Contains("supported", d.Reason, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Unsupported_Video_Falls_Back_To_Transcode_Or_DirectStream()
    {
        var meta = Meta("mkv", "rv40", "aac"); // RealVideo — not in Windows matrix
        var d = _engine.Decide(meta, NetworkClass.Local);
        Assert.NotEqual(PlaybackMode.DirectPlay, d.Mode);
        Assert.False(string.IsNullOrWhiteSpace(d.Reason));
    }

    [Fact]
    public void Empty_Media_Is_Transcode_With_Reason()
    {
        var meta = new PlexMetadata
        {
            RatingKey = "1",
            Key = "/library/metadata/1",
            Type = PlexMetadataType.Movie,
            Title = "Empty",
            Media = []
        };
        var d = _engine.Decide(meta, NetworkClass.Local);
        Assert.Equal(PlaybackMode.Transcode, d.Mode);
        Assert.Contains("No media", d.Reason, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Reason_Always_Present()
    {
        var d = _engine.Decide(Meta("mp4", "h264", "aac"), NetworkClass.Remote);
        Assert.False(string.IsNullOrWhiteSpace(d.Reason));
    }

    private static PlexMetadata Meta(string container, string video, string audio) => new()
    {
        RatingKey = "42",
        Key = "/library/metadata/42",
        Type = PlexMetadataType.Movie,
        Title = "Sample",
        Duration = 3_600_000,
        Media =
        [
            new PlexMedia
            {
                Id = 1,
                Container = container,
                VideoCodec = video,
                AudioCodec = audio,
                Duration = 3_600_000,
                Parts =
                [
                    new PlexPart
                    {
                        Id = 1,
                        Key = "/library/parts/1/file.mp4",
                        Container = container,
                        Duration = 3_600_000,
                        Streams =
                        [
                            new PlexStream { Id = 1, Type = PlexStream.StreamType.Video, Codec = video },
                            new PlexStream { Id = 2, Type = PlexStream.StreamType.Audio, Codec = audio }
                        ]
                    }
                ]
            }
        ]
    };
}
