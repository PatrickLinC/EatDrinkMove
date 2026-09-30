import Foundation

// MARK: - 模糊比對

/// 搜尋用的模糊比對：完全相同 > 開頭相同 > 包含 > 每個字依序出現 > 大部分兩字詞相同
enum FuzzyMatcher {
    /// 品牌別名（左邊任一個都代表右邊的品牌）
    static let brandAliases: [(aliases: [String], brand: String)] = [
        (["7-11", "711", "7/11", "7–11", "小七", "seven", "7eleven", "統一超商"], "7-11"),
        (["全家", "familymart", "fami"], "全家"),
        (["萊爾富", "hilife", "hi-life"], "萊爾富"),
        (["麥當勞", "麥當當", "mcd", "mcdonald", "m記"], "麥當勞"),
        (["肯德基", "kfc"], "肯德基"),
        (["摩斯", "mos"], "摩斯"),
        (["漢堡王", "burgerking", "bk"], "漢堡王"),
        (["星巴克", "starbucks", "sbux"], "星巴克"),
        (["路易莎", "louisa"], "路易莎"),
        (["五十嵐", "50嵐", "50lan"], "50嵐"),
        (["清心", "清心福全"], "清心福全"),
        (["麻古", "macu"], "麻古茶坊"),
        (["迷客夏", "milksha"], "迷客夏"),
        (["coco", "都可"], "CoCo都可"),
        (["可不可"], "可不可熟成紅茶"),
        (["subway", "潛艇堡"], "Subway"),
        (["必勝客", "pizzahut"], "必勝客"),
        (["達美樂", "dominos"], "達美樂"),
        (["吉野家", "yoshinoya"], "吉野家"),
        (["sukiya", "すき家", "食其家"], "Sukiya"),
        (["八方雲集", "八方"], "八方雲集"),
        (["能量小姐", "missenergy"], "能量小姐"),
        (["misterdonut", "mister donut", "mr donut", "mrdonut"], "Mister Donut"),
        (["qburger", "q burger", "饗樂"], "Q Burger"),
        (["全聯", "pxmart"], "全聯"),
        (["丸龜", "marugame"], "丸龜製麵"),
        (["一風堂", "ippudo"], "一風堂"),
        (["得正"], "得正"),
        (["頂呱呱"], "頂呱呱"),
        (["大苑子"], "大苑子"),
        (["comebuy"], "COMEBUY"),
        (["茶湯會"], "茶湯會"),
        (["五桐號"], "五桐號"),
        (["一沐日"], "一沐日"),
        (["八曜"], "八曜和茶"),
        (["德克士", "dicos"], "德克士"),
        (["拉亞"], "拉亞漢堡"),
        (["三商巧福", "巧福"], "三商巧福"),
        (["ikea", "宜家"], "IKEA"),
    ]

    /// 同義詞：同一組裡的詞互相代換後都會試
    static let synonyms: [[String]] = [
        ["拿鐵", "那堤", "latte"], ["珍奶", "珍珠奶茶"], ["雞胸", "雞胸肉"], ["美式", "美式咖啡"],
        ["飯糰", "御飯糰"], ["地瓜", "番薯"], ["馬鈴薯", "洋芋"], ["起司", "乳酪", "芝士"], ["番茄", "蕃茄"],
        ["花椰菜", "青花菜"], ["豆漿", "豆乳"], ["鮭魚", "三文魚"], ["優格", "優酪乳"], ["奶昔", "冰沙"],
        ["無糖", "0糖"], ["雞塊", "麥克雞塊"], ["蛋塔", "蛋撻"], ["薯條", "大薯", "中薯", "小薯"],
        ["刈包", "割包"], ["滷", "魯"], ["洋芋片", "薯片"], ["泡麵", "速食麵"],
    ]

    /// 事先整理好的同義詞與品牌別名（normalize 要做全形轉半形，很慢，不要每次搜尋都重算）
    private static let synonymKeys: [[String]] = synonyms.map { $0.map(normalize) }
    private static let aliasKeys: [(keys: [String], brand: String)] = brandAliases.map { aliases, brand in
        (aliases.map(normalize).sorted { $0.count > $1.count }, brand)
    }

