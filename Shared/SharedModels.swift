import Foundation

// iPhone 與 Apple Watch 共用的資料型別。

/// 一餐的類型（順序就是一天裡的先後：早餐、午餐、點心、晚餐、宵夜）
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner, lateNight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .snack: "點心"
        case .dinner: "晚餐"
        case .lateNight: "宵夜"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .snack: "cup.and.saucer.fill"
        case .dinner: "moon.stars.fill"
        case .lateNight: "moon.zzz.fill"
        }
    }

    /// 依照時間猜是哪一餐，記錄時就不用再選一次
    static func suggested(for date: Date = .now) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<10: .breakfast
        case 10..<15: .lunch
        case 17..<21: .dinner
        case 21..<24, 0..<4: .lateNight
        default: .snack
        }
    }
}

/// 可以一鍵記錄的常吃食物（手錶上也會顯示）
struct QuickFood: Codable, Hashable, Identifiable {
    var name: String
    var emoji: String
    var portion: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sodium: Double
    var sugar: Double

    var id: String { name }
}

/// 今日摘要：iPhone 算好後送到手錶顯示
struct DailySummary: Codable, Equatable {
    var date: Date
    var calories: Double
    var calorieGoal: Double
    var protein: Double
    var proteinGoal: Double
    var waterML: Double
    var waterGoalML: Double
    var steps: Double
    var stepGoal: Double
    var activeCalories: Double
    var exerciseMinutes: Double
    var loggedMeals: [MealType]
    var quickFoods: [QuickFood]
    /// 帶在身邊的精靈（CompanionSkin 的 rawValue）、是不是閃光版、名字；舊版 iPhone 送來的沒有
    var companion: String? = nil
    var companionShiny: Bool? = nil
    var companionName: String? = nil

    static let empty = DailySummary(
        date: .distantPast, calories: 0, calorieGoal: 1800, protein: 0, proteinGoal: 90,
        waterML: 0, waterGoalML: 2000, steps: 0, stepGoal: 8000, activeCalories: 0,
        exerciseMinutes: 0, loggedMeals: [], quickFoods: []
    )

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// 摘要若是昨天的，數值歸零但保留目標與常吃食物
    func normalizedForToday() -> DailySummary {
        guard !isToday else { return self }
        var summary = DailySummary.empty
        summary.date = .now
        summary.calorieGoal = calorieGoal
        summary.proteinGoal = proteinGoal
        summary.waterGoalML = waterGoalML
        summary.stepGoal = stepGoal
        summary.quickFoods = quickFoods
        summary.companion = companion
        summary.companionShiny = companionShiny
        summary.companionName = companionName
        return summary
    }
}

/// WatchConnectivity 訊息的欄位名稱
enum WatchMessage {
    static let action = "action"
    static let id = "id"
    static let amount = "amount"
    static let food = "food"
    static let date = "date"
    static let summary = "summary"

    enum Action {
        static let logWater = "logWater"
        static let logFood = "logFood"
        static let requestSummary = "requestSummary"
    }
}
