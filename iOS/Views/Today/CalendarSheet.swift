import SwiftData
import SwiftUI

// MARK: - 每日達成率

/// 一天的目標達成率：飲食、喝水、步數、燃燒，各項最多 100%，取平均
struct DayScore {
    var meals: Double
    var water: Double
    var steps: Double?
    var burn: Double?

    /// 沒連接 Apple 健康時只算飲食和喝水
    var total: Double {
        let parts = [meals, water] + [steps, burn].compactMap { $0 }
        return parts.sum { $0 } / Double(parts.count)
    }

    var light: TrafficLight { TrafficLight(total) }
}

/// 紅綠燈：30% 以下紅、90% 以下黃、90% 以上綠
enum TrafficLight {
    case red, yellow, green

    init(_ ratio: Double) {
        if ratio < 0.3 {
            self = .red
        } else if ratio < 0.9 {
            self = .yellow
        } else {
            self = .green
        }
    }

    /// 燈號顏色固定，不隨配色改變，才分得出紅黃綠
    var color: Color {
        switch self {
        case .red: Color(hex: 0xD9534F)
        case .yellow: Color(hex: 0xF0B429)
        case .green: Color(hex: 0x5FA84F)
        }
    }

    var title: String {
        switch self {
        case .red: "紅燈"
        case .yellow: "黃燈"
        case .green: "綠燈"
        }
    }
}

@MainActor
enum DayScoreCalculator {
    /// 算某段期間每天的達成率（用現在的目標），key 為當天 00:00
    static func scores(from start: Date, to end: Date, health: HealthKitManager) async -> [Date: DayScore] {
        let days = max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
        guard days > 0 else { return [:] }
        let totals = LogService.shared.dayTotals(from: start, days: days)

        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        var meals: [Date: Set<MealType>] = [:]
        for entry in (try? AppDatabase.context.fetch(descriptor)) ?? [] {
            meals[entry.date.startOfDay, default: []].insert(entry.mealType)
        }
        let skipped = UserDefaults.standard.string(forKey: SettingKey.skippedMeals) ?? ""

        let connected = health.isAvailable && !health.needsAuthorization
        let steps = connected ? await health.dailySteps(from: start, to: end) : [:]
        let active = connected ? await health.dailyActiveCalories(from: start, to: end) : [:]

        let calorieGoal = AppSettings.calorieGoal
        let waterGoal = AppSettings.waterGoal
        let stepGoal = AppSettings.stepGoal
        let burnGoal = AppSettings.burnGoal
        let addBack = UserDefaults.standard.bool(forKey: SettingKey.addBackExercise)

        var result: [Date: DayScore] = [:]
        for offset in 0..<days {
            let day = start.adding(days: offset)
            let total = totals[day] ?? DayTotals()
            let burned = (active[day] ?? 0) + total.manualExercise

            // 三餐有記錄（或標記沒吃）各算一份；吃超過目標 10% 以上最多只算一半
            let handled = [MealType.breakfast, .lunch, .dinner].filter { meal in
                meals[day]?.contains(meal) == true || skipped.contains("\(day.dayKey)-\(meal.rawValue)")
            }
            var mealScore = Double(handled.count) / 3
            let budget = calorieGoal + (addBack ? burned : 0)
            if budget > 0, total.calories > budget * 1.1 { mealScore = min(mealScore, 0.5) }

            result[day] = DayScore(
                meals: mealScore,
                water: waterGoal > 0 ? min(total.water / waterGoal, 1) : 0,
                steps: connected ? (stepGoal > 0 ? min((steps[day] ?? 0) / stepGoal, 1) : 0) : nil,
                burn: connected ? (burnGoal > 0 ? min(burned / burnGoal, 1) : 0) : nil
            )
        }
        return result
    }

    /// 第一筆記錄的日期，之前的日子不亮燈
    static func firstRecordDay() -> Date? {
        var food = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)])
        food.fetchLimit = 1
        var water = FetchDescriptor<WaterEntry>(sortBy: [SortDescriptor(\.date)])
        water.fetchLimit = 1
        let dates = [(try? AppDatabase.context.fetch(food))?.first?.date,
                     (try? AppDatabase.context.fetch(water))?.first?.date].compactMap { $0 }
        return dates.min()?.startOfDay
    }
}

// MARK: - 月曆

/// 點今日頁的日期打開：每天用紅綠燈表示達成率，點一天就跳過去
struct CalendarSheet: View {
    @Binding var selected: Date
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var month: Date
    @State private var scores: [Date: DayScore] = [:]
    @State private var firstDay: Date?
    @State private var loading = true

    init(selected: Binding<Date>) {
        _selected = selected
        _month = State(initialValue: Self.startOfMonth(selected.wrappedValue))
    }

    private static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date.startOfDay
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private var firstWeekday: Int {
        UserDefaults.standard.integer(forKey: SettingKey.firstWeekday) == 1 ? 1 : 2
    }

