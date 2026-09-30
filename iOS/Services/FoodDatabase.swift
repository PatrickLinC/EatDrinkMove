import Foundation

/// 台灣食品營養成分資料庫的一筆食物（數值為每 100 公克可食部分）
struct TWFood: Identifiable, Hashable {
    let id: Int
    let name: String
    let alias: String
    let category: String
    let detail: String
    let per100: Nutrition100
    let fiber: Double
    /// 每單位（例如一顆、一片）的重量
    let unitGrams: Double?
    fileprivate let nameKey: String
    fileprivate let aliasKey: String
}

/// 內建的離線食物資料庫。
/// 資料來源：衛生福利部食品藥物管理署「食品營養成分資料集」
/// （政府資料開放平臺，依政府資料開放授權條款第 1 版使用）
final class FoodDatabase {
    static let shared = FoodDatabase()

    private struct Raw: Decodable {
        let n, a, c, d: String
        let k, p, f, cb, fi, na, s: Double
        let u: Double?
    }

    /// 第一次用到時載入（static let 保證只載入一次、多執行緒安全）
    let foods: [TWFood]

    private init() {
        foods = Self.load()
    }

    private static func load() -> [TWFood] {
        guard let url = Bundle.main.url(forResource: "tw_food_nutrition", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raws = try? JSONDecoder().decode([Raw].self, from: data) else {
            print("找不到內建的營養資料庫")
            return []
        }
        return raws.enumerated().map { index, raw in
            TWFood(
                id: index, name: raw.n, alias: raw.a, category: raw.c, detail: raw.d,
                per100: Nutrition100(kcal: raw.k, protein: raw.p, carbs: raw.cb, fat: raw.f,
                                     sodium: raw.na, sugar: raw.s),
                fiber: raw.fi, unitGrams: raw.u,
                nameKey: FuzzyMatcher.normalize(raw.n), aliasKey: FuzzyMatcher.normalize(raw.a)
            )
        }
    }

    /// 模糊搜尋（名稱優先、俗名其次），回傳（食物, 分數）；查詢裡有品牌時這裡不回傳（交給品牌資料庫）
    func searchScored(_ query: String, limit: Int = 40) -> [(food: TWFood, score: Int)] {
        let (brand, rest) = FuzzyMatcher.splitBrand(query)
        guard brand == nil, !rest.isEmpty else { return [] }
        let variants = FuzzyMatcher.variants(rest)
        var matches: [(food: TWFood, score: Int)] = []
        for food in foods {
            let byName = FuzzyMatcher.bestScore(variants: variants, in: food.nameKey)
            let byAlias = food.aliasKey.isEmpty ? nil : FuzzyMatcher.bestScore(variants: variants, in: food.aliasKey).map { $0 - 30 }
            if let score = [byName, byAlias].compactMap({ $0 }).max() {
                matches.append((food, score))
            }
        }
        return Array(matches.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.food.name.count < $1.food.name.count
        }.prefix(limit))
    }

    func search(_ query: String, limit: Int = 30) -> [TWFood] {
        searchScored(query, limit: limit).map(\.food)
    }

    /// 給 AI 辨識結果用：名稱完全相同，或資料庫名稱以它開頭且只多幾個字（例如「茶葉蛋」→「茶葉蛋平均值」）
    func closestMatch(for name: String) -> TWFood? {
        let q = Self.normalize(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return nil }
        if let exact = foods.first(where: { Self.normalize($0.name) == q }) { return exact }
        return foods
            .filter { food in
                let n = Self.normalize(food.name)
                return n.hasPrefix(q) && n.count <= q.count + 5
            }
            .min { $0.name.count < $1.name.count }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "臺", with: "台")
    }
}

/// 用條碼查詢包裝食品（Open Food Facts 開放資料庫）
enum ProductLookup {
    struct Product {
        let name: String
        let brand: String
        let per100: Nutrition100
        let servingGrams: Double?
    }

    enum LookupError: LocalizedError {
        case noNutrition(String)
        var errorDescription: String? {
            switch self {
            case .noNutrition(let name): "找到「\(name)」，但沒有營養資料。可以拍包裝上的營養標示讓 AI 讀取。"
            }
        }
    }

    static func lookup(barcode: String) async throws -> Product? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,product_name_zh,brands,nutriments,serving_quantity")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("EatDrinkMove/1.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["status"] as? Int == 1,
              let product = json["product"] as? [String: Any] else { return nil }

        func number(_ value: Any?) -> Double? {
            if let value = value as? Double { return value }
            if let value = value as? Int { return Double(value) }
            if let value = value as? String { return Double(value) }
            return nil
        }
        func text(_ value: Any?) -> String? {
            guard let value = value as? String, !value.isEmpty else { return nil }
            return value
        }

        let name = text(product["product_name_zh"]) ?? text(product["product_name"]) ?? "條碼 \(digits)"
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        var kcal = number(nutriments["energy-kcal_100g"])
        if kcal == nil, let kilojoules = number(nutriments["energy_100g"]) { kcal = kilojoules / 4.184 }
        guard let kcal else { throw LookupError.noNutrition(name) }

        return Product(
            name: name,
            brand: text(product["brands"]) ?? "",
            per100: Nutrition100(
                kcal: kcal,
                protein: number(nutriments["proteins_100g"]) ?? 0,
                carbs: number(nutriments["carbohydrates_100g"]) ?? 0,
                fat: number(nutriments["fat_100g"]) ?? 0,
                sodium: (number(nutriments["sodium_100g"]) ?? 0) * 1000, // 公克 → 毫克
                sugar: number(nutriments["sugars_100g"]) ?? 0
            ),
            servingGrams: number(product["serving_quantity"])
        )
    }
}
