import Foundation

struct EPGProgram: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let channelID: String
    var title: String
    var subtitle: String?
    var description: String?
    var startTime: Date
    var endTime: Date
    var category: String?
    var iconURLString: String?

    var iconURL: URL? { iconURLString.flatMap(URL.init(string:)) }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    func progress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startTime)
        return min(1, max(0, elapsed / duration))
    }

    func isPlaying(at date: Date = Date()) -> Bool {
        date >= startTime && date < endTime
    }
}

struct EPGChannelIndex: Sendable {
    /// channelId (tvg-id) → programs sorted by start
    var programsByChannel: [String: [EPGProgram]] = [:]

    func current(channelID: String, at date: Date = Date()) -> EPGProgram? {
        programsByChannel[channelID]?.first { $0.isPlaying(at: date) }
    }

    func next(channelID: String, at date: Date = Date()) -> EPGProgram? {
        programsByChannel[channelID]?.first { $0.startTime > date }
    }

    func programs(channelID: String, around date: Date = Date(), hours: Double = 6) -> [EPGProgram] {
        let start = date.addingTimeInterval(-3600)
        let end = date.addingTimeInterval(hours * 3600)
        return (programsByChannel[channelID] ?? []).filter {
            $0.endTime > start && $0.startTime < end
        }
    }
}
