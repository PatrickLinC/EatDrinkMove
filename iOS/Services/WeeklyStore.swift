import Foundation
import SwiftData
import SwiftUI

// MARK: - 習慣與兩層目標

/// 每天的四個習慣，各有「最低標」和「理想標」
enum Habit: String, CaseIterable, Identifiable, Codable {
    case water, steps, sleep, logging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: "喝水"
        case .steps: "步數"
        case .sleep: "睡眠"
        case .logging: "記錄三餐"
        }
    }

    var art: PixelArt {
        switch self {
        case .water: .drop
        case .steps: .footprint
        case .sleep: .moon
        case .logging: .bowl
        }
    }

    var color: Color {
        switch self {
        case .water: .water
        case .steps: .move
        case .sleep: .fat
        case .logging: .calorie
        }
    }

    /// 代表這個壞習慣的頭目
    var boss: (name: String, art: PixelArt) {
        switch self {
        case .water: ("旱地仙人掌", .monsterCactus)
        case .steps: ("沙發怪", .monsterSofa)
        case .sleep: ("熬夜蝠", .monsterBat)
        case .logging: ("健忘書蟲", .monsterWorm)
        }
    }

    /// 最低標（level 是每週回顧調整的：-2 到 +2）
    func floor(level: Int) -> Double {
        switch self {
        case .water: AppSettings.waterGoal * (0.6 + Double(level) * 0.1)
        case .steps: AppSettings.stepGoal * (0.5 + Double(level) * 0.1)
        case .sleep: 6 + Double(level) * 0.5
        case .logging: Double(min(max(2 + level, 1), 3))
        }
    }

    var ideal: Double {
        switch self {
        case .water: AppSettings.waterGoal
        case .steps: AppSettings.stepGoal
        case .sleep: 7
        case .logging: 3
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .water: "\(Int(value.rounded())) ml"
        case .steps: "\(Int(value.rounded()).formatted()) 步"
        case .sleep: value.formatted(.number.precision(.fractionLength(1))) + " 小時"
        case .logging: "\(Int(value.rounded())) 餐"
        }
    }
}

enum QuestTier: Int, Codable, Comparable {
    case none, floor, ideal

    static func < (lhs: QuestTier, rhs: QuestTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .none: "未達成"
        case .floor: "保底"
        case .ideal: "完美"
        }
    }

    /// 對頭目的傷害：保底 3、完美 5
    var damage: Int { [0, 3, 5][rawValue] }
}

/// 某一天某個習慣的進度
struct HabitProgress {
    let value: Double
    let floor: Double
    let ideal: Double

    var tier: QuestTier { value >= ideal ? .ideal : value >= floor ? .floor : .none }
}

// MARK: - 每週

/// 每週的頭目、回顧與冒險編年史
@MainActor
final class WeeklyStore: ObservableObject {
    static let shared = WeeklyStore()

    static let bossHP = 100
    static let bossReward = 20
    static let reviewReward = 5

    struct BossRecord: Codable {
        var habit: Habit
        var damage = 0
        var defeated = false
    }

    struct Review: Codable {
        var bestDay: Date?
        var stuck: Habit?
        /// -1 調低、0 維持、1 調高
        var adjust: Int
    }

    /// 一週的冒險紀錄（存起來的是已經結束的週）
    struct Chronicle: Codable, Identifiable {
        var weekStart: Date
        var steps: Double
        var sleepAverage: Double?
        var floorDays: Int
        var idealDays: Int
        var spirits: [String]
        var boss: BossRecord?
        var bestDay: Date?
        /// 每天四個習慣的達成分數（保底 1、完美 2，加起來 0–8）
        var dayScores: [Date: Int] = [:]
        var id: Date { weekStart }
    }