    static func normalize(_ text: String) -> String {
        let folded = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return folded.lowercased()
            .replacingOccurrences(of: "臺", with: "台")
            .filter { !$0.isWhitespace && !"()（）[]【】「」・,，.。-_/".contains($0) }
    }

    /// 把查詢拆成「品牌」和「剩下的字」，例如「全家 雞胸」→（全家, 雞胸）
    static func splitBrand(_ query: String) -> (brand: String?, rest: String) {
        let normalized = normalize(query)
        for (keys, brand) in aliasKeys {
            for key in keys where normalized.contains(key) {
                return (brand, normalized.replacingOccurrences(of: key, with: ""))
            }
        }
        return (nil, normalized)
    }

    /// 同義詞代換後的所有寫法（含原本的）
    static func variants(_ normalized: String) -> [String] {
        var result = [normalized]
        for keys in synonymKeys {
            for key in keys where normalized.contains(key) {
                for other in keys where other != key {
                    result.append(normalized.replacingOccurrences(of: key, with: other))
                }
            }
        }
        return result
    }

    /// 分數越高越相符；完全對不上回傳 nil。兩邊都要先 normalize
    static func score(_ query: String, in text: String) -> Int? {
        guard !query.isEmpty, !text.isEmpty else { return nil }
        let extra = max(text.count - query.count, 0)
        if text == query { return 1000 }
        if text.hasPrefix(query) { return 900 - min(extra, 80) }
        if let range = text.range(of: query) {
            return 800 - min(text.distance(from: text.startIndex, to: range.lowerBound) * 3 + extra, 150)
        }
        guard query.count >= 2 else { return nil }
        // 每個字依序出現：「紐雞胸」→「紐奧良雞胸肉」
        var gaps = 0, index = text.startIndex, started = false
        var matched = true
        for character in query {
            guard let found = text[index...].firstIndex(of: character) else { matched = false; break }
            if started { gaps += text.distance(from: index, to: found) }
            started = true
            index = text.index(after: found)
        }
        if matched && gaps <= query.count * 3 { return 600 - min(gaps * 15 + extra, 200) }
        // 大部分兩字詞相同（打錯一個字也找得到）
        guard query.count >= 3 else { return nil }
        let characters = Array(query)
        let bigrams = (0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) }
        let hits = bigrams.filter { text.contains($0) }.count
        let ratio = Double(hits) / Double(bigrams.count)
        return ratio >= 0.6 ? Int(300 * ratio) - min(extra, 100) : nil
    }

    /// 試過所有同義詞寫法，取最高分
    static func bestScore(_ query: String, in text: String) -> Int? {
        bestScore(variants: variants(query), in: text)
    }

    /// 同一個查詢要比對很多筆時，先算好 variants 再逐筆比
    static func bestScore(variants: [String], in text: String) -> Int? {
        variants.compactMap { score($0, in: text) }.max()
    }
}

// MARK: - 品牌與常見食品

/// 品牌商品或營養師整理的常見食品（數值是「每份」）
struct BrandFood: Decodable, Identifiable, Hashable {
    let brand: String?
    let name: String
    let kcal: Double
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let sugar: Double?
    let sodium: Double?
    let serving: String?
    let grams: Double?
    let category: String?
    let source: String?
    let barcode: String?

    var id: String { "\(brand ?? "")|\(name)|\(barcode ?? "")" }

    var displayName: String {
        guard let brand, !brand.isEmpty, !name.hasPrefix(brand) else { return name }
        return "\(brand) \(name)"
    }

    /// 品牌官網或政府平台的資料；其他是營養師、網站或網友整理的
    var isOfficial: Bool {
        ["familymart", "starbucks", "mos", "kfc", "taipei", "ntpc", "missenergy", "seven"].contains(source ?? "")
    }

