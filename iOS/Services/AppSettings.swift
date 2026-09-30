import Foundation

enum SettingKey {
    static let hasOnboarded = "hasOnboarded"

    // 每日目標
    static let calorieGoal = "calorieGoal"
    static let proteinGoal = "proteinGoal"
    static let carbsGoal = "carbsGoal"
    static let fatGoal = "fatGoal"
    static let sodiumGoal = "sodiumGoal"
    static let waterGoal = "waterGoal"
    static let stepGoal = "stepGoal"
    /// 每日建議運動消耗（大卡）
    static let burnGoal = "burnGoal"

    // 個人資料
    static let userName = "userName"
    static let avatar = "avatar"
    static let sex = "sex"
    static let age = "age"
    static let heightCM = "heightCM"
    static let weightKG = "weightKG"
    static let targetWeightKG = "targetWeightKG"
    static let activityLevel = "activityLevel"
    static let asianAdjust = "asianAdjust"
    /// 熱量改用國健署「國人膳食營養素參考攝取量」依年齡、性別、活動量查表
    static let useDRIEnergy = "useDRIEnergy"

    // 偏好
    static let autoGoals = "autoGoals"
    /// 目標：auto（依目標體重判斷）、lose、maintain、gain
    static let goalMode = "goalMode"
    /// 飲食方式（三大營養素比例），見 GoalCalculator.MacroStyle
    static let macroStyle = "macroStyle"
    static let addBackExercise = "addBackExercise"
    static let firstWeekday = "firstWeekday"
    static let cupSize = "cupSize"
    static let themeMode = "themeMode"

    // 提醒（時間都以午夜起算的分鐘數儲存）
    static let mealReminders = "mealReminders"
    static let breakfastTime = "breakfastTime"
    static let lunchTime = "lunchTime"
    static let dinnerTime = "dinnerTime"
    static let waterReminders = "waterReminders"
    static let waterInterval = "waterInterval"
    static let wakeTime = "wakeTime"
    static let sleepTime = "sleepTime"
    static let eveningReview = "eveningReview"
    static let eveningTime = "eveningTime"
    static let sedentaryReminders = "sedentaryReminders"
    static let workStart = "workStart"
    static let workEnd = "workEnd"
    static let sedentaryWeekdaysOnly = "sedentaryWeekdaysOnly"

    // AI
    static let aiProvider = "aiProvider"
    static let geminiModel = "geminiModel"
    static let claudeModel = "claudeModel"

    // AI 小夥伴
    static let companionEnabled = "companionEnabled"
    static let companionTips = "companionTips"
    static let companionName = "companionName"
    static let companionStyle = "companionStyle"
    /// 造型：CompanionSkin 的 rawValue，或「emoji:🐱」；沒設定時跟著回話風格
    static let companionSkin = "companionSkin"
    /// 小夥伴用閃光版（要先喚醒那隻的閃光版）
    static let companionShiny = "companionShiny"
    static let companionOnRight = "companionOnRight"
    /// 在畫面上的高度（0～1）
    static let companionY = "companionY"
    static let companionLastTip = "companionLastTip"
    static let companionChat = "companionChat"

    // 其他
    static let skippedMeals = "skippedMeals"
    static let processedWatchIDs = "processedWatchIDs"
}

