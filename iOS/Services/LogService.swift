import Foundation
import SwiftData

/// 某一天的加總（戰績圖表、AI 軍師用）
struct DayTotals {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var sodium: Double = 0
    var water: Double = 0
    /// 手動記錄的運動消耗（Apple Watch 的另外從「健康」讀）
    var manualExercise: Double = 0
}

/// 今天的記錄狀況，提醒排程會用到
struct TodayStatus {
    var handledMeals: Set<MealType>
    var water: Double
    var waterGoal: Double
    var lastWater: Date?
    var calories: Double
}

/// 所有新增、修改、刪除都經過這裡。
/// App 畫面、通知按鈕、Siri、Apple Watch 用的是同一套邏輯：
/// 存進資料庫 → 同步到「健康」→ 重新排程提醒 → 更新手錶
@MainActor
final class LogService {
    static let shared = LogService()

    private var context: ModelContext { AppDatabase.context }
    private var health: HealthKitManager { HealthKitManager.shared }

    // MARK: - 喝水

    @discardableResult
    func logWater(_ ml: Double, date: Date = .now, source: EntrySource = .app) -> WaterEntry {
        let entry = WaterEntry(amount: ml, date: date, source: source)
        context.insert(entry)
        commit()
        Task { await sync(entry) }
        return entry
    }

    func delete(_ entry: WaterEntry) {
        let id = entry.id
        context.delete(entry)
        commit()
        Task { await health.deleteSamples(entryID: id, types: [.dietaryWater]) }
    }

    // MARK: - 飲食

    /// 照片和照片貼紙放在第一項（呼叫端會把拍照辨識的那一項排在最前面），其餘用 emoji 貼紙
    func logFoods(_ drafts: [FoodDraft], meal: MealType, date: Date, photo: Data? = nil, sticker: Data? = nil) {
        guard !drafts.isEmpty else { return }
        var entries: [FoodEntry] = []
        for (index, draft) in drafts.enumerated() {
            let entry = FoodEntry(draft: draft, mealType: meal, date: date,
                                  photoData: index == 0 ? photo : nil,
                                  stickerData: index == 0 ? sticker : nil)
            context.insert(entry)
            entries.append(entry)
        }
        commit()
        Task {
            for entry in entries { await sync(entry) }
        }
    }

    func logQuickFood(_ food: QuickFood, meal: MealType? = nil, date: Date = .now, source: EntrySource) {
        logFoods([FoodDraft(quick: food, source: source)], meal: meal ?? .suggested(for: date), date: date)
    }

    /// 修改食物時的圖示
    enum IconChoice {
        /// 沿用；改名稱時自動重新配 emoji
        case auto
        /// 使用者自己挑的 emoji（不再用照片做的像素圖）
        case emoji(String)
        /// 用照片重新做的去背圖
        case photo(Data)
    }

    func update(_ entry: FoodEntry, with draft: FoodDraft, meal: MealType, date: Date, icon: IconChoice = .auto) {
        let newName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch icon {
        case .auto:
            if newName != entry.name {
                entry.emoji = FoodEmoji.guess(name: newName) // 修正名稱（例如 AI 認錯）時重新配 emoji
            }
        case .emoji(let emoji):
            entry.emoji = emoji
            entry.stickerData = nil
        case .photo(let data):
            entry.stickerData = data
        }
        entry.name = newName
        entry.portion = draft.portion
        entry.calories = draft.calories
        entry.protein = draft.protein
        entry.carbs = draft.carbs
        entry.fat = draft.fat
        entry.sodium = draft.sodium
        entry.sugar = draft.sugar
        entry.mealType = meal
        entry.date = date
        entry.healthSynced = false
        commit()
        let id = entry.id
        Task {
            await health.deleteSamples(entryID: id, types: HealthKitManager.foodTypes)
            await sync(entry)
        }
    }

    func delete(_ entry: FoodEntry) {
        let id = entry.id
        context.delete(entry)
        commit()
        Task { await health.deleteSamples(entryID: id, types: HealthKitManager.foodTypes) }
    }

    /// 把某天同一餐的內容複製到今天（「同昨天」按鈕）
    func repeatMeal(_ meal: MealType, from day: Date, to date: Date = .now) {
        let items = foods(on: day).filter { $0.mealType == meal }
        let drafts = items.map { item -> FoodDraft in
            var draft = FoodDraft(entry: item)
            draft.source = .quick
            return draft
        }
        logFoods(drafts, meal: meal, date: date)
    }

    // MARK: - 這餐沒吃