    /// 列表上標示資料從哪來
    var sourceLabel: String {
        if isOfficial { return "官方標示" }
        return source == "openfoodfacts" ? "條碼資料庫" : "網路整理"
    }
}

/// 內建的品牌與常見食品資料（iOS/Resources/brand_foods.json，由 Tools/nutrition 產生；沒有這個檔案時是空的）
final class BrandFoodDatabase {
    static let shared = BrandFoodDatabase()

    let foods: [BrandFood]
    private let keys: [String]
    private let brandKeys: [String]
    private let byBarcode: [String: BrandFood]

    private init() {
        guard let url = Bundle.main.url(forResource: "brand_foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let foods = try? JSONDecoder().decode([BrandFood].self, from: data) else {
            foods = []
            keys = []
            brandKeys = []
            byBarcode = [:]
            return
        }
        self.foods = foods
        keys = foods.map { FuzzyMatcher.normalize($0.name) }
        brandKeys = foods.map { FuzzyMatcher.normalize($0.brand ?? "") }
        byBarcode = Dictionary(foods.compactMap { food in food.barcode.map { ($0, food) } }, uniquingKeysWith: { first, _ in first })
    }

    /// 內建資料裡有這個條碼的商品（不用連網）
    func food(barcode: String) -> BrandFood? {
        byBarcode[barcode.filter(\.isNumber)]
    }

    /// 回傳（食物, 分數），分數越高越前面；「全家」這種只打品牌的查詢會列出該品牌的商品
    func search(_ query: String, limit: Int = 80) -> [(food: BrandFood, score: Int)] {
        let (brand, rest) = FuzzyMatcher.splitBrand(query)
        let brandKey = brand.map(FuzzyMatcher.normalize)
        guard brandKey != nil || !rest.isEmpty else { return [] }

        let variants = FuzzyMatcher.variants(rest)
        var results: [(food: BrandFood, score: Int)] = []
        for index in foods.indices {
            if let brandKey, !brandKeys[index].contains(brandKey) { continue }
            var score: Int
            if rest.isEmpty {
                score = 500
            } else if let match = FuzzyMatcher.bestScore(variants: variants, in: keys[index]) {
                score = match
            } else if brandKey == nil, let match = FuzzyMatcher.bestScore(variants: variants, in: brandKeys[index] + keys[index]) {
                score = match - 50
            } else {
                continue
            }
            if foods[index].isOfficial { score += 20 }
            results.append((foods[index], score))
        }
        return Array(results.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.food.name.count < $1.food.name.count
        }.prefix(limit))
    }
}

// MARK: - 條碼對應的商品

/// 掃過的條碼對應到的營養標示（Open Food Facts 查到的，或自己拍營養標示新增的），下次掃同一個條碼直接帶出
enum BarcodeStore {
    private static let key = "barcodeLabels"

    private static func all() -> [String: NutritionLabel] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let labels = try? JSONDecoder().decode([String: NutritionLabel].self, from: data) else { return [:] }
        return labels
    }

    static func label(for barcode: String) -> NutritionLabel? {
        all()[barcode.filter(\.isNumber)]
    }

    static func save(_ label: NutritionLabel, for barcode: String) {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty else { return }
        var labels = all()
        labels[code] = label
        if let data = try? JSONEncoder().encode(labels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension NutritionLabel {
    /// Open Food Facts 的每 100 g 數值換成「每份」的營養標示
    init(product: ProductLookup.Product) {
        let serving = product.servingGrams ?? 100
        let factor = serving / 100
        let name = product.brand.isEmpty || product.name.contains(product.brand) ? product.name : "\(product.brand) \(product.name)"
        self.init(productName: name, emoji: FoodEmoji.guess(name: product.name),
                  servingSize: serving, servingUnit: "g", servingsPerPackage: 1,
                  calories: product.per100.kcal * factor, protein: product.per100.protein * factor,
                  fat: product.per100.fat * factor, carbs: product.per100.carbs * factor,
                  sugar: product.per100.sugar * factor, sodium: product.per100.sodium * factor)
    }
}
