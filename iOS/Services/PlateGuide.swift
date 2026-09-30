import Foundation
import SwiftUI

// MARK: - 我的餐盤（國健署每日飲食指南）

/// 最常吃不夠的五類：蔬菜、水果、豆魚蛋肉、乳品、堅果種子（全穀雜糧通常不會少，不列）
enum PlateGroup: String, CaseIterable, Identifiable {
    case vegetables, fruit, protein, dairy, nuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegetables: "蔬菜"
        case .fruit: "水果"
        case .protein: "豆魚蛋肉"
        case .dairy: "乳品"
        case .nuts: "堅果種子"
        }
    }

    var unit: String { self == .dairy ? "杯" : "份" }

    /// 一份大概多少
    var hint: String {
        switch self {
        case .vegetables: "一份約煮熟半碗"
        case .fruit: "一份約一個拳頭大"
        case .protein: "一份約一顆蛋、掌心大的肉或魚"
        case .dairy: "一杯約 240 ml 鮮奶"
        case .nuts: "一份約一湯匙"
        }
    }

    var art: PixelArt {
        switch self {
        case .vegetables: .campGarden
        case .fruit: .festivalPomelo
        case .protein: .companionEgg
        case .dairy: .cupFull
        case .nuts: .plateNut
        }
    }

    var color: Color {
        switch self {
        case .vegetables: .move
        case .fruit: .calorie
        case .protein: .protein
        case .dairy: .water
        case .nuts: .brand
        }
    }

    /// 豆魚蛋肉是從蛋白質公克數推算的，不用手動加
    var isManual: Bool { self != .protein }

    // MARK: 每日建議份數

    /// 每日飲食指南的熱量層級（大卡）與各類份數
    private static let levels: [Double] = [1200, 1500, 1800, 2000, 2200, 2500, 2700]
    private var perLevel: [Double] {
        switch self {
        case .vegetables: [3, 3, 3, 4, 4, 5, 5]
        case .fruit: [2, 2, 2, 3, 3.5, 4, 4]
        case .protein: [3, 4, 5, 6, 6, 7, 8]
        case .dairy: [1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 2]
        case .nuts: [1, 1, 1, 1, 1, 1, 1]
        }
    }

    /// 依每日熱量目標取最接近的層級
    func target(calories: Double) -> Double {
        let index = Self.levels.indices.min { abs(Self.levels[$0] - calories) < abs(Self.levels[$1] - calories) } ?? 2
        return perLevel[index]
    }

    // MARK: 從紀錄估算

    /// 名字裡有這些字就算一份（份量有 ×½、×1.5 會跟著乘）
    private var keywords: [String] {
        switch self {
        case .vegetables:
            ["青菜", "蔬菜", "沙拉", "高麗菜", "花椰菜", "青花菜", "菠菜", "地瓜葉", "空心菜", "小白菜", "大白菜", "油菜", "A菜",
             "菇", "木耳", "竹筍", "筍", "茄子", "青椒", "甜椒", "紅蘿蔔", "胡蘿蔔", "洋蔥", "豆芽", "四季豆", "秋葵", "苦瓜", "絲瓜",
             "冬瓜", "海帶", "小黃瓜", "蘆筍", "玉米筍", "番茄炒", "韭菜", "芥藍", "高湯青菜", "燙菜", "便當", "自助餐", "蔬食"]
        case .fruit:
            ["水果", "蘋果", "香蕉", "芭樂", "橘子", "柳丁", "柳橙", "葡萄", "西瓜", "木瓜", "鳳梨", "芒果", "奇異果", "草莓", "藍莓",
             "梨", "水蜜桃", "蓮霧", "火龍果", "柚子", "文旦", "哈密瓜", "櫻桃", "小番茄", "聖女番茄", "荔枝", "龍眼", "釋迦", "百香果"]
        case .dairy:
            ["鮮奶", "牛奶", "優格", "優酪", "起司", "乳酪", "奶粉", "拿鐵"]
        case .nuts:
            ["堅果", "杏仁", "腰果", "核桃", "開心果", "夏威夷豆", "花生", "芝麻", "南瓜子", "葵瓜子", "松子"]
        case .protein:
            []
        }
    }

    /// 名字有這些字就不算（果汁、果醬、水果茶不算水果；奶茶、奶精不算乳品）
    private var excludes: [String] {
        switch self {
        case .fruit: ["汁", "醬", "凍", "糖", "茶", "蛋糕", "派", "冰淇淋", "口味"]
        case .dairy: ["奶茶", "奶精", "冰淇淋"]
        case .nuts: ["醬", "糖", "油"]
        default: []
        }
    }

    /// 一樣食物算幾份：拿鐵算半杯乳品，其他符合的算一份
    func servings(of food: FoodEntry) -> Double {
        guard isManual, keywords.contains(where: food.name.contains),
              !excludes.contains(where: food.name.contains) else { return 0 }
        let base = self == .dairy && food.name.contains("拿鐵") ? 0.5 : 1
        return base * Self.portionFactor(food.portion)
    }

    /// 份量上的「×½」「×1.5」
    static func portionFactor(_ portion: String) -> Double {
        guard let range = portion.range(of: "×") else { return 1 }
        let text = portion[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("½") { return 0.5 }
        return Double(text.prefix { "0123456789.".contains($0) }) ?? 1
    }
}

/// 某天的餐盤：自動估算＋手動補上
@MainActor
enum PlateLog {
    private static let key = "plateManual"

    /// 手動補的份數 [dayKey: [group: 份數]]
    private static var manual: [String: [String: Double]] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]]) ?? [:] }
        set {
            // 只留最近 60 天
            let keep = Set((0..<60).map { Date.now.adding(days: -$0).dayKey })
            UserDefaults.standard.set(newValue.filter { keep.contains($0.key) }, forKey: key)
        }
    }

    static func manual(_ group: PlateGroup, on day: Date) -> Double { manual[day.dayKey]?[group.rawValue] ?? 0 }

    static func add(_ amount: Double, to group: PlateGroup, on day: Date) {
        var all = manual
        var today = all[day.dayKey] ?? [:]
        today[group.rawValue] = max(0, (today[group.rawValue] ?? 0) + amount)
        all[day.dayKey] = today
        manual = all
    }

    /// 這一天各類吃了幾份，以及算進去的食物
    static func summary(foods: [FoodEntry], day: Date) -> [PlateGroup: (servings: Double, sources: [String])] {
        var result: [PlateGroup: (Double, [String])] = [:]
        for group in PlateGroup.allCases {
            if group == .protein {
                // 一份豆魚蛋肉約 7 公克蛋白質（主食、乳品也有一點，所以是「約」）
                result[group] = ((foods.reduce(0) { $0 + $1.protein } / 7 * 2).rounded() / 2, [])
                continue
            }
            let counted = foods.filter { group.servings(of: $0) > 0 }
            let auto = counted.reduce(0) { $0 + group.servings(of: $1) }
            result[group] = (auto + manual(group, on: day), counted.map(\.name))
        }
        return result
    }
}
