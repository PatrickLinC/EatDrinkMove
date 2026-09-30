import Foundation
import SwiftData
import SwiftUI

// MARK: - 今日事件

/// 每天早上抽出的事件：只給額外獎勵，沒做到不扣任何東西
enum DailyEvent: String, CaseIterable {
    case calm, meteor, market, training, spring, traveler

    var title: String {
        switch self {
        case .calm: "平靜的一天"
        case .meteor: "流星雨夜"
        case .market: "市集日"
        case .training: "修行日"
        case .spring: "泉水節"
        case .traveler: "遠方來客"
        }
    }

    var detail: String {
        switch self {
        case .calm: "大陸很安靜，照自己的步調冒險就好。"
        case .meteor: "今晚 11 點前睡著，明早夢境能量加倍。"
        case .market: "記錄早餐、午餐、晚餐，額外 +5 元氣幣。"
        case .training: "運動滿 20 分鐘，額外 +5 元氣幣。"
        case .spring: "喝水達標，額外 +5 元氣幣。"
        case .traveler: "走滿 8,000 步，路上會遇到送禮的旅人，額外 +8 元氣幣。"
        }
    }

    var art: PixelArt {
        switch self {
        case .calm: .sun
        case .meteor: .star
        case .market: .bowl
        case .training: .dumbbell
        case .spring: .drop
        case .traveler: .footprint
        }
    }

    var bonus: Int {
        switch self {
        case .calm, .meteor: 0
        case .market, .training, .spring: 5
        case .traveler: 8
        }
    }

    /// 同一天永遠抽到同一個（用日期算，不是隨機亂數）；一半左右是平靜日
    static func of(_ day: Date) -> DailyEvent {
        let key = day.dayKey
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        switch hash % 100 {
        case ..<48: return .calm
        case ..<60: return .meteor
        case ..<70: return .market
        case ..<79: return .training
        case ..<89: return .spring
        default: return .traveler
        }
    }
}

/// 營火時選的明天小目標
enum TomorrowGoal: String, CaseIterable, Identifiable {
    case sleepEarly, drinkWater, walkMore, eatVeggies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepEarly: "早點睡"
        case .drinkWater: "多喝水"
        case .walkMore: "多走路"
        case .eatVeggies: "吃蔬菜"
        }
    }

    var art: PixelArt {
        switch self {
        case .sleepEarly: .moon
        case .drinkWater: .drop
        case .walkMore: .footprint
        case .eatVeggies: .bowl
        }
    }
}

// MARK: - 元氣幣

/// 元氣幣的來源（每種都有上限，只獎勵健康行為）
enum CoinSource: String, CaseIterable {
    case sleep, steps, water, meals, protein, event, journey, perk, calm, boss, review, explore

    var title: String {
        switch self {
        case .sleep: "夢境能量"
        case .steps: "步數"
        case .water: "喝水達標"
        case .meals: "記錄三餐"
        case .protein: "蛋白質達標"
        case .event: "今日事件"
        case .journey: "旅途見聞"
        case .perk: "夥伴特性"
        case .calm: "靜心呼吸"
        case .boss: "頭目戰"
        case .review: "每週回顧"
        case .explore: "開拓地圖"
        }
    }
}

/// 某一天白天的冒險成果
struct DayProgress: Equatable {
    var steps: Double = 0
    var water: Double = 0
    var waterGoal: Double = 1
    var loggedMeals: Set<MealType> = []
    var protein: Double = 0
    var proteinGoal: Double = 1
    var exerciseMinutes: Double = 0

    var mainMealsLogged: Int { [MealType.breakfast, .lunch, .dinner].filter(loggedMeals.contains).count }

    /// 白天的元氣幣（夢境能量另外算）
    func coins(event: DailyEvent) -> [CoinSource: Int] {
        var result: [CoinSource: Int] = [:]
        result[.steps] = min(Int(steps / 1000), 15)
        result[.water] = water >= waterGoal ? 5 : 0
        result[.meals] = mainMealsLogged * 2
        result[.protein] = protein >= proteinGoal * 0.9 ? 3 : 0
        result[.event] = eventDone(event) ? event.bonus : 0
        return result
    }