    /// 月曆格子：前面補空白，讓 1 號對齊星期
    private var cells: [Date?] {
        let calendar = Calendar.current
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let weekday = calendar.component(.weekday, from: month)
        let blanks = (weekday - firstWeekday + 7) % 7
        return Array(repeating: nil, count: blanks) + (0..<count).map { month.adding(days: $0) }
    }

    private var weekdayTitles: [String] {
        let titles = ["日", "一", "二", "三", "四", "五", "六"]
        return Array(titles[(firstWeekday - 1)...] + titles[..<(firstWeekday - 1)])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelWindow(title: "月曆") {
                        HStack(spacing: 8) {
                            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                                PixelSprite(art: .arrowLeft, size: 14)
                            }
                            .buttonStyle(.pixel(.secondary))
                            .accessibilityLabel("上個月")
                            Spacer(minLength: 0)
                            Text(month.formatted(.dateTime.year().month(.wide))).font(.px(16))
                            Spacer(minLength: 0)
                            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                                PixelSprite(art: .arrowRight, size: 14)
                            }
                            .buttonStyle(.pixel(.secondary))
                            .disabled(isCurrentMonth)
                            .accessibilityLabel("下個月")
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                            ForEach(weekdayTitles, id: \.self) { title in
                                Text(title).font(.px(12)).foregroundStyle(Color.soft)
                            }
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                                if let day {
                                    dayCell(day)
                                } else {
                                    Color.clear.frame(height: 48)
                                }
                            }
                        }

                        if loading {
                            HStack(spacing: 8) {
                                PixelLoadingDots()
                                Text("計算中…").font(.px(12)).foregroundStyle(Color.soft)
                            }
                        }
                    }

                    summaryWindow
                    if let score = scores[selected.startOfDay] { breakdownWindow(score) }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("選日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("今天") {
                        selected = Date.now.startOfDay
                        dismiss()
                    }
                }
            }
            .task(id: month) { await load() }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }

    private func dayCell(_ day: Date) -> some View {
        let isFuture = day > Date.now
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        let isToday = Calendar.current.isDateInToday(day)
        let score = hasLight(day) ? scores[day] : nil

        return Button {
            selected = day
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.px(12))
                    .foregroundStyle(isFuture ? Color.track : (isToday ? Color.brand : Color.ink))
                Rectangle()
                    .fill(score?.light.color ?? Color.clear)
                    .frame(width: 12, height: 12)
                    .overlay(Rectangle().strokeBorder(score == nil ? Color.clear : Color.ink, lineWidth: 2))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if isSelected {
                    PixelPanel(fill: .track, border: .brand, shadow: nil, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityText(day, score: score))
    }

    private func hasLight(_ day: Date) -> Bool {
        guard day <= Date.now, let firstDay else { return false }
        return day >= firstDay
    }

    private func accessibilityText(_ day: Date, score: DayScore?) -> String {
        let date = day.formatted(.dateTime.month().day())
        guard let score else { return date }
        return "\(date)，\(score.light.title)，達成 \(Int((score.total * 100).rounded()))%"
    }

    private var summaryWindow: some View {
        let lights = scores.filter { hasLight($0.key) }.map(\.value.light)
        return PixelWindow(title: "燈號") {
            HStack(spacing: 14) {
                legend(.green, "90% 以上", count: lights.filter { $0 == .green }.count)
                legend(.yellow, "30–90%", count: lights.filter { $0 == .yellow }.count)
                legend(.red, "30% 以下", count: lights.filter { $0 == .red }.count)
            }
            Text("達成率 = 飲食（三餐有記錄、沒超標）、喝水、步數、燃燒四項平均，每項最多算 100%。沒連接 Apple 健康時只算飲食和喝水。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
    }

    private func legend(_ light: TrafficLight, _ text: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Rectangle().fill(light.color).frame(width: 12, height: 12)
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                Text("\(count) 天").font(.px(16))
            }
            Text(text).font(.px(12)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownWindow(_ score: DayScore) -> some View {
        PixelWindow(title: selected.formatted(.dateTime.month().day()) + " 的達成率") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int((score.total * 100).rounded()))%").font(.px(24)).foregroundStyle(score.light.color)
                Text(score.light.title).font(.px(12)).foregroundStyle(Color.soft)
            }
            row("飲食", score.meals, color: .calorie)
            row("喝水", score.water, color: .water)
            if let steps = score.steps { row("步數", steps, color: .move) }
            if let burn = score.burn { row("燃燒", burn, color: .protein) }
        }
    }

    private func row(_ title: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 36, alignment: .leading)
            PixelBar(value: value, total: 1, color: color, overIsBad: false)
            Text("\(Int((value * 100).rounded()))%")
                .font(.px(12))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func load() async {
        loading = true
        firstDay = DayScoreCalculator.firstRecordDay()
        let end = min(Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month,
                      Date.now.startOfDay.adding(days: 1))
        scores = await DayScoreCalculator.scores(from: month, to: end, health: health)
        loading = false
    }
}
