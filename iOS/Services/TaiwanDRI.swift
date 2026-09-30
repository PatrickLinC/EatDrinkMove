import Foundation

/// 衛生福利部國民健康署「國人膳食營養素參考攝取量」第八版總表（民國 111 年）
///
/// 只收 10 歲以上、App 會用到的項目。熱量依「低、稍低、適度、高」四種生活活動強度；
/// 蛋白質總表的克數是參考體重 × 每公斤建議量（成人 1.1 g、71 歲以上 1.2 g），所以依使用者自己的體重換算。
enum TaiwanDRI {
    /// 醣類（碳水化合物）建議量 RDA
    static let carbsMinimum: Double = 130
    /// 醣類佔總熱量 50–65%、脂質 20–30%、飽和脂肪 < 10%
    static let carbsRange = 0.50...0.65
    static let fatRange = 0.20...0.30
    /// 鈉的慢性疾病風險降低攝取量 CDRR（10 歲以上）
    static let sodiumLimit: Double = 2300

    private struct Row {
        let ages: ClosedRange<Int>
        /// 熱量（大卡），依活動強度 低、稍低、適度、高；沒有的強度是 nil
        let male: [Double?]
        let female: [Double?]
        let fiberMale: [Double?]
        let fiberFemale: [Double?]
        /// 蛋白質每公斤體重幾公克（總表克數 ÷ 參考體重）：男、女
        let proteinPerKg: (male: Double, female: Double)
    }

    private static let rows: [Row] = [
        Row(ages: 10...12, male: [nil, 2050, 2350, nil], female: [nil, 1950, 2250, nil],
            fiberMale: [nil, 29, 33, nil], fiberFemale: [nil, 27, 32, nil], proteinPerKg: (1.45, 1.28)),
        Row(ages: 13...15, male: [nil, 2400, 2800, nil], female: [nil, 2050, 2350, nil],
            fiberMale: [nil, 34, 39, nil], fiberFemale: [nil, 29, 33, nil], proteinPerKg: (1.27, 1.22)),
        Row(ages: 16...18, male: [2150, 2500, 2900, 3350], female: [1650, 1900, 2250, 2550],
            fiberMale: [30, 35, 41, 47], fiberFemale: [23, 27, 32, 36], proteinPerKg: (1.21, 1.08)),
        Row(ages: 19...30, male: [1850, 2150, 2400, 2700], female: [1450, 1650, 1900, 2100],
            fiberMale: [26, 30, 34, 38], fiberFemale: [20, 23, 27, 29], proteinPerKg: (1.1, 1.1)),
        Row(ages: 31...50, male: [1800, 2100, 2400, 2650], female: [1450, 1650, 1900, 2100],
            fiberMale: [25, 29, 34, 37], fiberFemale: [20, 23, 27, 29], proteinPerKg: (1.1, 1.1)),
        Row(ages: 51...70, male: [1700, 1950, 2250, 2500], female: [1400, 1600, 1800, 2000],
            fiberMale: [24, 27, 32, 35], fiberFemale: [20, 22, 25, 28], proteinPerKg: (1.1, 1.1)),
        Row(ages: 71...150, male: [1650, 1900, 2150, nil], female: [1300, 1500, 1700, nil],
            fiberMale: [23, 27, 30, nil], fiberFemale: [18, 21, 24, nil], proteinPerKg: (1.2, 1.2)),
    ]

    static let activityTitles = ["低", "稍低", "適度", "高"]

    private static func row(age: Int) -> Row? {
        rows.first { $0.ages.contains(age) }
    }

    /// App 的活動量（久坐、輕度、中度、高度）對到總表的活動強度；該年齡沒有的強度就用最接近的
    private static func pick(_ values: [Double?], activityLevel: Int) -> (value: Double, level: Int)? {
        let wanted = min(max(activityLevel, 0), 3)
        let order = [wanted] + (0..<4).filter { $0 != wanted }.sorted { abs($0 - wanted) < abs($1 - wanted) }
        for level in order {
            if let value = values[level] { return (value, level) }
        }
        return nil
    }

    /// 建議熱量（大卡）與實際採用的活動強度名稱
    static func energy(sex: GoalCalculator.Sex, age: Int, activityLevel: Int) -> (kcal: Double, activity: String)? {
        guard let row = row(age: age),
              let picked = pick(sex == .male ? row.male : row.female, activityLevel: activityLevel) else { return nil }
        return (picked.value, activityTitles[picked.level])
    }

    /// 膳食纖維足夠攝取量 AI（公克）
    static func fiber(sex: GoalCalculator.Sex, age: Int, activityLevel: Int) -> Double? {
        guard let row = row(age: age) else { return nil }
        return pick(sex == .male ? row.fiberMale : row.fiberFemale, activityLevel: activityLevel)?.value
    }

    /// 蛋白質建議量：每公斤體重幾公克
    static func proteinPerKg(sex: GoalCalculator.Sex, age: Int) -> Double {
        guard let row = row(age: age) else { return 1.1 }
        return sex == .male ? row.proteinPerKg.male : row.proteinPerKg.female
    }
}