    func eventDone(_ event: DailyEvent) -> Bool {
        switch event {
        case .calm, .meteor: false
        case .market: mainMealsLogged >= 3
        case .training: exerciseMinutes >= 20
        case .spring: water >= waterGoal
        case .traveler: steps >= 8000
        }
    }
}

// MARK: - 冒險進度

/// 夢境結算、營火、元氣幣
@MainActor
final class AdventureStore: ObservableObject {
    static let shared = AdventureStore()

    private struct State: Codable {
        var balance = 0
        /// 累計拿到的元氣幣（花掉的不扣，稱號用）
        var lifetime = 0
        /// 每天各來源已經領過的元氣幣（dayKey → 來源 → 枚數），之後進度變多只補差額
        var claimed: [String: [String: Int]] = [:]
        /// 已經看過夢境結算的那天
        var morningSeen = ""
        /// 明天的小目標（key 是「明天」的 dayKey）
        var goals: [String: String] = [:]

        init() {}

        /// 新版多了欄位時，舊的存檔也讀得進來（不會把元氣幣歸零）
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            balance = try container.decodeIfPresent(Int.self, forKey: .balance) ?? 0
            lifetime = try container.decodeIfPresent(Int.self, forKey: .lifetime) ?? balance
            claimed = try container.decodeIfPresent([String: [String: Int]].self, forKey: .claimed) ?? [:]
            morningSeen = try container.decodeIfPresent(String.self, forKey: .morningSeen) ?? ""
            goals = try container.decodeIfPresent([String: String].self, forKey: .goals) ?? [:]
        }
    }

    private static let key = "adventureState"
    @Published private var state: State

    /// 昨晚的睡眠與分數、最近一週的作息類型
    @Published private(set) var lastNight: SleepNight?
    @Published private(set) var score: SleepScore?
    @Published private(set) var chronotype: Chronotype?
    @Published private(set) var today = DayProgress()
    /// 今天早上要顯示夢境結算
    @Published var showMorning = false
    @Published var showCampfire = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedCamp") {
            state.balance = 260
            state.lifetime = 540
        }
        #endif
    }

    var balance: Int { state.balance }
    var lifetimeEarned: Int { state.lifetime }

    /// 花元氣幣（蓋營地）；不夠就不扣
    func spend(_ coins: Int) -> Bool {
        guard coins >= 0, state.balance >= coins else { return false }
        state.balance -= coins
        save()
        objectWillChange.send()
        return true
    }
    var todayEvent: DailyEvent { DailyEvent.of(.now) }
    var todayGoal: TomorrowGoal? { state.goals[Date.now.dayKey].flatMap(TomorrowGoal.init(rawValue:)) }
    var tomorrowGoal: TomorrowGoal? { state.goals[Date.now.adding(days: 1).dayKey].flatMap(TomorrowGoal.init(rawValue:)) }

    /// 營火可以升起的時間
    var campfireAvailable: Bool { Calendar.current.component(.hour, from: .now) >= 18 }

    // MARK: 讀資料

    /// App 回到前景時呼叫：讀睡眠、今天的進度；早上第一次打開就排夢境結算
    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedAdventure") { seedForScreenshots(); return }
        #endif
        let health = HealthKitManager.shared
        let nights = await health.allSleepNights(from: Date.now.adding(days: -7), to: .now)
        let sorted = nights.keys.sorted().compactMap { nights[$0] }
        lastNight = nights[Date.now.startOfDay]
        score = lastNight.map { SleepScore.compute($0, recent: Array(sorted.suffix(7))) }
        chronotype = Chronotype.from(Array(sorted.suffix(7)))
        today = await progress(on: .now)

        let hour = Calendar.current.component(.hour, from: .now)
        if (4..<15).contains(hour), state.morningSeen != Date.now.dayKey,
           UserDefaults.standard.bool(forKey: SettingKey.hasOnboarded) {
            showMorning = true
        }
    }

    /// 只重算今天白天的進度（記錄飲食、喝水後）
    func refreshToday() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedAdventure") { return }
        #endif
        today = await progress(on: .now)
    }

    #if DEBUG
    /// 開發用：模擬器沒有健康資料，放一晚假的睡眠和今天的進度來檢查畫面（-morning、-campfire 直接打開）
    private func seedForScreenshots() {
        let wake = Date.at(minutes: 7 * 60 + 5)
        func night(_ offset: Int, bed: Int) -> SleepNight {
            let end = wake.adding(days: -offset)
            let start = Date.at(minutes: bed, on: end.adding(days: -1))
            return SleepNight(start: start, end: end, asleep: end.timeIntervalSince(start) - 12 * 60,
                              deep: 70 * 60, rem: 100 * 60, awake: 12 * 60)
        }
        let recent = [night(4, bed: 23 * 60 + 40), night(3, bed: 23 * 60 + 10), night(2, bed: 23 * 60 + 50),
                      night(1, bed: 23 * 60 + 30), night(0, bed: 23 * 60 + 20)]
        lastNight = recent.last
        score = lastNight.map { SleepScore.compute($0, recent: recent) }
        chronotype = Chronotype.from(recent)
        today = DayProgress(steps: 8420, water: 2100, waterGoal: 2600, loggedMeals: [.breakfast, .lunch],
                            protein: 70, proteinGoal: 90, exerciseMinutes: 25)
        let arguments = ProcessInfo.processInfo.arguments
        showMorning = arguments.contains("-morning")
        showCampfire = arguments.contains("-campfire")
    }
    #endif

    /// 某一天白天的進度（步數與運動分鐘從「健康」讀，飲食喝水從 App 的紀錄讀）
    func progress(on day: Date) async -> DayProgress {
        let health = HealthKitManager.shared
        let start = day.startOfDay
        let end = min(start.adding(days: 1), .now)
        let log = LogService.shared
        let foods = log.foods(on: start)
        var progress = DayProgress()
        progress.steps = Calendar.current.isDateInToday(start)
            ? health.steps : await health.dailySteps(from: start, to: end)[start] ?? 0
        progress.water = log.waters(on: start).reduce(0) { $0 + $1.amount }
        progress.waterGoal = max(AppSettings.waterGoal, 1)
        progress.loggedMeals = Set(foods.map(\.mealType))
        progress.protein = foods.reduce(0) { $0 + $1.protein }
        progress.proteinGoal = max(AppSettings.proteinGoal, 1)
        let watchMinutes = await health.sum(.appleExerciseTime, unit: .minute(), from: start, to: end)
        let manualMinutes = (try? AppDatabase.context.fetch(FetchDescriptorFactory.exercises(on: start)))?
            .reduce(0) { $0 + $1.minutes } ?? 0
        progress.exerciseMinutes = watchMinutes + manualMinutes
        return progress
    }

    // MARK: 領獎

    /// 還沒領的差額
    func unclaimed(_ coins: [CoinSource: Int], on day: Date) -> [CoinSource: Int] {
        let claimed = state.claimed[day.dayKey] ?? [:]
        var result: [CoinSource: Int] = [:]
        for (source, value) in coins {
            let rest = value - (claimed[source.rawValue] ?? 0)
            if rest > 0 { result[source] = rest }
        }
        return result
    }

    /// 白天的元氣幣＋出戰精靈的特性加成
    func dayCoins(_ progress: DayProgress, event: DailyEvent) -> [CoinSource: Int] {
        var coins = progress.coins(event: event)
        guard let perk = CampStore.shared.activePerk?.perk else { return coins }
        var bonus = 0
        switch perk {
        case .bonus(let source, let extra):
            if source != .sleep, (coins[source] ?? 0) > 0 { bonus = extra }
        case .bigWalk(let steps, let extra):
            if progress.steps >= steps { bonus = extra }
        case .percentDay(let percent):
            let base = coins.values.reduce(0, +)
            bonus = base > 0 ? max(1, Int((Double(base * percent) / 100).rounded(.up))) : 0
        case .earlyWake, .earlySleep, .journeyCap:
            break
        }
        if bonus > 0 { coins[.perk] = bonus }
        return coins
    }

    /// 今天白天還沒領的元氣幣
    var todayUnclaimed: [CoinSource: Int] { unclaimed(dayCoins(today, event: todayEvent), on: .now) }

    /// 夢境能量：睡眠分數每 10 分 1 枚，手動補記減半；前一天是流星雨夜且 11 點前睡著就加倍；再加出戰精靈的特性
    func sleepCoins() -> (coins: Int, meteorBonus: Bool, perk: Int) {
        guard let night = lastNight, let score else { return (0, false, 0) }
        var coins = score.total / 10
        if night.isManual { coins /= 2 }
        let meteor = DailyEvent.of(Date.now.adding(days: -1)) == .meteor && night.isAsleep(before: 23 * 60)
        if meteor { coins *= 2 }
        var perk = 0
        switch CampStore.shared.activePerk?.perk {
        case .bonus(.sleep, let extra): perk = coins > 0 ? extra : 0
        case .earlyWake(let extra): perk = night.wakeMinutes < 7 * 60 + 30 && night.hours >= 6 ? extra : 0
        case .earlySleep(let before, let extra): perk = night.isAsleep(before: before) && night.hours >= 6 ? extra : 0
        default: break
        }
        return (coins, meteor, perk)
    }

    /// 夢境結算：領夢境能量，也把昨天沒在營火領的補發
    func claimMorning() async -> (sleep: Int, meteor: Bool, perk: Int, yesterday: Int) {
        let (sleep, meteor, perk) = sleepCoins()
        let yesterdayDate = Date.now.adding(days: -1)
        let yesterday = await progress(on: yesterdayDate)
        let leftover = unclaimed(dayCoins(yesterday, event: DailyEvent.of(yesterdayDate)), on: yesterdayDate)
        credit(leftover, on: yesterdayDate)
        // 夢境能量的特性加成直接算進夢境能量
        credit(unclaimed([.sleep: sleep + perk], on: .now), on: .now)
        state.morningSeen = Date.now.dayKey
        save()
        return (sleep, meteor, perk, leftover.values.reduce(0, +))
    }

    /// 營火：收下今天白天的元氣幣
    @discardableResult
    func claimToday() -> Int {
        let coins = todayUnclaimed
        credit(coins, on: .now)
        save()
        return coins.values.reduce(0, +)
    }

    /// 其他地方給的獎勵（例如旅途見聞），直接算進今天
    func addBonus(_ coins: Int, source: CoinSource) {
        credit([source: coins], on: .now)
        save()
        objectWillChange.send()
    }

    func setTomorrowGoal(_ goal: TomorrowGoal) {
        state.goals[Date.now.adding(days: 1).dayKey] = goal.rawValue
        // 只留最近幾天
        let keep = Set((-3...1).map { Date.now.adding(days: $0).dayKey })
        state.goals = state.goals.filter { keep.contains($0.key) }
        save()
        objectWillChange.send()
    }

    private func credit(_ coins: [CoinSource: Int], on day: Date) {
        guard !coins.isEmpty else { return }
        var claimed = state.claimed[day.dayKey] ?? [:]
        for (source, value) in coins {
            claimed[source.rawValue, default: 0] += value
            state.balance += value
            state.lifetime += max(value, 0)
        }
        // 帶著的精靈一起累積羈絆
        CampStore.shared.addBond(coins.values.reduce(0, +))
        state.claimed[day.dayKey] = claimed
        // 領獎紀錄只留最近兩週
        let cutoff = Date.now.adding(days: -14).dayKey
        state.claimed = state.claimed.filter { $0.key >= cutoff }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// 查某天的運動紀錄
enum FetchDescriptorFactory {
    static func exercises(on day: Date) -> FetchDescriptor<ExerciseEntry> {
        let start = day.startOfDay
        let end = start.adding(days: 1)
        return FetchDescriptor(predicate: #Predicate<ExerciseEntry> { $0.date >= start && $0.date < end })
    }
}