    private struct State: Codable {
        var floorLevels: [String: Int] = [:]
        var bosses: [String: BossRecord] = [:]
        var reviews: [String: Review] = [:]
        var chronicles: [Chronicle] = []

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            floorLevels = try container.decodeIfPresent([String: Int].self, forKey: .floorLevels) ?? [:]
            bosses = try container.decodeIfPresent([String: BossRecord].self, forKey: .bosses) ?? [:]
            reviews = try container.decodeIfPresent([String: Review].self, forKey: .reviews) ?? [:]
            chronicles = try container.decodeIfPresent([Chronicle].self, forKey: .chronicles) ?? []
        }
    }

    private static let key = "weeklyState"
    @Published private var state: State

    /// 今天四個習慣的進度
    @Published private(set) var today: [Habit: HabitProgress] = [:]
    /// 這週每天的達成（到今天為止）
    @Published private(set) var week: [Date: [Habit: QuestTier]] = [:]
    /// 每個習慣連續保底幾天（今天還沒達成不算斷）
    @Published private(set) var streaks: [Habit: Int] = [:]
    /// 這週目前的編年史（還在進行中）
    @Published private(set) var current: Chronicle?
    @Published var showReview = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    var weekStart: Date { AppSettings.startOfWeek(.now) }
    private var weekKey: String { weekStart.dayKey }
    var boss: BossRecord? { state.bosses[weekKey] }
    var bossHP: Int { max(Self.bossHP - (boss?.damage ?? 0), 0) }
    var chronicles: [Chronicle] { state.chronicles }

    func floorLevel(_ habit: Habit) -> Int { state.floorLevels[habit.rawValue] ?? 0 }

    /// 週末（一週最後一天）傍晚後，或新的一週前三天還沒回顧上週時，可以做每週回顧
    var reviewWeekStart: Date? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedWeekly") { return weekStart }
        #endif
        let calendar = AppSettings.calendar
        let lastDay = weekStart.adding(days: 6)
        if calendar.isDateInToday(lastDay), Calendar.current.component(.hour, from: .now) >= 18,
           state.reviews[weekKey] == nil {
            return weekStart
        }
        let previous = weekStart.adding(days: -7)
        if Date.now < weekStart.adding(days: 3), state.reviews[previous.dayKey] == nil,
           state.chronicles.contains(where: { $0.weekStart == previous }) {
            return previous
        }
        return nil
    }

    // MARK: 讀資料

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedWeekly") { seedForScreenshots(); return }
        #endif
        let health = HealthKitManager.shared
        let log = LogService.shared
        let start = weekStart.adding(days: -35)
        let steps = await health.dailySteps(from: start, to: .now)
        let nights = await health.allSleepNights(from: start, to: .now)
        let totals = log.dayTotals(from: start, days: 36)
        // 每天記錄了哪幾餐（一次查完，不要每天查一次資料庫）
        let end = Date.now.startOfDay.adding(days: 1)
        let foods = (try? AppDatabase.context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        var meals: [Date: Set<MealType>] = [:]
        for food in foods where [MealType.breakfast, .lunch, .dinner].contains(food.mealType) {
            meals[food.date.startOfDay, default: []].insert(food.mealType)
        }

        func progress(_ habit: Habit, on day: Date) -> HabitProgress {
            let level = floorLevel(habit)
            let value: Double
            switch habit {
            case .water: value = totals[day]?.water ?? 0
            case .steps: value = Calendar.current.isDateInToday(day) ? health.steps : steps[day] ?? 0
            case .sleep: value = nights[day].map { $0.hours * $0.weight } ?? 0
            case .logging: value = Double(meals[day]?.count ?? 0)
            }
            return HabitProgress(value: value, floor: habit.floor(level: level), ideal: habit.ideal)
        }

        let todayDate = Date.now.startOfDay
        today = Dictionary(uniqueKeysWithValues: Habit.allCases.map { ($0, progress($0, on: todayDate)) })

        // 這週每天
        var weekTiers: [Date: [Habit: QuestTier]] = [:]
        var day = weekStart
        while day <= todayDate {
            weekTiers[day] = Dictionary(uniqueKeysWithValues: Habit.allCases.map { ($0, progress($0, on: day).tier) })
            day = day.adding(days: 1)
        }
        week = weekTiers

        // 連續保底
        var result: [Habit: Int] = [:]
        for habit in Habit.allCases {
            var count = 0
            var cursor = todayDate
            if progress(habit, on: cursor).tier == .none { cursor = cursor.adding(days: -1) }
            while cursor >= start, progress(habit, on: cursor).tier >= .floor {
                count += 1
                cursor = cursor.adding(days: -1)
            }
            result[habit] = count
        }
        streaks = result

        // 上週結束了：記一章編年史
        let previous = weekStart.adding(days: -7)
        if !state.chronicles.contains(where: { $0.weekStart == previous }), previous >= SpiritCollection.shared.state.start.adding(days: -6) {
            var tiers: [Date: [Habit: QuestTier]] = [:]
            for offset in 0..<7 {
                let d = previous.adding(days: offset)
                tiers[d] = Dictionary(uniqueKeysWithValues: Habit.allCases.map { ($0, progress($0, on: d).tier) })
            }
            state.chronicles.insert(chronicle(start: previous, tiers: tiers, steps: steps, nights: nights), at: 0)
            state.chronicles = Array(state.chronicles.prefix(12))
        }

        // 這週的頭目：上週最弱的習慣
        if state.bosses[weekKey] == nil {
            let lastWeek = (0..<7).map { previous.adding(days: $0) }
            let weakest = Habit.allCases.min { a, b in
                lastWeek.filter { progress(a, on: $0).tier >= .floor }.count
                    < lastWeek.filter { progress(b, on: $0).tier >= .floor }.count
            } ?? .steps
            state.bosses[weekKey] = BossRecord(habit: weakest)
        }
        if var record = state.bosses[weekKey] {
            record.damage = weekTiers.values.reduce(0) { total, tiers in
                total + tiers.reduce(0) { $0 + $1.value.damage * ($1.key == record.habit ? 2 : 1) }
            }
            if record.damage >= Self.bossHP, !record.defeated {
                record.defeated = true
                AdventureStore.shared.addBonus(Self.bossReward, source: .boss)
                CompanionStore.shared.show("打倒\(record.habit.boss.name)了！獲得 \(Self.bossReward) 元氣幣！")
            }
            state.bosses[weekKey] = record
        }
        current = chronicle(start: weekStart, tiers: weekTiers, steps: steps, nights: nights)
        save()
    }

    private func chronicle(start: Date, tiers: [Date: [Habit: QuestTier]], steps: [Date: Double],
                           nights: [Date: SleepNight]) -> Chronicle {
        let days = (0..<7).map { start.adding(days: $0) }
        let scores = days.compactMap { day -> Int? in
            guard let night = nights[day] else { return nil }
            let recent = (0..<7).compactMap { nights[day.adding(days: -$0)] }
            return SleepScore.compute(night, recent: recent).total
        }
        let floorDays = tiers.values.filter { $0.values.filter { $0 >= .floor }.count >= 3 }.count
        let idealDays = tiers.values.filter { $0.values.allSatisfy { $0 == .ideal } }.count
        let spirits = CompanionSkin.dexOrder.filter { skin in
            guard let date = SpiritCollection.shared.unlockedDate(skin) else { return false }
            return date >= start && date < start.adding(days: 7) && skin != .onigiri
        }.map(\.title)
        let best = tiers.max { a, b in
            a.value.values.reduce(0) { $0 + $1.rawValue } < b.value.values.reduce(0) { $0 + $1.rawValue }
        }?.key
        return Chronicle(weekStart: start, steps: days.reduce(0) { $0 + (steps[$1] ?? 0) },
                         sleepAverage: scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count),
                         floorDays: floorDays, idealDays: idealDays, spirits: spirits,
                         boss: state.bosses[start.dayKey], bestDay: state.reviews[start.dayKey]?.bestDay ?? best,
                         dayScores: tiers.mapValues { $0.values.reduce(0) { $0 + $1.rawValue } })
    }

    // MARK: 每週回顧

    func submitReview(weekStart start: Date, bestDay: Date?, stuck: Habit?, adjust: Int) -> Int {
        state.reviews[start.dayKey] = Review(bestDay: bestDay, stuck: stuck, adjust: adjust)
        if let stuck, adjust != 0 {
            state.floorLevels[stuck.rawValue] = min(max(floorLevel(stuck) + adjust, -2), 2)
        }
        if let index = state.chronicles.firstIndex(where: { $0.weekStart == start }), let bestDay {
            state.chronicles[index].bestDay = bestDay
        }
        save()
        AdventureStore.shared.addBonus(Self.reviewReward, source: .review)
        return Self.reviewReward
    }

    /// 某週每天的達成分數（回顧時用）：這週用即時的，上週用編年史存的
    func dayScores(weekStart start: Date) -> [Date: Int] {
        if start == weekStart { return current?.dayScores ?? [:] }
        return state.chronicles.first { $0.weekStart == start }?.dayScores ?? [:]
    }

    /// 某週最弱的習慣（回顧時預先選好）
    func weakest(weekStart start: Date) -> Habit? {
        state.bosses[start.adding(days: 7).dayKey]?.habit ?? state.bosses[start.dayKey]?.habit
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    #if DEBUG
    /// 開發用：-seedWeekly 放一週假的進度來檢查畫面（-review 打開回顧）
    private func seedForScreenshots() {
        today = [.water: HabitProgress(value: 1800, floor: 1560, ideal: 2600),
                 .steps: HabitProgress(value: 8420, floor: 4000, ideal: 8000),
                 .sleep: HabitProgress(value: 7.5, floor: 6, ideal: 7),
                 .logging: HabitProgress(value: 2, floor: 2, ideal: 3)]
        streaks = [.water: 5, .steps: 3, .sleep: 2, .logging: 6]
        let patterns: [[QuestTier]] = [[.ideal, .floor, .ideal, .floor], [.floor, .none, .ideal, .ideal],
                                       [.ideal, .ideal, .floor, .floor], [.floor, .ideal, .ideal, .floor]]
        var tiers: [Date: [Habit: QuestTier]] = [:]
        var day = weekStart
        var index = 0
        while day <= Date.now.startOfDay {
            tiers[day] = Dictionary(uniqueKeysWithValues: zip(Habit.allCases, patterns[index % patterns.count]))
            day = day.adding(days: 1)
            index += 1
        }
        week = tiers
        state.bosses[weekKey] = BossRecord(habit: .steps, damage: 38)
        current = Chronicle(weekStart: weekStart, steps: 41230, sleepAverage: 82, floorDays: 3, idealDays: 1,
                            spirits: ["珍奶精靈", "小籠包"], boss: state.bosses[weekKey], bestDay: weekStart.adding(days: 1),
                            dayScores: tiers.mapValues { $0.values.reduce(0) { $0 + $1.rawValue } })
        showReview = ProcessInfo.processInfo.arguments.contains("-review")
    }
    #endif
}
