import Foundation
import SwiftData

/// 紀錄的來源，方便日後分析「哪種記錄方式最常用」
enum EntrySource: String, Codable {
    case app, manual, ai, database, barcode, label, quick, watch, siri, notification
}

@Model
final class FoodEntry {
    var id: UUID = UUID()
    var name: String = ""
    var portion: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    /// 毫克
    var sodium: Double = 0
    /// 公克
    var sugar: Double = 0
    var mealTypeRaw: String = MealType.snack.rawValue
    var date: Date = Date.now
    var sourceRaw: String = EntrySource.manual.rawValue
    var healthSynced: Bool = false
    /// 沒有照片貼紙時顯示的 emoji 貼紙
    var emoji: String = ""
    /// 照片縮圖
    @Attribute(.externalStorage) var photoData: Data?
    /// 從照片剪下來的去背貼紙（PNG）
    @Attribute(.externalStorage) var stickerData: Data?

    init(draft: FoodDraft, mealType: MealType, date: Date, photoData: Data? = nil, stickerData: Data? = nil) {
        self.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emoji = draft.emoji.isEmpty ? FoodEmoji.guess(name: draft.name) : draft.emoji
        self.stickerData = stickerData
        self.portion = draft.portion
        self.calories = draft.calories
        self.protein = draft.protein
        self.carbs = draft.carbs
        self.fat = draft.fat
        self.sodium = draft.sodium
        self.sugar = draft.sugar
        self.mealTypeRaw = mealType.rawValue
        self.date = date
        self.sourceRaw = draft.source.rawValue
        self.photoData = photoData
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// 蛋白質(g) × 20 ≥ 熱量，就算是「高蛋白」的好選擇
    var isHighProtein: Bool { protein >= 5 && protein * 20 >= calories }

    var quickFood: QuickFood {
        QuickFood(name: name, emoji: emoji, portion: portion, calories: calories, protein: protein,
                  carbs: carbs, fat: fat, sodium: sodium, sugar: sugar)
    }
}

@Model
final class WaterEntry {
    var id: UUID = UUID()
    /// 毫升
    var amount: Double = 0
    var date: Date = Date.now
    var sourceRaw: String = EntrySource.app.rawValue
    var healthSynced: Bool = false

    init(amount: Double, date: Date, source: EntrySource) {
        self.amount = amount
        self.date = date
        self.sourceRaw = source.rawValue
    }
}

/// 手動記錄的運動（Apple Watch 的運動會直接從「健康」讀取）
@Model
final class ExerciseEntry {
    var id: UUID = UUID()
    var name: String = ""
    var minutes: Double = 0
    var calories: Double = 0
    var date: Date = Date.now

    init(name: String, minutes: Double, calories: Double, date: Date) {
        self.name = name
        self.minutes = minutes
        self.calories = calories
        self.date = date
    }
}

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var kg: Double = 0
    var date: Date = Date.now
    var healthSynced: Bool = false

    init(kg: Double, date: Date) {
        self.kg = kg
        self.date = date
    }
}

/// 還沒存檔前、可以編輯的一項食物
struct FoodDraft: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var portion: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var sodium: Double = 0
    var sugar: Double = 0
    var source: EntrySource = .manual
    var emoji: String = ""

    mutating func scale(by factor: Double) {
        calories *= factor
        protein *= factor
        carbs *= factor
        fat *= factor
        sodium *= factor
        sugar *= factor
        let label = factor == 0.5 ? "×½" : "×\(factor.formatted())"
        portion = portion.isEmpty ? label : "\(portion) \(label)"
    }
}

extension FoodDraft {
    init(quick food: QuickFood, source: EntrySource = .quick) {
        self.init(name: food.name, portion: food.portion, calories: food.calories, protein: food.protein,
                  carbs: food.carbs, fat: food.fat, sodium: food.sodium, sugar: food.sugar,
                  source: source, emoji: food.emoji)
    }

    init(entry: FoodEntry) {
        self.init(name: entry.name, portion: entry.portion, calories: entry.calories, protein: entry.protein,
                  carbs: entry.carbs, fat: entry.fat, sodium: entry.sodium, sugar: entry.sugar,
                  source: EntrySource(rawValue: entry.sourceRaw) ?? .manual, emoji: entry.emoji)
    }

    init(aiItem item: FoodAnalysis.Item) {
        self.init(name: item.name, portion: item.portion, calories: item.calories, protein: item.protein,
                  carbs: item.carbs, fat: item.fat, sodium: item.sodium, sugar: item.sugar,
                  source: .ai, emoji: item.emoji)
    }
}

/// 每 100 公克的營養素
struct Nutrition100: Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// 毫克
    var sodium: Double
    var sugar: Double

    func scaled(grams: Double) -> Nutrition100 {
        let f = grams / 100
        return Nutrition100(kcal: kcal * f, protein: protein * f, carbs: carbs * f,
                            fat: fat * f, sodium: sodium * f, sugar: sugar * f)
    }
}
