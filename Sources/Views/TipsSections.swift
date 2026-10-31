import SwiftUI

struct MarketSection: View {
    @Environment(TipsStore.self) private var tips
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SectionTitle(text: "市场")
                Spacer()
                if let updated = tips.lastUpdated {
                    Text(updated, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                }
                RefreshButton()
            }
            .padding(.leading, 10)

            content
        }
    }

    @ViewBuilder private var content: some View {
        switch tips.markets {
        case .loaded(let quotes):
            rows(quotes)
        case .failed(let message):
            rows(tips.lastQuotes)
            ErrorLine(message: message) { tips.refresh() }
        case .idle, .loading:
            if tips.lastQuotes.isEmpty {
                rows(settings.enabledIndices.map { Quote(code: $0, name: MarketIndex.named($0), price: 0, change: 0, changePercent: 0) })
                    .redacted(reason: .placeholder)
            } else {
                rows(tips.lastQuotes)
            }
        }
    }

    private func rows(_ quotes: [Quote]) -> some View {
        ForEach(quotes) { quote in
            QuoteRow(quote: quote, redMeansUp: settings.redMeansUp)
        }
    }
}

private struct QuoteRow: View {
    let quote: Quote
    let redMeansUp: Bool

    var body: some View {
        let color = Theme.trend(quote.changePercent, redMeansUp: redMeansUp)
        HStack(spacing: 8) {
            Text(quote.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(quote.price, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 13))
                .monospacedDigit()
            HStack(spacing: 3) {
                if quote.changePercent != 0 {
                    Image(systemName: quote.changePercent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                }
                Text(abs(quote.changePercent) / 100, format: .percent.precision(.fractionLength(2)))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(color)
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("market.row")
    }

    private var accessibilityText: String {
        let direction = quote.changePercent > 0 ? "上涨" : quote.changePercent < 0 ? "下跌" : "平盘"
        return "\(quote.name) \(String(format: "%.2f", quote.price)) \(direction) \(String(format: "%.2f", abs(quote.changePercent)))%"
    }
}

struct MatchSection: View {
    @Environment(TipsStore.self) private var tips
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SectionTitle(text: "赛事 · " + settings.enabledLeagues.map(League.named).joined(separator: " / "))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, 10)
            .frame(height: 26)

            content
        }
    }

    @ViewBuilder private var content: some View {
        switch tips.matches {
        case .loaded(let matches):
            list(matches)
        case .failed(let message):
            list(tips.lastMatches, showEmpty: false)
            ErrorLine(message: message) { tips.refresh() }
        case .idle, .loading:
            if tips.lastMatches.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("加载中…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
            } else {
                list(tips.lastMatches)
            }
        }
    }

    @ViewBuilder private func list(_ matches: [Match], showEmpty: Bool = true) -> some View {
        if matches.isEmpty {
            if showEmpty {
                Text("今日无比赛")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .accessibilityIdentifier("match.empty")
            }
        } else {
            let showLeague = Set(matches.map(\.league)).count > 1
            ForEach(matches) { match in
                MatchRow(match: match, showLeague: showLeague)
            }
        }
    }
}

private struct MatchRow: View {
    let match: Match
    let showLeague: Bool

    var body: some View {
        HStack(spacing: 6) {
            status
                .frame(width: 44, alignment: .leading)
            Text(match.home)
                .frame(maxWidth: .infinity, alignment: .trailing)
            score
                .frame(width: 44)
            Text(match.away)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("match.row")
        .help(showLeague ? League.named(match.league) : "")
    }

    @ViewBuilder private var status: some View {
        switch match.state {
        case .scheduled:
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.time.string(from: match.kickoff))
                    .monospacedDigit()
                if !Calendar.current.isDateInToday(match.kickoff) {
                    Text("次日").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        case .live:
            HStack(spacing: 4) {
                Circle().fill(Theme.live).frame(width: 5, height: 5)
                Text(match.detail.isEmpty ? "进行中" : match.detail)
                    .monospacedDigit()
                    .foregroundStyle(Theme.live)
            }
            .font(.system(size: 12, weight: .medium))
        case .finished:
            Text("完场").foregroundStyle(.tertiary).font(.system(size: 12))
        }
    }

    @ViewBuilder private var score: some View {
        if let home = match.homeScore, let away = match.awayScore {
            Text("\(home) - \(away)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        } else {
            Text("vs").foregroundStyle(.tertiary).font(.system(size: 11))
        }
    }

    private var accessibilityText: String {
        let prefix = showLeague ? League.named(match.league) + " " : ""
        switch match.state {
        case .scheduled:
            return "\(prefix)\(Self.time.string(from: match.kickoff)) \(match.home) 对 \(match.away)"
        case .live:
            return "\(prefix)进行中 \(match.detail) \(match.home) \(match.homeScore ?? "0") 比 \(match.awayScore ?? "0") \(match.away)"
        case .finished:
            return "\(prefix)完场 \(match.home) \(match.homeScore ?? "0") 比 \(match.awayScore ?? "0") \(match.away)"
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct RefreshButton: View {
    @Environment(TipsStore.self) private var tips

    var body: some View {
        IconButton(symbol: "arrow.clockwise", label: "刷新", identifier: "tips.refresh") {
            tips.refresh()
        }
        .disabled(tips.isLoading)
        .opacity(tips.isLoading ? 0.4 : 1)
    }
}
