import Foundation
import SwiftUI

/// 小夥伴的回話風格
enum CompanionStyle: String, CaseIterable, Identifiable {
    case fiery, motivating, savage, disdain, romance, cat, dog, bird

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiery: "火爆"
        case .motivating: "激勵"
        case .savage: "毒舌"
        case .disdain: "嫌棄"
        case .romance: "戀愛"
        case .cat: "貓咪"
        case .dog: "小狗"
        case .bird: "小鳥"
        }
    }

    /// 設定頁上的範例
    var sample: String {
        switch self {
        case .fiery: "還躺著幹嘛！給我起來喝水！現在！🔥"
        case .motivating: "又多記一餐，經驗值 +10！你越來越強了 💪"
        case .savage: "這杯全糖珍奶是補血還是補脂肪？換半糖啦 😏"
        case .disdain: "哼，才不是擔心你…快去喝水啦，笨蛋。"
        case .romance: "今天有好好吃飯嗎？沒吃的話我會心疼喔 💕"
        case .cat: "喵喵～喵？💧"
        case .dog: "汪汪！汪嗚～🦴"
        case .bird: "啾啾！啾～🌾"
        }
    }

    /// 動物模式只會叫，不需要 AI
    var isAnimal: Bool { self == .cat || self == .dog || self == .bird }

    /// 給 AI 的語氣說明
    var prompt: String {
        switch self {
        case .fiery:
            "說話風格：火爆熱血的教練，嗓門大、驚嘆號多，像在場邊吼人（「給我站起來！」），但內容都是為對方好；不罵髒話、不人身攻擊。"
        case .motivating:
            "說話風格：熱情正向的冒險夥伴，肯定每一個小進步，常用遊戲比喻（經驗值、補血、任務、打王）鼓勵對方。"
        case .savage:
            "說話風格：毒舌、很會吐槽，用幽默的挖苦點出問題，但最後一定給一個做得到的建議；不嘲笑外表、體重或身材，不人身攻擊。"
        case .disdain:
            "說話風格：傲嬌、一臉嫌棄、口是心非（「哼，才不是擔心你」），嘴上嫌棄其實很關心，最後還是會給建議。"
        case .romance:
            "說話風格：甜甜的戀人或曖昧對象，會撒嬌、關心、說「想你」「我會心疼」，溫柔但適度，不露骨。"
        case .cat, .dog, .bird:
            ""
        }
    }

    /// 冒泡提示、離線回覆前面加的口頭禪
    var interjection: String {
        switch self {
        case .fiery: "喂！"
        case .motivating: ""
        case .savage: "嘖，"
        case .disdain: "哼，"
        case .romance: "寶貝～"
        case .cat, .dog, .bird: ""
        }
    }

    /// 動物叫聲
    fileprivate var sounds: [String] {
        switch self {
        case .cat: ["喵", "喵喵", "喵～", "喵嗚", "喵？", "喵喵喵", "咪～", "呼嚕嚕"]
        case .dog: ["汪", "汪汪", "汪！", "汪嗚～", "嗚汪", "汪汪汪", "嗷嗚～", "嗚嗚"]
        case .bird: ["啾", "啾啾", "啾～", "啾啾啾", "啾？", "嘰嘰", "啾嚕～", "啾！"]
        default: []
        }
    }

    fileprivate var treat: String {
        switch self {
        case .cat: "🐟"
        case .dog: "🦴"
        case .bird: "🌾"
        default: "🍙"
        }
    }
}

/// 跟 AI 小夥伴的一則訊息
struct CompanionMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable {
        case user, companion
    }

    var id = UUID()
    let role: Role
    let text: String
    var date = Date.now
}

/// AI 小夥伴：聊天紀錄、呼叫 AI、主動冒泡的小提示
@MainActor
final class CompanionStore: ObservableObject {
    static let shared = CompanionStore()

    @Published private(set) var messages: [CompanionMessage] = []
    @Published private(set) var isThinking = false
    /// 浮在小夥伴旁邊的一句話
    @Published var bubble: String?