    /// 標記「沒吃」後，這一餐今天就不會再提醒
    func skipMeal(_ meal: MealType, on day: Date = .now) {
        let key = "\(day.dayKey)-\(meal.rawValue)"
        let recentKeys = Set((0..<7).map { Date.now.adding(days: -$0).dayKey })
        var keys = skippedKeys().filter { recentKeys.contains(String($0.prefix(8))) }
        keys.insert(key)
        UserDefaults.standard.set(keys.sorted().joined(separator: ","), forKey: SettingKey.skippedMeals)
        commit()
    }

    func isSkipped(_ meal: MealType, on day: Date = .now) -> Bool {
        skippedKeys().contains("\(day.dayKey)-\(meal.rawValue)")
    }

    private func skippedKeys() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: SettingKey.skippedMeals) ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    // MARK: - 運動與體重

    func logExercise(name: String, minutes: Double, calories: Double, date: Date) {
        context.insert(ExerciseEntry(name: name, minutes: minutes, calories: calories, date: date))
        commit()
    }

    func delete(_ entry: ExerciseEntry) {
        context.delete(entry)
        commit()
    }

    func logWeight(_ kg: Double, date: Date = .now) {
        let entry = WeightEntry(kg: kg, date: date)
        context.insert(entry)
        UserDefaults.standard.set(kg, forKey: SettingKey.weightKG)
        commit()
        Task { await sync(entry) }
    }

    func delete(_ entry: WeightEntry) {
        let id = entry.id
        context.delete(entry)
        commit()
        Task { await health.deleteSamples(entryID: id, types: [.bodyMass]) }
    }

    // MARK: - 查詢

    func foods(on day: Date) -> [FoodEntry] {
        let start = day.startOfDay
        let end = start.adding(days: 1)
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func waters(on day: Date) -> [WaterEntry] {
        let start = day.startOfDay
        let end = start.adding(days: 1)
        let descriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 從 start 開始連續幾天，每天的加總，key 為當天 00:00
    func dayTotals(from start: Date, days: Int) -> [Date: DayTotals] {
        let begin = start.startOfDay
        let end = begin.adding(days: days)
        var result: [Date: DayTotals] = [:]
        for offset in 0..<days { result[begin.adding(days: offset)] = DayTotals() }

        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= begin && $0.date < end }))) ?? []
        for food in foods {
            let day = food.date.startOfDay
            result[day]?.calories += food.calories
            result[day]?.protein += food.protein
            result[day]?.carbs += food.carbs
            result[day]?.fat += food.fat
            result[day]?.sodium += food.sodium
        }
        let waters = (try? context.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= begin && $0.date < end }))) ?? []
        for water in waters {
            result[water.date.startOfDay]?.water += water.amount
        }
        let exercises = (try? context.fetch(FetchDescriptor<ExerciseEntry>(
            predicate: #Predicate { $0.date >= begin && $0.date < end }))) ?? []
        for exercise in exercises {
            result[exercise.date.startOfDay]?.manualExercise += exercise.calories
        }
        return result
    }

    /// 某天手動記錄的運動消耗
    func manualExerciseCalories(on day: Date) -> Double {
        dayTotals(from: day, days: 1)[day.startOfDay]?.manualExercise ?? 0
    }

    /// 一段期間每天的體重（沒量的日子沿用前一次），未來的日子不算
    func dailyWeights(from start: Date, days: Int) -> [Date: Double] {
        let begin = start.startOfDay
        let end = begin.adding(days: days)
        var descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 2000
        let entries = (try? context.fetch(descriptor)) ?? []
        var result: [Date: Double] = [:]
        var last = entries.last { $0.date < begin }?.kg
        for offset in 0..<days {
            let day = begin.adding(days: offset)
            guard day <= Date.now else { break }
            let next = day.adding(days: 1)
            if let latest = entries.last(where: { $0.date >= day && $0.date < next }) { last = latest.kg }
            if let last { result[day] = last }
        }
        return result
    }

    /// 一段期間內有記錄飲食的日子（日期列上的小圓點）
    func loggedDays(from start: Date, to end: Date) -> Set<Date> {
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return Set(((try? context.fetch(descriptor)) ?? []).map { $0.date.startOfDay })
    }

    /// 最近吃過的食物（同名只留最新一筆）
    func recentFoods(limit: Int = 40) -> [QuickFood] {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 300
        var seen = Set<String>()
        var result: [QuickFood] = []
        for entry in (try? context.fetch(descriptor)) ?? [] where !entry.name.isEmpty && seen.insert(entry.name).inserted {
            result.append(entry.quickFood)
            if result.count >= limit { break }
        }
        return result
    }

    /// 最近 60 天最常吃的食物，依次數排序
    func frequentFoods(limit: Int = 12) -> [QuickFood] {
        let since = Date.now.adding(days: -60)
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= since },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        let entries = (try? context.fetch(descriptor)) ?? []

        var counts: [String: (count: Int, latest: FoodEntry)] = [:]
        for entry in entries where !entry.name.isEmpty {
            if let existing = counts[entry.name] {
                counts[entry.name] = (existing.count + 1, existing.latest)
            } else {
                counts[entry.name] = (1, entry)
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.latest.date > $1.latest.date }
            .prefix(limit)
            .map { $0.latest.quickFood }
    }

    /// 連續有記錄飲食的天數（今天還沒記錄的話從昨天開始算）
    func streak() -> Int {
        let since = Date.now.adding(days: -366).startOfDay
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= since })
        let days = Set(((try? context.fetch(descriptor)) ?? []).map { $0.date.startOfDay })
        var day = Date.now.startOfDay
        if !days.contains(day) { day = day.adding(days: -1) }
        var count = 0
        while days.contains(day) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }

    func todayStatus() -> TodayStatus {
        let foods = foods(on: .now)
        let waters = waters(on: .now)
        var handled = Set(foods.map(\.mealType))
        for meal in MealType.allCases where isSkipped(meal) { handled.insert(meal) }
        return TodayStatus(
            handledMeals: handled,
            water: waters.sum(\.amount),
            waterGoal: AppSettings.waterGoal,
            lastWater: waters.last?.date,
            calories: foods.sum(\.calories)
        )
    }

    func todaySummary() -> DailySummary {
        let foods = foods(on: .now)
        return DailySummary(
            date: .now,
            calories: foods.sum(\.calories),
            calorieGoal: AppSettings.calorieGoal,
            protein: foods.sum(\.protein),
            proteinGoal: AppSettings.proteinGoal,
            waterML: waters(on: .now).sum(\.amount),
            waterGoalML: AppSettings.waterGoal,
            steps: health.steps,
            stepGoal: AppSettings.stepGoal,
            activeCalories: health.activeCalories,
            exerciseMinutes: health.exerciseMinutes,
            loggedMeals: Array(Set(foods.map(\.mealType))),
            quickFoods: frequentFoods(limit: 10),
            companion: (CompanionSkin.active ?? .onigiri).rawValue,
            companionShiny: CompanionSkin.active.map { UserDefaults.standard.bool(forKey: SettingKey.companionShiny)
                && SpiritCollection.isShinyUnlocked($0) } ?? false,
            companionName: UserDefaults.standard.string(forKey: SettingKey.companionName) ?? "小卡"
        )
    }

    // MARK: - 同步到「健康」

    /// 補寫先前失敗的資料（例如手機上鎖時從通知記錄的喝水）
    func syncPendingToHealth() async {
        guard health.isAvailable, !health.needsAuthorization else { return }
        let since = Date.now.adding(days: -14)
        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.healthSynced == false && $0.date >= since }))) ?? []
        let waters = (try? context.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.healthSynced == false && $0.date >= since }))) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.healthSynced == false && $0.date >= since }))) ?? []
        for entry in foods { await sync(entry) }
        for entry in waters { await sync(entry) }
        for entry in weights { await sync(entry) }
    }

    private func sync(_ entry: FoodEntry) async {
        let ok = await health.saveFood(
            name: entry.name, calories: entry.calories, protein: entry.protein, carbs: entry.carbs,
            fat: entry.fat, sodium: entry.sodium, sugar: entry.sugar, date: entry.date, entryID: entry.id
        )
        if ok {
            entry.healthSynced = true
            try? context.save()
        }
    }

    private func sync(_ entry: WaterEntry) async {
        if await health.saveWater(ml: entry.amount, date: entry.date, entryID: entry.id) {
            entry.healthSynced = true
            try? context.save()
        }
    }

    private func sync(_ entry: WeightEntry) async {
        if await health.saveWeight(kg: entry.kg, date: entry.date, entryID: entry.id) {
            entry.healthSynced = true
            try? context.save()
        }
    }

    // MARK: -

    private func commit() {
        do {
            try context.save()
        } catch {
            print("資料儲存失敗：\(error)")
        }
        NotificationManager.shared.scheduleRefresh()
        PhoneConnectivity.shared.pushSummary()
    }
}
