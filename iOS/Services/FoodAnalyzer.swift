import Foundation
import UIKit

/// AI 回傳的餐點分析結果（格式由 JSON Schema 強制保證）
struct FoodAnalysis: Decodable {
    struct Item: Decodable {
        let name: String
        let emoji: String
        let portion: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let sodium: Double
        let sugar: Double
    }

    let items: [Item]
    /// high / medium / low
    let confidence: String
    let notes: String
}

/// 包裝上「營養標示」讀出來的內容，營養數值都是「每份」
struct NutritionLabel: Codable, Identifiable, Hashable {
    let productName: String
    let emoji: String
    /// 每一份量
    let servingSize: Double
    /// g 或 ml
    let servingUnit: String
    /// 本包裝含幾份
    let servingsPerPackage: Double
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let sugar: Double
    /// 毫克
    let sodium: Double

    var id: String { productName }

    var isLiquid: Bool {
        let unit = servingUnit.lowercased()
        return unit.contains("ml") || unit.contains("毫升")
    }

    /// 熱量跟「蛋白質×4 + 碳水×4 + 脂肪×9」差太多，代表可能有數字讀錯
    var looksInconsistent: Bool {
        guard calories > 20 else { return false }
        let computed = protein * 4 + carbs * 4 + fat * 9
        return abs(computed - calories) / calories > 0.3
    }
}