enum AppSettings {
    enum Defaults {
        static let calorieGoal: Double = 1800
        static let proteinGoal: Double = 90
        static let carbsGoal: Double = 200
        static let fatGoal: Double = 55
        static let sodiumGoal: Double = TaiwanDRI.sodiumLimit
        static let waterGoal: Double = 2000
        static let stepGoal: Double = 8000
        /// 約快走一小時
        static let burnGoal: Double = 300
        static let sex = GoalCalculator.Sex.female.rawValue
        static let age = 30
        static let heightCM: Double = 165
        static let weightKG: Double = 60
        static let targetWeightKG: Double = 55
        static let activityLevel = 1
        static let userName = "我"
        static let avatar = "🍓"
        /// 2 = 週一（Calendar 的 1 是週日）
        static let firstWeekday = 2
        static let cupSize: Double = 250
        static let themeMode = "system"
        static let goalMode = "auto"
        static let macroStyle = GoalCalculator.MacroStyle.recommended.rawValue
        static let breakfastTime = 8 * 60
        static let lunchTime = 12 * 60 + 30
        static let dinnerTime = 18 * 60 + 30
        static let waterInterval = 120
        static let wakeTime = 7 * 60 + 30
        static let sleepTime = 23 * 60
        static let eveningTime = 21 * 60 + 30
        static let workStart = 9 * 60
        static let workEnd = 18 * 60
        static let aiProvider = AIProvider.apple.rawValue
        static let geminiModel = "gemini-3.8-flash"
        static let claudeModel = "claude-opus-5"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingKey.hasOnboarded: false,
            SettingKey.calorieGoal: Defaults.calorieGoal,
            SettingKey.proteinGoal: Defaults.proteinGoal,
            SettingKey.carbsGoal: Defaults.carbsGoal,
            SettingKey.fatGoal: Defaults.fatGoal,
            SettingKey.sodiumGoal: Defaults.sodiumGoal,
            SettingKey.waterGoal: Defaults.waterGoal,
            SettingKey.stepGoal: Defaults.stepGoal,
            SettingKey.burnGoal: Defaults.burnGoal,
            SettingKey.sex: Defaults.sex,
            SettingKey.age: Defaults.age,
            SettingKey.heightCM: Defaults.heightCM,
            SettingKey.weightKG: Defaults.weightKG,
            SettingKey.targetWeightKG: Defaults.targetWeightKG,
            SettingKey.activityLevel: Defaults.activityLevel,
            SettingKey.asianAdjust: true,
            SettingKey.useDRIEnergy: false,
            SettingKey.userName: Defaults.userName,
            SettingKey.avatar: Defaults.avatar,
            SettingKey.autoGoals: true,
            SettingKey.addBackExercise: true,
            SettingKey.firstWeekday: Defaults.firstWeekday,
            SettingKey.cupSize: Defaults.cupSize,
            SettingKey.themeMode: Defaults.themeMode,
            SettingKey.goalMode: Defaults.goalMode,
            SettingKey.macroStyle: Defaults.macroStyle,
            SettingKey.mealReminders: true,
            SettingKey.breakfastTime: Defaults.breakfastTime,
            SettingKey.lunchTime: Defaults.lunchTime,
            SettingKey.dinnerTime: Defaults.dinnerTime,
            SettingKey.waterReminders: true,
            SettingKey.waterInterval: Defaults.waterInterval,
            SettingKey.wakeTime: Defaults.wakeTime,
            SettingKey.sleepTime: Defaults.sleepTime,
            SettingKey.eveningReview: true,
            SettingKey.eveningTime: Defaults.eveningTime,
            SettingKey.aiProvider: Defaults.aiProvider,
            SettingKey.geminiModel: Defaults.geminiModel,
            SettingKey.claudeModel: Defaults.claudeModel,
            SettingKey.skippedMeals: "",
            SettingKey.companionEnabled: true,
            SettingKey.companionTips: true,
            SettingKey.companionName: "小卡",
            SettingKey.companionStyle: CompanionStyle.motivating.rawValue,
            SettingKey.companionOnRight: true,
            SettingKey.companionY: 0.72,
            SettingKey.sedentaryReminders: false,
            SettingKey.workStart: Defaults.workStart,
            SettingKey.workEnd: Defaults.workEnd,
            SettingKey.sedentaryWeekdaysOnly: true,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var calorieGoal: Double { d.double(forKey: SettingKey.calorieGoal) }
    static var proteinGoal: Double { d.double(forKey: SettingKey.proteinGoal) }
    static var sodiumGoal: Double { d.double(forKey: SettingKey.sodiumGoal) }
    static var waterGoal: Double { d.double(forKey: SettingKey.waterGoal) }
    static var stepGoal: Double { d.double(forKey: SettingKey.stepGoal) }
    static var burnGoal: Double { d.double(forKey: SettingKey.burnGoal) }
    static var weightKG: Double { d.double(forKey: SettingKey.weightKG) }
    static var targetWeightKG: Double { d.double(forKey: SettingKey.targetWeightKG) }
    static var cupSize: Double { max(50, d.double(forKey: SettingKey.cupSize)) }
    static var addBackExercise: Bool { d.bool(forKey: SettingKey.addBackExercise) }
    static var sedentaryReminders: Bool { d.bool(forKey: SettingKey.sedentaryReminders) }
    static var workStart: Int { d.integer(forKey: SettingKey.workStart) }
    static var workEnd: Int { d.integer(forKey: SettingKey.workEnd) }
    static var sedentaryWeekdaysOnly: Bool { d.bool(forKey: SettingKey.sedentaryWeekdaysOnly) }

    /// 依「每週的第一天」設定的日曆（週一或週日開始）
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = d.integer(forKey: SettingKey.firstWeekday) == 1 ? 1 : 2
        return calendar
    }