    private let defaults = UserDefaults.standard
    private var bubbleTask: Task<Void, Never>?

    var style: CompanionStyle {
        CompanionStyle(rawValue: defaults.string(forKey: SettingKey.companionStyle) ?? "") ?? .motivating
    }

    var name: String {
        let saved = (defaults.string(forKey: SettingKey.companionName) ?? "").trimmingCharacters(in: .whitespaces)
        return saved.isEmpty ? "小卡" : saved
    }

    private var userName: String {
        let saved = (defaults.string(forKey: SettingKey.userName) ?? "").trimmingCharacters(in: .whitespaces)
        return saved.isEmpty || saved == "我" ? "冒險家" : saved
    }

    private init() {
        if let data = defaults.data(forKey: SettingKey.companionChat),
           let saved = try? JSONDecoder().decode([CompanionMessage].self, from: data) {
            messages = saved
            // 舊版把招呼存進紀錄，改名後還是舊名字；現在招呼改成即時產生，把存著的那一則拿掉
            if let first = messages.first, first.role == .companion, first.text.contains("我是") {
                messages.removeFirst()
                save()
            }
        }
    }

    // MARK: - 聊天

    /// 聊天最上面的招呼：每次依目前的名字與回話風格產生，不存進紀錄
    func greeting() -> String {
        switch style {
        case .fiery: "喂！\(userName)！我是\(name)！今天也給我拿出幹勁來，吃什麼、動多少都跟我報告！🔥"
        case .motivating: "嗨，\(userName)！我是\(name)，你的冒險夥伴 🍙 想聊吃什麼、怎麼運動，或需要打氣都可以找我！"
        case .savage: "喔，\(userName) 來了。我是\(name)，專門吐槽你的飲食 😏 有什麼想被念的，說吧。"
        case .disdain: "哼，又是你啊 \(userName)…我是\(name)，才、才不是特地在等你呢。有事快說。"
        case .romance: "\(userName)～你終於來了 💕 我是\(name)，一直在等你喔。今天有好好吃飯嗎？"
        case .cat: "喵～喵喵！🐾"
        case .dog: "汪汪！汪～🐾"
        case .bird: "啾啾！啾～🐾"
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        append(CompanionMessage(role: .user, text: trimmed))
        isThinking = true

        Task {
            defer { isThinking = false }
            if style.isAnimal {
                // 動物只會叫，稍微停一下比較像在思考
                try? await Task.sleep(for: .milliseconds(600))
                append(CompanionMessage(role: .companion, text: animalReply(to: trimmed)))
                return
            }
            guard FoodAnalyzer.isReady else {
                append(CompanionMessage(role: .companion, text: offlineReply(to: trimmed)))
                return
            }
            do {
                let (reply, _) = try await FoodAnalyzer().companionReply(system: systemPrompt(), prompt: transcript())
                let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                append(CompanionMessage(role: .companion, text: cleaned.isEmpty ? offlineReply(to: trimmed) : cleaned))
            } catch {
                append(CompanionMessage(role: .companion,
                                        text: "我剛剛斷線了一下…（\(error.localizedDescription)）\n\(offlineReply(to: trimmed))"))
            }
        }
    }

    func clear() {
        messages = []
        defaults.removeObject(forKey: SettingKey.companionChat)
    }

    private func append(_ message: CompanionMessage) {
        messages.append(message)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(messages.suffix(60))) {
            defaults.set(data, forKey: SettingKey.companionChat)
        }
    }

    /// 最近 10 則對話整理成文字（手機上的模型空間小，不放太多）
    private func transcript() -> String {
        let lines = messages.suffix(10).map { message in
            "\(message.role == .user ? userName : name)：\(message.text)"
        }
        return "以下是你和\(userName)的對話，請用\(name)的身分回覆最後一句：\n\n" + lines.joined(separator: "\n")
    }

