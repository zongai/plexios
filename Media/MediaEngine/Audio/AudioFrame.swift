import Foundation

enum AudioCodecID: String, Sendable, Equatable {
    case aac
    case ac3
    case eac3
    case mp3
    case flac
    case alac
    case opus
    case vorbis
    case pcm
    case dts
    case truehd
    case unknown

    static func from(codecName: String?) -> AudioCodecID {
        switch IOSCapabilities.normalizeAudioCodec(codecName) {
        case "aac", "mp4a": return .aac
        case "ac3": return .ac3
        case "eac3": return .eac3
        case "mp3", "mp2": return .mp3
        case "flac": return .flac
        case "alac": return .alac
        case "opus": return .opus
        case "vorbis": return .vorbis
        case "pcm", "pcm_s16le", "pcm_s24le", "pcm_f32le": return .pcm
        case "dca", "dts": return .dts
        case "truehd": return .truehd
        default: return .unknown
        }
    }
}

struct AudioDecoderConfig: Sendable, Equatable {
    var codec: AudioCodecID
    var sampleRate: Int
    var channels: Int
    var extradata: Data?
    /// Bits per sample for PCM input.
    var bitDepth: Int
}

/// Interleaved PCM float samples ready for AVAudioEngine.
struct AudioFrame: Sendable {
    /// Non-interleaved or interleaved Float32 PCM (renderer assumes interleaved).
    var pcm: Data
    var sampleRate: Double
    var channelCount: Int
    var frameCount: Int
    var ptsMs: Int64?
}
