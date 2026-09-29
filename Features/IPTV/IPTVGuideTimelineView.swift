import SwiftUI

/// Full EPG timeline grid: channel rows × time columns with a live “now” line.
struct IPTVGuideTimelineView: View {
    let channels: [IPTVChannel]
    @Environment(\.dismiss) private var dismiss

    @State private var index = EPGChannelIndex()
    @State private var windowStart: Date = Date().addingTimeInterval(-30 * 60)
    @State private var now = Date()
    @State private var isLoading = true

    private let hourWidth: CGFloat = 220
    private let rowHeight: CGFloat = 64
    private let channelColWidth: CGFloat = 120
    private let hoursVisible: Double = 6

    private var windowEnd: Date {
        windowStart.addingTimeInterval(hoursVisible * 3600)
    }

    private var totalWidth: CGFloat {
        CGFloat(hoursVisible) * hourWidth
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    geometryGrid
                }
            }
            .background(AppColors.background)
            .navigationTitle(String(localized: "iptv.guide"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.close) { dismiss() }
                }
            }
            .task {
                index = await EPGRepository.shared.index()
                isLoading = false
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
                now = date
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                windowStart = windowStart.addingTimeInterval(-3600)
            } label: {
                Image(systemName: "chevron.left")
            }
            Button(String(localized: "iptv.guide_now")) {
                windowStart = Date().addingTimeInterval(-30 * 60)
            }
            .font(AppTypography.caption)
            Button {
                windowStart = windowStart.addingTimeInterval(3600)
            } label: {
                Image(systemName: "chevron.right")
            }
            Spacer()
            Text(windowLabel)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    private var windowLabel: String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(windowStart.formatted(f)) – \(windowEnd.formatted(f))"
    }

    private var geometryGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                timeHeader
                ForEach(Array(channels.prefix(80))) { channel in
                    channelRow(channel)
                }
            }
            .frame(width: channelColWidth + totalWidth, alignment: .leading)
        }
    }

    private var timeHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: channelColWidth, height: 28)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<Int(hoursVisible), id: \.self) { i in
                        let t = windowStart.addingTimeInterval(Double(i) * 3600)
                        Text(t.formatted(Date.FormatStyle(date: .omitted, time: .shortened)))
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: hourWidth, alignment: .leading)
                    }
                }
                nowLine(height: 28)
            }
            .frame(width: totalWidth, height: 28)
        }
        .background(AppColors.secondaryBackground)
    }

    private func channelRow(_ channel: IPTVChannel) -> some View {
        let programs = programs(for: channel)
        return HStack(spacing: 0) {
            Text(channel.name)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .frame(width: channelColWidth, height: rowHeight, alignment: .leading)
                .background(AppColors.secondaryBackground)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(PlexColors.separator.opacity(0.35))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                ForEach(programs) { program in
                    programBlock(program)
                }
                nowLine(height: rowHeight)
            }
            .frame(width: totalWidth, height: rowHeight)
        }
    }

    @ViewBuilder
    private func programBlock(_ program: EPGProgram) -> some View {
        let start = max(program.startTime, windowStart)
        let end = min(program.endTime, windowEnd)
        let duration = end.timeIntervalSince(start)
        if duration > 0 {
            let x = CGFloat(start.timeIntervalSince(windowStart) / (hoursVisible * 3600)) * totalWidth
            let w = max(44, CGFloat(duration / (hoursVisible * 3600)) * totalWidth)
            let isNow = program.isPlaying(at: now)
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title)
                    .font(AppTypography.caption2)
                    .fontWeight(isNow ? .semibold : .regular)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)
                Text(timeRange(program))
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(6)
            .frame(width: w, height: rowHeight - 6, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isNow ? PlexColors.accent.opacity(0.25) : AppColors.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isNow ? PlexColors.accent : PlexColors.separator.opacity(0.5), lineWidth: 1)
                    )
            )
            .offset(x: x)
        }
    }

    private func nowLine(height: CGFloat) -> some View {
        let x = CGFloat(now.timeIntervalSince(windowStart) / (hoursVisible * 3600)) * totalWidth
        return Group {
            if now >= windowStart && now <= windowEnd {
                Rectangle()
                    .fill(PlexColors.accent)
                    .frame(width: 2, height: height)
                    .offset(x: x)
            }
        }
    }

    private func programs(for channel: IPTVChannel) -> [EPGProgram] {
        guard let tvg = channel.tvgID, !tvg.isEmpty else { return [] }
        return index.programs(channelID: tvg, around: windowStart, hours: hoursVisible + 1)
    }

    private func timeRange(_ p: EPGProgram) -> String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(p.startTime.formatted(f))–\(p.endTime.formatted(f))"
    }
}
