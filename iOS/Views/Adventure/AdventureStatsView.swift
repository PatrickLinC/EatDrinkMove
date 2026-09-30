import SwiftUI

// MARK: - 冒險統計（足跡頁）

/// 期間合計、最近 12 週的距離、連續週數、個人紀錄
struct AdventureStatsWindow: View {
    @ObservedObject private var routes = RouteStore.shared
    @AppStorage("footprintPeriod") private var periodRaw = Period.week.rawValue
    /// 點個人紀錄時打開那一條路線
    var onSelect: (SavedRoute) -> Void

    enum Period: String, CaseIterable, Identifiable {
        case week, month, year, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: "本週"
            case .month: "本月"
            case .year: "今年"
            case .all: "全部"
            }
        }

        var start: Date? {
            switch self {
            case .week: AppSettings.startOfWeek(.now)
            case .month: Calendar.current.dateInterval(of: .month, for: .now)?.start
            case .year: Calendar.current.dateInterval(of: .year, for: .now)?.start
            case .all: nil
            }
        }
    }

    private var period: Period { Period(rawValue: periodRaw) ?? .week }

    var body: some View {
        PixelWindow(title: "冒險統計", tint: .calorie) {
            HStack(spacing: 6) {
                ForEach(Period.allCases) { item in
                    Button(item.title) { periodRaw = item.rawValue }
                        .buttonStyle(.pixel(period == item ? .primary : .secondary, fullWidth: true, fontSize: 12))
                }
            }
            totals
            PixelDivider()
            weeklyChart
            PixelDivider()
            records
            frequentRoutes
        }
    }

    // MARK: 常走路線

    @ViewBuilder private var frequentRoutes: some View {
        let groups = Array(RouteMatcher.frequent(in: routes.routes).prefix(3))
        if !groups.isEmpty {
            PixelDivider()
            Text("常走路線").font(.px(12)).foregroundStyle(Color.soft)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, runs in
                    if index > 0 { PixelDivider() }
                    if let latest = runs.last, let best = runs.min(by: { $0.activeTime < $1.activeTime }) {
                        Button { onSelect(latest) } label: {
                            HStack(spacing: 10) {
                                PixelSprite(art: latest.kind.art, size: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RouteMatcher.name(latest))
                                    Text("走了 \(runs.count) 次・最佳 \(RouteStore.clock(best.activeTime))")
                                        .font(.px(12))
                                        .foregroundStyle(Color.soft)
                                }
                                Spacer(minLength: 4)
                                PixelSprite(art: .cursor, size: 12)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 合計

    private var totals: some View {
        let list = routes.routes.filter { route in period.start.map { route.start >= $0 } ?? true }
        let meters = list.reduce(0) { $0 + $1.distance }
        let time = list.reduce(0) { $0 + $1.activeTime }
        let climb = list.reduce(0) { $0 + ($1.climb ?? 0) }
        return HStack(alignment: .top, spacing: 8) {
            stat("\(list.count)", "次")
            stat((meters / 1000).formatted(.number.precision(.fractionLength(1))), "公里")
            stat(Self.hours(time), "時間")
            stat("\(Int(climb.rounded()))", "公尺爬升")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.px(20)).foregroundStyle(Color.calorie).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 1 小時以上顯示「3h20m」，以下顯示分鐘
    static func hours(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }

    // MARK: 最近 12 週

    private var weeklyChart: some View {
        let weeks = routes.weeklyDistance(weeks: 12)
        let best = max(weeks.map(\.meters).max() ?? 0, 1)
        let streak = routes.weekStreak
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近 12 週的距離").font(.px(12)).foregroundStyle(Color.soft)
                Spacer()
                Text("最多 \((best / 1000).formatted(.number.precision(.fractionLength(1)))) 公里")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    // 高度以 4 點為一格，保持像素感
                    let height = week.meters > 0 ? max((week.meters / best * 76 / 4).rounded() * 4, 4) : 2
                    Rectangle()
                        .fill(week.meters > 0 ? (index == weeks.count - 1 ? Color.calorie : Color.brand) : Color.track)
                        .frame(height: height)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(week.start.formatted(.dateTime.month().day())) 那週 \((week.meters / 1000).formatted(.number.precision(.fractionLength(1)))) 公里")
                }
            }
            .frame(height: 80, alignment: .bottom)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ink).frame(height: 2) }
            HStack {
                Text(weeks.first?.start.formatted(.dateTime.month().day()) ?? "")
                Spacer()
                Text("本週")
            }
            .font(.px(12))
            .foregroundStyle(Color.soft)
            HStack(spacing: 8) {
                PixelSprite(art: .campfire, size: 20)
                Text(streak > 0 ? "連續 \(streak) 週都有出發冒險！" : "這週出發一次，就開始累積連續週數。")
                    .font(.px(12))
                    .foregroundStyle(streak > 0 ? Color.calorie : Color.soft)
            }
        }
    }

    // MARK: 個人紀錄

    @ViewBuilder private var records: some View {
        let all = routes.routes.filter { $0.distance >= 500 }
        if all.isEmpty {
            Text("走完第一趟冒險，這裡會記下你的個人紀錄。").font(.px(12)).foregroundStyle(Color.soft)
        } else {
            Text("個人紀錄").font(.px(12)).foregroundStyle(Color.soft)
            VStack(spacing: 0) {
                if let longest = all.max(by: { $0.distance < $1.distance }) {
                    recordRow("最長距離", "\(longest.kilometers) 公里", longest)
                }
                let paced = all.filter { $0.distance >= 1000 }
                if let fastest = paced.min(by: { $0.activeTime / $0.distance < $1.activeTime / $1.distance }) {
                    PixelDivider()
                    recordRow("最快配速", RouteStore.pace(seconds: fastest.activeTime, meters: fastest.distance) + "／公里", fastest)
                }
                if let longestTime = all.max(by: { $0.activeTime < $1.activeTime }) {
                    PixelDivider()
                    recordRow("最久的一趟", RouteStore.clock(longestTime.activeTime), longestTime)
                }
                if let climb = all.filter({ ($0.climb ?? 0) > 0 }).max(by: { ($0.climb ?? 0) < ($1.climb ?? 0) }) {
                    PixelDivider()
                    recordRow("最多爬升", "\(Int((climb.climb ?? 0).rounded())) 公尺", climb)
                }
            }
        }
    }

    private func recordRow(_ title: String, _ value: String, _ route: SavedRoute) -> some View {
        Button {
            onSelect(route)
        } label: {
            HStack(spacing: 10) {
                PixelSprite(art: .trophy, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text("\(route.title)・\(route.start.formatted(.dateTime.month().day()))")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
                Spacer(minLength: 4)
                Text(value).foregroundStyle(Color.calorie).monospacedDigit()
                PixelSprite(art: .cursor, size: 12)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension RouteStore {
    /// 最近幾週每週的距離（最後一個是這週）
    func weeklyDistance(weeks: Int) -> [(start: Date, meters: Double)] {
        let thisWeek = AppSettings.startOfWeek(.now)
        return (0..<weeks).reversed().map { offset in
            let start = thisWeek.adding(days: -7 * offset)
            let end = start.adding(days: 7)
            let meters = routes.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.distance }
            return (start, meters)
        }
    }

    /// 連續幾週都有出發（這週還沒出發不算斷掉）
    var weekStreak: Int {
        let weeks = Set(routes.map { AppSettings.startOfWeek($0.start) })
        var week = AppSettings.startOfWeek(.now)
        if !weeks.contains(week) { week = week.adding(days: -7) }
        var count = 0
        while weeks.contains(week) {
            count += 1
            week = week.adding(days: -7)
        }
        return count
    }
}
