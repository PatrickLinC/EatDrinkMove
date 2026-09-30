import FoundationModels
import UIKit
import Vision

/// iPhone 內建的 Apple Intelligence 模型（iOS 27 起可以看圖）：
/// 免費、不用金鑰、不用網路，照片不會離開手機。
///
/// 手機上的模型比較小，所以分工：模型負責認出食物和估計重量，
/// 營養數值能在台灣食品營養資料庫找到的就用資料庫計算，找不到才用模型的估計。
enum OnDeviceFoodAnalyzer {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可以使用 ✓"
        case .unavailable(.deviceNotEligible):
            return "這支 iPhone 不支援 Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "請到 iPhone「設定 › Apple Intelligence 與 Siri」開啟"
        case .unavailable(.modelNotReady):
            return "模型還在下載，請稍後再試"
        case .unavailable:
            return "目前無法使用"
        @unknown default:
            return "目前無法使用"
        }
    }

    /// 手機上的模型只有約 4K token 的空間，指示要精簡
    private static let instructions = """
    你是台灣的營養師。找出照片或描述中的每一樣食物和飲料，用繁體中文、台灣常見說法命名，\
    估計重量與整份的營養。便當請拆成主食、主菜、配菜。使用者的補充說明優先。看不到食物時 items 留空。
    """

    static func analyze(image: UIImage?, text: String) async throws -> FoodAnalysis {
        let session = LanguageModelSession(instructions: instructions)
        let response: LanguageModelSession.Response<OnDeviceMeal>
        if let image {
            // 照片越大越佔空間，縮到 768px 就夠辨識
            let small = image.resized(maxDimension: 768)
            response = try await session.respond(generating: OnDeviceMeal.self) {
                text
                Attachment(small)
            }
        } else {
            response = try await session.respond(to: text, generating: OnDeviceMeal.self)
        }

        let meal = response.content
        var usedDatabase = false
        let items = meal.items.map { food -> FoodAnalysis.Item in
            let portion = food.grams > 0 ? "\(food.portion)（約 \(food.grams.rounded0) g）" : food.portion
            if food.grams > 0, let match = FoodDatabase.shared.closestMatch(for: food.name) {
                usedDatabase = true
                let n = match.per100.scaled(grams: food.grams)
                return FoodAnalysis.Item(name: food.name, emoji: food.emoji, portion: portion,
                                         calories: n.kcal, protein: n.protein, carbs: n.carbs,
                                         fat: n.fat, sodium: n.sodium, sugar: n.sugar)
            }
            return FoodAnalysis.Item(name: food.name, emoji: food.emoji, portion: portion,
                                     calories: max(food.calories, 0), protein: max(food.protein, 0),
                                     carbs: max(food.carbs, 0), fat: max(food.fat, 0),
                                     sodium: max(food.sodium, 0), sugar: max(food.sugar, 0))
        }

        let confidence = ["high", "medium", "low"].contains(meal.confidence.lowercased())
            ? meal.confidence.lowercased() : "medium"
        let notes = usedDatabase ? "\(meal.notes) 營養數值參考台灣食品營養資料庫。" : meal.notes
        return FoodAnalysis(items: items, confidence: confidence, notes: notes)
    }

    // MARK: - AI 健康洞察

    static func insight(summary: String) async throws -> String {
        let session = LanguageModelSession(instructions: FoodAnalyzer.insightPrompt)
        let response = try await session.respond(to: summary)
        return response.content
    }

    // MARK: - AI 小夥伴

    static func chat(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt).content
    }

    // MARK: - 營養標示

    /// 先用 iPhone 內建的文字辨識把標示上的字讀出來，再請 Apple AI 整理。
    /// 比直接看圖準，也比較省手機模型的空間。讀標示時不會用資料庫的數字覆蓋。
    static func readLabel(image: UIImage) async throws -> NutritionLabel {
        let text = try await recognizeText(in: image)
        guard text.count >= 10 else { throw FoodAnalyzerError.noText }

        let session = LanguageModelSession(instructions: "你負責整理台灣包裝食品的「營養標示」。\n" + FoodAnalyzer.labelRules)
        let response = try await session.respond(
            to: "以下是用手機從營養標示讀出來的文字，請整理成每份的數值：\n\(text)",
            generating: OnDeviceLabel.self
        )
        let label = response.content
        return NutritionLabel(
            productName: label.productName.isEmpty ? "包裝食品" : label.productName,
            emoji: label.emoji,
            servingSize: max(label.servingSize, 0),
            servingUnit: label.servingUnit,
            servingsPerPackage: max(label.servingsPerPackage, 1),
            calories: max(label.calories, 0),
            protein: max(label.protein, 0),
            fat: max(label.fat, 0),
            carbs: max(label.carbs, 0),
            sugar: max(label.sugar, 0),
            sodium: max(label.sodium, 0)
        )
    }

    /// Vision 文字辨識（繁體中文 + 英文），由上到下一行一行排好
    private static func recognizeText(in image: UIImage) async throws -> String {
        let upright = image.resized(maxDimension: 2000) // 轉正方向，太大的照片縮小
        guard let cgImage = upright.cgImage else { throw FoodAnalyzerError.noText }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

@Generable
struct OnDeviceLabel {
    @Guide(description: "商品名稱，看不到就填「包裝食品」")
    var productName: String

    @Guide(description: "一個代表這個商品的 emoji")
    var emoji: String

    @Guide(description: "每一份量的數字")
    var servingSize: Double

    @Guide(description: "每一份量的單位，g 或 ml")
    var servingUnit: String

    @Guide(description: "本包裝含幾份，沒寫就填 1")
    var servingsPerPackage: Double

    @Guide(description: "每份熱量（大卡）")
    var calories: Double

    @Guide(description: "每份蛋白質（公克）")
    var protein: Double

    @Guide(description: "每份脂肪（公克）")
    var fat: Double

    @Guide(description: "每份碳水化合物（公克）")
    var carbs: Double

    @Guide(description: "每份糖（公克）")
    var sugar: Double

    @Guide(description: "每份鈉（毫克）")
    var sodium: Double
}

@Generable
struct OnDeviceMeal {
    @Guide(description: "照片或描述中的每一樣食物或飲料")
    var items: [OnDeviceFood]

    @Guide(description: "辨識把握度，只能是 high、medium 或 low")
    var confidence: String

    @Guide(description: "一句繁體中文，說明估算依據或給一個小建議")
    var notes: String
}

@Generable
struct OnDeviceFood {
    @Guide(description: "食物名稱，繁體中文、台灣常見說法，例如：白飯、滷雞腿、燙青菜")
    var name: String

    @Guide(description: "一個代表這項食物的 emoji")
    var emoji: String

    @Guide(description: "份量描述，例如：1 碗、半個、1 杯")
    var portion: String

    @Guide(description: "估計重量（公克）")
    var grams: Double

    @Guide(description: "整份的熱量（大卡）")
    var calories: Double

    @Guide(description: "整份的蛋白質（公克）")
    var protein: Double

    @Guide(description: "整份的碳水化合物（公克）")
    var carbs: Double

    @Guide(description: "整份的脂肪（公克）")
    var fat: Double

    @Guide(description: "整份的鈉（毫克）")
    var sodium: Double

    @Guide(description: "整份的糖（公克）")
    var sugar: Double
}