    private func systemPrompt() -> String {
        """
        你是「\(name)」，手機遊戲風飲食記錄 App《\(AppBrand.name)》裡陪伴玩家的像素小夥伴，一顆會說話的飯糰精靈。玩家是「\(userName)」，你叫他冒險家或他的名字。
        用繁體中文、台灣用語，最多一個 emoji。
        \(style.prompt)
        每次回覆 1～3 句、80 字以內；對方要求詳細說明時才寫長一點。一直維持這個說話風格。
        根據下面的今日狀況，給具體、做得到的建議。不論什麼風格都不能真的傷人：不羞辱外表或身材、不鼓勵節食過度或不健康的行為。
        不做醫療診斷，身體不適或疾病相關的問題，請對方找醫師或營養師。不知道就說不知道，不要編數字。

        \(context())
        """
    }

    // MARK: - 今天的狀況

    private struct Snapshot {
        var eaten: Double
        var budget: Double
        var protein: Double
        var water: Double
        var steps: Double
        var burned: Double
        var loggedMeals: Set<MealType>
        var foodNames: [String]
        var streak: Int
    }

    private func snapshot() -> Snapshot {
        let foods = LogService.shared.foods(on: .now)
        let health = HealthKitManager.shared
        let burned = health.activeCalories + LogService.shared.manualExerciseCalories(on: .now)
        let budget = AppSettings.calorieGoal + (AppSettings.addBackExercise ? burned : 0)
        return Snapshot(
            eaten: foods.sum(\.calories),
            budget: budget,
            protein: foods.sum(\.protein),
            water: LogService.shared.waters(on: .now).sum(\.amount),
            steps: health.steps,
            burned: burned,
            loggedMeals: Set(foods.map(\.mealType)),
            foodNames: foods.map { "\($0.mealType.title) \($0.name)" },
            streak: LogService.shared.streak()
        )
    }

    private func context() -> String {
        let s = snapshot()
        let level = HeroLevel.current()
        let missing = [MealType.breakfast, .lunch, .dinner]
            .filter { !s.loggedMeals.contains($0) && AppSettings.mealTime($0) < Date.now.minutesSinceMidnight }
            .map(\.title)
        return """
        【今日狀況】
        現在：\(Date.now.formatted(.dateTime.month().day().weekday().hour().minute()))
        冒險家：LV.\(level.level) \(level.title)，連續記錄 \(s.streak) 天
        目標：\(AppSettings.effectiveGoal.title)（\(AppSettings.weightKG.formatted()) → \(AppSettings.targetWeightKG.formatted()) kg），每天 \(AppSettings.calorieGoal.rounded0) 大卡、蛋白質 \(AppSettings.proteinGoal.rounded0) g、喝水 \(AppSettings.waterGoal.rounded0) ml、步數 \(AppSettings.stepGoal.rounded0)、運動消耗 \(AppSettings.burnGoal.rounded0) 大卡
        今天：吃了 \(s.eaten.rounded0) 大卡（還可以吃 \((s.budget - s.eaten).rounded0)）、蛋白質 \(s.protein.rounded0) g；喝水 \(s.water.rounded0) ml；步數 \(s.steps.rounded0)；運動消耗 \(s.burned.rounded0) 大卡
        今天吃了：\(s.foodNames.isEmpty ? "還沒記錄" : s.foodNames.prefix(12).joined(separator: "、"))
        \(missing.isEmpty ? "" : "還沒記錄：\(missing.joined(separator: "、"))")
        """
    }

    // MARK: - 沒有 AI 時的回覆