/// 可以選用的 AI 服務
enum AIProvider: String, CaseIterable, Identifiable {
    case apple, gemini, claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple 內建 AI（免費、離線）"
        case .gemini: "Google Gemini（有免費額度）"
        case .claude: "Anthropic Claude（付費）"
        }
    }

    var shortName: String {
        switch self {
        case .apple: "Apple AI"
        case .gemini: "Gemini"
        case .claude: "Claude"
        }
    }

    var keychainKey: String { self == .claude ? Keychain.claudeAPIKey : Keychain.geminiAPIKey }

    /// 寫在 Secrets.swift 裡的金鑰
    var builtInKey: String? {
        let key: String
        switch self {
        case .apple: return nil
        case .gemini: key = Secrets.geminiAPIKey
        case .claude: key = Secrets.claudeAPIKey
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// App 設定裡輸入的金鑰優先，其次是 Secrets.swift 裡的
    var apiKey: String? {
        guard self != .apple else { return nil }
        if let saved = Keychain.get(keychainKey), !saved.isEmpty { return saved }
        return builtInKey
    }

    var keyPlaceholder: String { self == .claude ? "貼上 API 金鑰（sk-ant-…）" : "貼上 API 金鑰（AQ.… 或 AIza…）" }

    var keyURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/")!
        default: URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    var models: [FoodAnalyzer.ModelOption] {
        switch self {
        case .apple: []
        case .gemini: [
            FoodAnalyzer.ModelOption(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash（較準確，預設）"),
            FoodAnalyzer.ModelOption(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite（較快）"),
        ]
        case .claude: [
            FoodAnalyzer.ModelOption(id: "claude-opus-5", name: "Claude Opus 5（最準確）"),
            FoodAnalyzer.ModelOption(id: "claude-sonnet-5", name: "Claude Sonnet 5（費用較低）"),
        ]
        }
    }
}

enum FoodAnalyzerError: LocalizedError {
    case missingKey
    case appleAIUnavailable
    case noText
    case unreadableLabel
    case badStatus(Int, String)
    case refusal
    case truncated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "還沒設定 AI 金鑰。請到「角色 › AI 拍照辨識」輸入；也可以先用下方的資料庫搜尋或手動輸入。"
        case .appleAIUnavailable:
            "Apple 內建 AI 目前無法使用（\(OnDeviceFoodAnalyzer.statusText)）。可以在「角色 › AI 拍照辨識」加上 Gemini 金鑰當備援。"
        case .noText:
            "讀不到標示上的文字。請靠近一點、對好焦、避免反光再拍一次。"
        case .unreadableLabel:
            "讀不出每一份量或熱量，請再拍一次清楚的「營養標示」表格。"
        case .badStatus(401, _), .badStatus(403, _):
            "API 金鑰無效或沒有權限，請到「角色 › AI 拍照辨識」重新輸入。"
        case .badStatus(400, let message) where message.localizedCaseInsensitiveContains("api key"):
            "API 金鑰無效，請到「角色 › AI 拍照辨識」重新輸入。"
        case .badStatus(429, _):
            "免費額度暫時用完了，或請求太頻繁。請稍後再試。"
        case .badStatus(let code, _) where code >= 500:
            "AI 伺服器目前忙碌（\(code)），請稍後再試。"
        case .badStatus(let code, let message):
            "辨識失敗（\(code)）：\(message)"
        case .refusal:
            "這張照片無法分析，請換一張或改用文字描述。"
        case .truncated:
            "回應被截斷了，請再試一次。"
        case .invalidResponse:
            "無法解讀 AI 的回應，請再試一次。"
        }
    }
}

/// 從照片或文字估算營養、讀取營養標示。
/// 預設用 iPhone 內建 Apple AI，不能用或失敗時改用 Gemini；也可以指定 Gemini / Claude。
/// Swift 沒有官方 SDK，Gemini 與 Claude 都直接呼叫 REST API。
struct FoodAnalyzer {
    struct ModelOption: Identifiable {
        let id: String
        let name: String
    }

    /// 餐點辨識結果，以及這次用了哪一個 AI
    struct Outcome {
        let analysis: FoodAnalysis
        let provider: AIProvider
    }

    /// 營養標示讀取結果，以及這次用了哪一個 AI
    struct LabelOutcome {
        let label: NutritionLabel
        let provider: AIProvider
    }

    static var provider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: SettingKey.aiProvider) ?? "") ?? .apple
    }

    /// 目前設定能不能開始辨識
    static var isReady: Bool {
        switch provider {
        case .apple: OnDeviceFoodAnalyzer.isAvailable || AIProvider.gemini.apiKey != nil
        case .gemini, .claude: provider.apiKey != nil
        }
    }

    // MARK: - 餐點

    /// - Parameters:
    ///   - imageData: JPEG 照片（可為 nil，只用文字描述）
    ///   - description: 使用者的補充說明或文字描述
    ///   - preferred: 指定這次要用的 AI（例如「用 Gemini 再算一次」），nil 表示依設定
    func analyze(imageData: Data?, description: String, preferred: AIProvider? = nil) async throws -> Outcome {
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if imageData != nil {
            text = note.isEmpty ? "請分析這張照片中的餐點。" : "請分析這張照片中的餐點。\n使用者補充：\(note)"
        } else {
            text = "請估算這一餐的營養：\(note)"
        }

        let (analysis, provider) = try await run(
            preferred: preferred,
            onDevice: { () async throws -> FoodAnalysis in
                try await OnDeviceFoodAnalyzer.analyze(image: imageData.flatMap(UIImage.init(data:)), text: text)
            },
            remote: { (provider: AIProvider) async throws -> FoodAnalysis in
                try await self.remote(provider, task: Self.mealTask, imageData: imageData, text: text)
            }
        )
        return Outcome(analysis: analysis, provider: provider)
    }

    // MARK: - 營養標示

    func readLabel(imageData: Data, preferred: AIProvider? = nil) async throws -> LabelOutcome {
        let (label, provider) = try await run(
            preferred: preferred,
            onDevice: { () async throws -> NutritionLabel in
                guard let image = UIImage(data: imageData) else { throw FoodAnalyzerError.noText }
                return try await OnDeviceFoodAnalyzer.readLabel(image: image)
            },
            remote: { (provider: AIProvider) async throws -> NutritionLabel in
                try await self.remote(provider, task: Self.labelTask, imageData: imageData,
                                      text: "請讀取這張營養標示。")
            }
        )
        guard label.servingSize > 0, label.calories > 0 || label.protein + label.carbs + label.fat > 0 else {
            throw FoodAnalyzerError.unreadableLabel
        }
        return LabelOutcome(label: label, provider: provider)
    }

    // MARK: - AI 健康洞察

    static let insightPrompt = """
    你是溫暖、務實的營養師朋友。根據使用者最近 7 天的紀錄，用繁體中文寫一段分析：
    1. 先用一句話肯定做得好的地方。
    2. 列出最值得調整的 3 件事，每件都要具體、明天就做得到（例如「晚餐的滷味換成燙青菜」）。
    3. 最後一句鼓勵。
    不超過 250 字，不要用表格。某天數字特別低可能只是沒記錄，不要苛責。
    """

    /// 分析最近的紀錄，回傳文字與使用的 AI
    func insight(summary: String) async throws -> (String, AIProvider) {
        try await run(
            preferred: nil,
            onDevice: { () async throws -> String in
                try await OnDeviceFoodAnalyzer.insight(summary: summary)
            },
            remote: { (provider: AIProvider) async throws -> String in
                try await self.remoteText(provider, task: Self.insightTask, text: summary)
            }
        )
    }

    private static let insightTask = RemoteTask(systemPrompt: insightPrompt, geminiSchema: nil, claudeSchema: nil)

    // MARK: - AI 小夥伴

    /// 小夥伴聊天：system 是角色設定加上今天的狀況，prompt 是整理成文字的對話紀錄
    func companionReply(system: String, prompt: String) async throws -> (String, AIProvider) {
        try await run(
            preferred: nil,
            onDevice: { () async throws -> String in
                try await OnDeviceFoodAnalyzer.chat(instructions: system, prompt: prompt)
            },
            remote: { (provider: AIProvider) async throws -> String in
                let task = RemoteTask(systemPrompt: system, geminiSchema: nil, claudeSchema: nil)
                return try await self.remoteText(provider, task: task, text: prompt)
            }
        )
    }

    // MARK: - 選擇 AI

    /// Apple AI 優先；不能用或失敗時，有 Gemini 金鑰就自動改用 Gemini
    private func run<T>(preferred: AIProvider?,
                        onDevice: () async throws -> T,
                        remote: (AIProvider) async throws -> T) async throws -> (T, AIProvider) {
        let provider = preferred ?? Self.provider
        guard provider == .apple else {
            return (try await remote(provider), provider)
        }

        let hasGeminiBackup = AIProvider.gemini.apiKey != nil
        if OnDeviceFoodAnalyzer.isAvailable {
            do {
                return (try await onDevice(), .apple)
            } catch {
                print("Apple AI 失敗：\(error)")
                if !hasGeminiBackup { throw error }
            }
        } else if !hasGeminiBackup {
            throw FoodAnalyzerError.appleAIUnavailable
        }
        return (try await remote(.gemini), .gemini)
    }

    // MARK: - 雲端 AI 的任務設定

    /// 雲端 AI 的一種任務；沒有 schema 表示回傳一般文字
    private struct RemoteTask {
        let systemPrompt: String
        let geminiSchema: [String: Any]?
        let claudeSchema: [String: Any]?
    }

    private static let itemFields = ["name", "emoji", "portion", "calories", "protein", "carbs", "fat", "sodium", "sugar"]

    private static let mealTask = RemoteTask(
        systemPrompt: """
        你是台灣的註冊營養師，負責從餐點照片或文字描述估算營養。

        - 把每一樣看得出來的食物或飲料列成一個 item；便當、套餐請拆成主食、主菜、配菜。
        - name 用繁體中文、台灣常見說法（例如：滷肉飯、茶葉蛋、燙青菜、珍珠奶茶）。
        - emoji 填一個最能代表這項食物的 emoji（例如 🍚、🥚、🥬、🧋）。
        - portion 用直覺的份量描述並附上估計重量或容量，例如「1 碗（約 200 g）」、「大杯 700 ml」。
        - 數值是這一份的總量，不是每 100 公克：calories 為 kcal；protein、carbs、fat、sugar 為公克；sodium 為毫克。
        - 參考台灣食品營養成分資料庫與常見外食份量。台灣外食通常較油、較鹹，請反映在脂肪與鈉。
        - 如果照片是包裝上的「營養標示」，直接讀取標示上的數值，並依使用者說的份數換算。
        - 使用者的補充說明（例如只吃一半、去冰無糖）優先於你從照片看到的內容。
        - 看不清楚或份量不確定時，用台灣常見份量估計，並把假設寫進 notes。
        - 看不到任何食物時，items 回傳空陣列，並在 notes 說明。
        - confidence 只能填 high、medium 或 low：辨識和份量都有把握填 high，部分不確定填 medium，大多靠推測填 low。
        - notes：一到兩句繁體中文，說明估算依據，或給一個具體可行的小建議。
        """,
        geminiSchema: [
            "type": "OBJECT",
            "properties": [
                "items": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING"],
                            "emoji": ["type": "STRING"],
                            "portion": ["type": "STRING"],
                            "calories": ["type": "NUMBER"],
                            "protein": ["type": "NUMBER"],
                            "carbs": ["type": "NUMBER"],
                            "fat": ["type": "NUMBER"],
                            "sodium": ["type": "NUMBER"],
                            "sugar": ["type": "NUMBER"],
                        ],
                        "required": itemFields,
                        "propertyOrdering": itemFields,
                    ],
                ],
                "confidence": ["type": "STRING"],
                "notes": ["type": "STRING"],
            ],
            "required": ["items", "confidence", "notes"],
            "propertyOrdering": ["items", "confidence", "notes"],
        ],
        claudeSchema: [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "emoji": ["type": "string"],
                            "portion": ["type": "string"],
                            "calories": ["type": "number"],
                            "protein": ["type": "number"],
                            "carbs": ["type": "number"],
                            "fat": ["type": "number"],
                            "sodium": ["type": "number"],
                            "sugar": ["type": "number"],
                        ],
                        "required": itemFields,
                        "additionalProperties": false,
                    ],
                ],
                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                "notes": ["type": "string"],
            ],
            "required": ["items", "confidence", "notes"],
            "additionalProperties": false,
        ]
    )

    private static let labelFields = ["productName", "emoji", "servingSize", "servingUnit", "servingsPerPackage",
                                      "calories", "protein", "fat", "carbs", "sugar", "sodium"]

    /// 讀營養標示的說明（Apple AI 也共用）
    static let labelRules = """
    - productName：包裝上的商品名稱，看不到就填「包裝食品」；emoji：一個代表它的 emoji。
    - servingSize、servingUnit：「每一份量」的數字與單位（g 或 ml）。
    - servingsPerPackage：「本包裝含 N 份」的 N，沒寫就填 1。
    - calories（大卡）、protein、fat、carbs、sugar（公克）、sodium（毫克）一律填「每份」的數值。
    - 標示如果只有「每 100 公克」或「每 100 毫升」，請依每一份量換算成每份；完全沒有每一份量時，servingSize 填 100，數值填每 100 公克（毫升）的。
    - 「每日參考值百分比」不是營養素的量，不要填進去。
    - 熱量若標示為千焦（kJ），請除以 4.184 換算成大卡。看不清楚的數字填 0。
    """

    private static let labelTask = RemoteTask(
        systemPrompt: "你負責讀取台灣包裝食品上的「營養標示」。\n\n" + labelRules,
        geminiSchema: [
            "type": "OBJECT",
            "properties": [
                "productName": ["type": "STRING"],
                "emoji": ["type": "STRING"],
                "servingSize": ["type": "NUMBER"],
                "servingUnit": ["type": "STRING"],
                "servingsPerPackage": ["type": "NUMBER"],
                "calories": ["type": "NUMBER"],
                "protein": ["type": "NUMBER"],
                "fat": ["type": "NUMBER"],
                "carbs": ["type": "NUMBER"],
                "sugar": ["type": "NUMBER"],
                "sodium": ["type": "NUMBER"],
            ],
            "required": labelFields,
            "propertyOrdering": labelFields,
        ],
        claudeSchema: [
            "type": "object",
            "properties": [
                "productName": ["type": "string"],
                "emoji": ["type": "string"],
                "servingSize": ["type": "number"],
                "servingUnit": ["type": "string"],
                "servingsPerPackage": ["type": "number"],
                "calories": ["type": "number"],
                "protein": ["type": "number"],
                "fat": ["type": "number"],
                "carbs": ["type": "number"],
                "sugar": ["type": "number"],
                "sodium": ["type": "number"],
            ],
            "required": labelFields,
            "additionalProperties": false,
        ]
    )

    // MARK: - 雲端 AI 呼叫

    private func remote<T: Decodable>(_ provider: AIProvider, task: RemoteTask,
                                      imageData: Data?, text: String) async throws -> T {
        let resultText = try await remoteText(provider, task: task, imageData: imageData, text: text)
        guard let data = resultText.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw FoodAnalyzerError.invalidResponse
        }
        return value
    }

    private func remoteText(_ provider: AIProvider, task: RemoteTask,
                            imageData: Data? = nil, text: String) async throws -> String {
        guard let apiKey = provider.apiKey else { throw FoodAnalyzerError.missingKey }
        switch provider {
        case .claude:
            return try await callClaude(task: task, imageData: imageData, text: text,
                                        apiKey: apiKey, model: AppSettings.claudeModel)
        case .gemini, .apple:
            return try await callGemini(task: task, imageData: imageData, text: text,
                                        apiKey: apiKey, model: AppSettings.geminiModel)
        }
    }

    /// Gemini：POST /v1beta/models/{model}:generateContent
    private func callGemini(task: RemoteTask, imageData: Data?, text: String,
                            apiKey: String, model: String) async throws -> String {
        var parts: [[String: Any]] = []
        if let imageData {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": imageData.base64EncodedString()]])
        }
        parts.append(["text": text])

        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": task.systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
        ]
        if let schema = task.geminiSchema {
            body["generationConfig"] = [
                "responseMimeType": "application/json",
                "responseSchema": schema,
            ]
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw FoodAnalyzerError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard http.statusCode == 200 else {
            throw FoodAnalyzerError.badStatus(http.statusCode, errorMessage(json, data))
        }
        if (json?["promptFeedback"] as? [String: Any])?["blockReason"] != nil {
            throw FoodAnalyzerError.refusal
        }
        guard let candidate = (json?["candidates"] as? [[String: Any]])?.first else {
            throw FoodAnalyzerError.refusal
        }
        switch candidate["finishReason"] as? String {
        case "MAX_TOKENS": throw FoodAnalyzerError.truncated
        case "SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII": throw FoodAnalyzerError.refusal
        default: break
        }

        let resultParts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        return resultParts
            .filter { ($0["thought"] as? Bool) != true } // 略過模型的思考摘要
            .compactMap { $0["text"] as? String }
            .joined()
    }

    /// Claude：POST /v1/messages
    private func callClaude(task: RemoteTask, imageData: Data?, text: String,
                            apiKey: String, model: String) async throws -> String {
        var content: [[String: Any]] = []
        if let imageData {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": imageData.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": text])

        var outputConfig: [String: Any] = ["effort": "medium"]
        if let schema = task.claudeSchema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": task.systemPrompt,
            "output_config": outputConfig,
            "messages": [["role": "user", "content": content]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if model == "claude-opus-5" {
            // 安全機制偶爾誤判拒答時，由伺服器自動改用建議的備援模型重跑
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard http.statusCode == 200 else {
            throw FoodAnalyzerError.badStatus(http.statusCode, errorMessage(json, data))
        }
        switch json?["stop_reason"] as? String {
        case "refusal": throw FoodAnalyzerError.refusal
        case "max_tokens": throw FoodAnalyzerError.truncated
        default: break
        }

        let blocks = json?["content"] as? [[String: Any]] ?? []
        return blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
    }

    /// 兩家的錯誤格式都是 {"error": {"message": ...}}
    private func errorMessage(_ json: [String: Any]?, _ data: Data) -> String {
        ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
    }

    /// 伺服器忙碌（429、5xx）時等一下再重試一次
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FoodAnalyzerError.invalidResponse }
            let retryable = http.statusCode == 429 || http.statusCode >= 500
            if retryable && attempt == 0 {
                try await Task.sleep(for: .seconds(3))
                continue
            }
            return (data, http)
        }
        throw FoodAnalyzerError.invalidResponse
    }
}

/// 記住讀過的營養標示，下次同一個商品不用再拍
enum LabelStore {
    private static let key = "savedNutritionLabels"

    static func all() -> [NutritionLabel] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let labels = try? JSONDecoder().decode([NutritionLabel].self, from: data) else { return [] }
        return labels
    }

    static func save(_ label: NutritionLabel) {
        var labels = all().filter { $0.productName != label.productName }
        labels.insert(label, at: 0)
        if let data = try? JSONEncoder().encode(Array(labels.prefix(30))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(_ label: NutritionLabel) {
        let labels = all().filter { $0.productName != label.productName }
        if let data = try? JSONEncoder().encode(labels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