    static func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date.startOfDay
    }

    /// 由目標體重決定是減脂、維持還是增肌
    static var derivedGoal: GoalCalculator.Goal {
        let diff = targetWeightKG - weightKG
        if diff < -0.5 { return .lose }
        if diff > 0.5 { return .gain }
        return .maintain
    }

    /// 使用者選的目標；選「自動」時依目標體重判斷
    static var effectiveGoal: GoalCalculator.Goal {
        GoalCalculator.Goal(rawValue: d.string(forKey: SettingKey.goalMode) ?? "") ?? derivedGoal
    }

    static var macroStyle: GoalCalculator.MacroStyle {
        GoalCalculator.MacroStyle(rawValue: d.string(forKey: SettingKey.macroStyle) ?? "") ?? .recommended
    }

    static var mealReminders: Bool { d.bool(forKey: SettingKey.mealReminders) }
    static var waterReminders: Bool { d.bool(forKey: SettingKey.waterReminders) }
    static var waterInterval: Int { d.integer(forKey: SettingKey.waterInterval) }
    static var wakeTime: Int { d.integer(forKey: SettingKey.wakeTime) }
    static var sleepTime: Int { d.integer(forKey: SettingKey.sleepTime) }
    static var eveningReview: Bool { d.bool(forKey: SettingKey.eveningReview) }
    static var eveningTime: Int { d.integer(forKey: SettingKey.eveningTime) }

    static var claudeModel: String { d.string(forKey: SettingKey.claudeModel) ?? Defaults.claudeModel }
    static var geminiModel: String { d.string(forKey: SettingKey.geminiModel) ?? Defaults.geminiModel }

    static func mealTime(_ meal: MealType) -> Int {
        switch meal {
        case .breakfast: d.integer(forKey: SettingKey.breakfastTime)
        case .lunch: d.integer(forKey: SettingKey.lunchTime)
        case .dinner: d.integer(forKey: SettingKey.dinnerTime)
        case .snack: 15 * 60 + 30
        case .lateNight: 22 * 60
        }
    }

    /// 依個人資料算出建議目標並寫入設定
    static func applyGoals(_ result: GoalCalculator.Result, includeWater: Bool = true) {
        d.set(result.calories, forKey: SettingKey.calorieGoal)
        d.set(result.protein, forKey: SettingKey.proteinGoal)
        d.set(result.carbs, forKey: SettingKey.carbsGoal)
        d.set(result.fat, forKey: SettingKey.fatGoal)
        if includeWater { d.set(result.water, forKey: SettingKey.waterGoal) }
    }

    /// 依個人資料、選的目標與飲食方式計算
    static func currentProfileGoals() -> GoalCalculator.Result {
        GoalCalculator.calculate(
            sex: GoalCalculator.Sex(rawValue: d.string(forKey: SettingKey.sex) ?? "") ?? .female,
            age: d.integer(forKey: SettingKey.age),
            heightCM: d.double(forKey: SettingKey.heightCM),
            weightKG: d.double(forKey: SettingKey.weightKG),
            activityLevel: d.integer(forKey: SettingKey.activityLevel),
            goal: effectiveGoal,
            asianAdjust: d.bool(forKey: SettingKey.asianAdjust),
            macroStyle: macroStyle,
            useDRIEnergy: d.bool(forKey: SettingKey.useDRIEnergy)
        )
    }

    /// 開啟「自動計算卡路里」時，個人資料一改就重新計算熱量與三大營養素（喝水目標由使用者自己設定）
    static func applyAutoGoalsIfNeeded() {
        guard d.bool(forKey: SettingKey.autoGoals) else { return }
        applyGoals(currentProfileGoals(), includeWater: false)
    }
}

/// 每日目標計算
///
/// - 基礎代謝：Mifflin-St Jeor 公式，可選擇乘上 0.95 的亞洲人校正
/// - 每日消耗 = 基礎代謝 × 活動係數；也可改用國健署「國人膳食營養素參考攝取量」依年齡、性別、活動量查表
/// - 減重：每天少吃 TDEE 的 20%（最多 500 kcal），且不低於 1200（女）/ 1500（男）
/// - 三大營養素：「國健署建議」時蛋白質依活動量 1.0–2.0 g/kg 但不低於國健署建議量（減重再加 0.2），
///   至少佔總熱量 15%；脂肪佔 28%（不低於 20%），並保留每天至少 130 g 醣類，其餘為碳水；
///   其他飲食方式依固定比例分配
/// - 喝水為體重 × 30 ml
enum GoalCalculator {
    enum Sex: String, CaseIterable, Identifiable {
        case female, male
        var id: String { rawValue }
        var title: String { self == .male ? "男性" : "女性" }
    }