    private func offlineReply(to text: String) -> String {
        let s = snapshot()
        let remaining = (s.budget - s.eaten).rounded0
        var reply: String
        if text.contains("吃什麼") || text.contains("晚餐") || text.contains("午餐") || text.contains("宵夜") {
            reply = remaining > 400
                ? "今天還有 \(remaining) 大卡的額度！推薦一份有蛋白質的主菜配一大份青菜，例如雞胸便當或鮭魚飯 🍙"
                : "今天剩 \(max(remaining, 0)) 大卡，來點清爽的：燙青菜、豆腐、茶葉蛋，肚子飽又不爆表！"
        } else if text.contains("累") || text.contains("不想") || text.contains("放棄") || text.contains("打氣") {
            reply = "冒險不是每天都要打王，今天有記錄就已經在拿經驗值了！連續 \(s.streak) 天，繼續保持 💪"
        } else if s.water < AppSettings.waterGoal * 0.5 {
            reply = "先補個血！今天才喝 \(s.water.rounded0) ml，來一杯水再繼續冒險 💧"
        } else if remaining < 0 {
            reply = "今天超過 \(-remaining) 大卡，沒關係～晚點散步 20 分鐘，明天再扳回一城！"
        } else {
            reply = "收到！今天吃了 \(s.eaten.rounded0) 大卡、走了 \(s.steps.rounded0) 步，步調很穩，我們繼續前進！"
        }
        return style.interjection + reply + "\n（AI 還沒設定好，我先用簡單的方式回答；到「角色 › AI 拍照辨識」可以設定。）"
    }

    /// 動物模式：只會叫，後面接一個看得出意思的 emoji
    private func animalReply(to text: String) -> String {
        let s = snapshot()
        let sounds = style.sounds
        let count = Int.random(in: 1...3)
        let words = (0..<count).map { _ in sounds.randomElement() ?? "" }.joined(separator: " ")
        let hint: String
        if text.contains("吃") || text.contains("餓") {
            hint = style.treat
        } else if s.water < AppSettings.waterGoal * 0.4 {
            hint = "💧"
        } else if AppSettings.burnGoal > 0, s.burned >= AppSettings.burnGoal {
            hint = "🔥"
        } else if s.eaten > s.budget, s.budget > 0 {
            hint = style == .cat ? "🙀" : "😵"
        } else {
            hint = ["💕", "✨", "🐾", style.treat].randomElement() ?? "🐾"
        }
        return "\(words)！\(hint)"
    }

    // MARK: - 主動冒泡

    /// App 回到前景時偶爾冒一句話（每小時最多一次）
    func maybeShowTip() {
        guard defaults.bool(forKey: SettingKey.companionEnabled),
              defaults.bool(forKey: SettingKey.companionTips) else { return }
        let last = defaults.double(forKey: SettingKey.companionLastTip)
        guard Date.now.timeIntervalSince1970 - last > 3600 else { return }
        defaults.set(Date.now.timeIntervalSince1970, forKey: SettingKey.companionLastTip)
        show(tip())
    }

    func show(_ text: String, seconds: Double = 6) {
        bubbleTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { bubble = text }
        bubbleTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation { bubble = nil }
        }
    }

    private func tip() -> String {
        let s = snapshot()
        let minutes = Date.now.minutesSinceMidnight
        var tips: [String] = []
        if s.eaten == 0 && minutes > 10 * 60 { tips.append("今天還沒記錄吃的喔！拍一張照片就有 EXP 🍙") }
        let wake = AppSettings.wakeTime, sleep = AppSettings.sleepTime
        if sleep > wake, minutes > wake {
            let expected = AppSettings.waterGoal * min(1, Double(minutes - wake) / Double(sleep - wake))
            if expected - s.water > 400 { tips.append("補水時間！喝一杯回復 HP 💧") }
        }
        if AppSettings.burnGoal > 0, s.burned >= AppSettings.burnGoal { tips.append("今天運動達標了，超強！🔥") }
        if s.eaten > s.budget, s.budget > 0 { tips.append("熱量有點超過，晚點散步一下就能扳回來！") }
        if minutes > 15 * 60, s.steps < AppSettings.stepGoal * 0.5 { tips.append("步數還差一些，起來走走 10 分鐘吧！") }
        if s.streak >= 3 { tips.append("連續 \(s.streak) 天記錄，冒險家好穩！") }
        if tips.isEmpty {
            tips = ["點我聊天，我可以幫你想下一餐吃什麼！", "今天也一起好好吃飯吧！", "有記錄就有經驗值，繼續冒險！"]
        }
        if style.isAnimal { return animalReply(to: "") }
        return style.interjection + (tips.randomElement() ?? tips[0])
    }
}