    enum Goal: String, CaseIterable, Identifiable {
        case lose, maintain, gain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lose: "減脂"
            case .maintain: "維持"
            case .gain: "增肌"
            }
        }

        var detail: String {
            switch self {
            case .lose: "每天少吃約 20%（最多 500 大卡）"
            case .maintain: "吃進去的等於消耗的"
            case .gain: "每天多吃 300 大卡，搭配重訓"
            }
        }
    }

    /// 飲食方式：三大營養素怎麼分配
    enum MacroStyle: String, CaseIterable, Identifiable {
        case recommended, balanced, highProtein, muscle, lowCarb
        var id: String { rawValue }

        var title: String {
            switch self {
            case .recommended: "國健署建議"
            case .balanced: "均衡"
            case .highProtein: "高蛋白"
            case .muscle: "增肌"
            case .lowCarb: "低碳"
            }
        }

        var detail: String {
            switch self {
            case .recommended: "依國人膳食營養素參考攝取量：蛋白質依體重、醣類至少 130 g、脂肪 20–30%"
            case .balanced: "一般家常飲食"
            case .highProtein: "減脂時比較不會掉肌肉"
            case .muscle: "搭配重訓，碳水多一點"
            case .lowCarb: "少吃澱粉，脂肪多一點（醣類低於國健署建議的每天 130 g）"
            }
        }

        /// 蛋白質、碳水、脂肪佔總熱量的比例；「建議」依體重計算，沒有固定比例
        var split: (protein: Double, carbs: Double, fat: Double)? {
            switch self {
            case .recommended: nil
            case .balanced: (0.20, 0.50, 0.30)
            case .highProtein: (0.30, 0.40, 0.30)
            case .muscle: (0.30, 0.45, 0.25)
            case .lowCarb: (0.30, 0.20, 0.50)
            }
        }
    }

    static let activityTitles = [
        "久坐（幾乎不運動）",
        "輕度（每週運動 1–3 天）",
        "中度（每週運動 3–5 天）",
        "高度（每週運動 6–7 天）",
    ]
    private static let activityFactors = [1.2, 1.375, 1.55, 1.725]
    private static let proteinPerKg = [1.0, 1.2, 1.5, 2.0]

    struct Result {
        var bmr: Double
        var tdee: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var water: Double
        /// 國健署建議熱量（依年齡、性別、活動量查表）與採用的活動強度
        var driEnergy: Double?
        var driActivity: String?
        /// 國健署膳食纖維足夠攝取量（公克）
        var fiber: Double?
    }

    static func calculate(sex: Sex, age: Int, heightCM: Double, weightKG: Double,
                          activityLevel: Int, goal: Goal, asianAdjust: Bool,
                          macroStyle: MacroStyle = .recommended, useDRIEnergy: Bool = false) -> Result {
        let level = min(max(activityLevel, 0), activityFactors.count - 1)
        var bmr = 10 * weightKG + 6.25 * heightCM - 5 * Double(age) + (sex == .male ? 5 : -161)
        if asianAdjust { bmr *= 0.95 }
        let dri = TaiwanDRI.energy(sex: sex, age: age, activityLevel: level)
        let tdee = useDRIEnergy ? dri?.kcal ?? bmr * activityFactors[level] : bmr * activityFactors[level]

        var calories: Double
        switch goal {
        case .lose: calories = tdee - min(500, tdee * 0.2)
        case .maintain: calories = tdee
        case .gain: calories = tdee + 300
        }
        calories = max(calories, sex == .male ? 1500 : 1200)
        calories = (calories / 50).rounded() * 50

        let protein: Double
        let fat: Double
        let carbs: Double
        if let split = macroStyle.split {
            protein = (calories * split.protein / 4).rounded()
            carbs = (calories * split.carbs / 4).rounded()
            fat = (calories * split.fat / 9).rounded()
        } else {
            // 國健署：蛋白質每公斤至少 1.1 g（71 歲以上 1.2 g）、醣類至少 130 g、脂質佔 20–30%
            let perKg = max(proteinPerKg[level], TaiwanDRI.proteinPerKg(sex: sex, age: age)) + (goal == .lose ? 0.2 : 0)
            protein = max(weightKG * perKg, calories * 0.15 / 4).rounded()
            let lowestFat = calories * TaiwanDRI.fatRange.lowerBound / 9
            let roomForCarbs = (calories - protein * 4 - TaiwanDRI.carbsMinimum * 4) / 9
            fat = max(lowestFat, min(calories * 0.28 / 9, roomForCarbs)).rounded()
            carbs = max(0, (calories - protein * 4 - fat * 9) / 4).rounded()
        }
        let water = max(1500, (weightKG * 30 / 100).rounded() * 100)

        return Result(bmr: bmr, tdee: tdee, calories: calories, protein: protein,
                      carbs: carbs, fat: fat, water: water, driEnergy: dri?.kcal, driActivity: dri?.activity,
                      fiber: TaiwanDRI.fiber(sex: sex, age: age, activityLevel: level))
    }
}
