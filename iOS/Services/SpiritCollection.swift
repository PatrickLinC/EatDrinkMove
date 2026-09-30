import Foundation
import SwiftUI

// MARK: - 元氣大陸

/// 元氣大陸的區域，每個區域的精靈由不同的生活習慣喚醒
enum SpiritRegion: String, CaseIterable, Identifiable {
    case riceVillage, trailValley, dawnHill, dreamForest, moonMarsh, royalCity, sacredLake, calmTower, frontier, festival

    var id: String { rawValue }

    var title: String {
        switch self {
        case .riceVillage: "米糧村"
        case .trailValley: "步道山谷"
        case .dawnHill: "晨光丘"
        case .dreamForest: "夢之森"
        case .moonMarsh: "月影沼澤"
        case .royalCity: "王城"
        case .sacredLake: "聖泉湖"
        case .calmTower: "靜心塔"
        case .frontier: "開拓區"
        case .festival: "節慶廣場"
        }
    }

    var detail: String {
        switch self {
        case .riceVillage: "冒險開始的村莊，走第一段路、睡第一個好覺"
        case .trailValley: "走越多路，越深入山谷"
        case .dawnHill: "早起的冒險者才看得到晨光"
        case .dreamForest: "睡得夠久，森林才會醒來"
        case .moonMarsh: "早點睡，沼澤的迷霧就會散去"
        case .royalCity: "長期累積的冒險者才能進城"
        case .sacredLake: "水喝夠了，湖水才會清澈見底"
        case .calmTower: "靜下心呼吸，塔頂的鐘才會響"
        case .frontier: "走出家門，地圖才會一格一格畫出來"
        case .festival: "每年節慶才開放，錯過了明年還會再來"
        }
    }

    var art: PixelArt {
        switch self {
        case .riceVillage: .bowl
        case .trailValley: .footprint
        case .dawnHill: .sun
        case .dreamForest: .moon
        case .moonMarsh: .star
        case .royalCity: .trophy
        case .sacredLake: .drop
        case .calmTower: .bell
        case .frontier: .campBanner
        case .festival: .festivalLantern
        }
    }

    var color: Color {
        switch self {
        case .riceVillage: .brand
        case .trailValley: .move
        case .dawnHill: .carbs
        case .dreamForest: .water
        case .moonMarsh: .fat
        case .royalCity: .protein
        case .sacredLake: .water
        case .calmTower: .fat
        case .frontier: .move
        case .festival: .calorie
        }
    }

    var spirits: [CompanionSkin] { CompanionSkin.dexOrder.filter { $0.region == self } }
}

/// 喚醒條件（時間都是「當天第幾分鐘」，例如 7:30 = 450；午夜 = 1440）
enum SpiritRequirement {
    case starter
    /// 收集幾隻精靈
    case collect(Int)
    /// 單日走滿幾步
    case stepsInDay(Double)
    /// 累計步數
    case totalSteps(Double)
    /// 累計幾天走滿幾步
    case stepDays(Double, steps: Double)
    /// 連續幾天、每天走滿幾步
    case stepStreak(days: Int, steps: Double)
    /// 累計幾晚睡滿幾小時
    case sleepNights(Double, hours: Double)
    /// 連續幾晚睡滿幾小時
    case sleepStreak(nights: Int, hours: Double)
    /// 累計幾天在某時間前起床，且睡滿幾小時
    case earlyRiser(Double, before: Int, hours: Double)
    /// 連續幾天在某時間前起床，且睡滿幾小時
    case earlyStreak(days: Int, before: Int, hours: Double)
    /// 累計幾晚在某時間前睡著，且睡滿幾小時
    case earlySleep(Double, before: Int, hours: Double)
    /// 連續幾晚在某時間前睡著，且睡滿幾小時
    case earlySleepStreak(nights: Int, before: Int, hours: Double)
    /// 連續幾天走滿幾步、而且前一晚睡滿幾小時
    case perfectStreak(days: Int, steps: Double, hours: Double)
    /// 累計幾天喝滿喝水目標
    case waterDays(Double)
    /// 連續幾天喝滿喝水目標
    case waterStreak(days: Int)
    /// 累計幾天做一分鐘呼吸
    case breathDays(Double)
    /// 連續幾天做一分鐘呼吸
    case breathStreak(days: Int)
    /// 累計幾天精神力在多少以上
    case calmDays(Double, mp: Int)
    /// 完成幾次出發冒險（含手錶記錄的路線）
    case routes(Double)
    /// 單次冒險走滿幾公尺
    case longRoute(Double)
    /// 世界迷霧解除幾平方公里
    case fogArea(Double)
    /// 某個節慶期間有幾天做到那個節慶的習慣（同一年的活動期間內）
    case festival(Festival, days: Int)

    var text: String {
        switch self {
        case .starter: "一開始就在你身邊"
        case .collect(let count): "喚醒 \(count) 隻精靈"
        case .stepsInDay(let steps): "單日走滿 \(steps.formatted()) 步"
        case .totalSteps(let steps): "累計走 \(steps.formatted()) 步"
        case .stepDays(let days, let steps): "累計 \(days.formatted()) 天走滿 \(steps.formatted()) 步"
        case .stepStreak(let days, let steps): "連續 \(days) 天，每天走滿 \(steps.formatted()) 步"
        case .sleepNights(let nights, let hours):
            nights == 1 ? "一晚睡滿 \(hours.formatted()) 小時" : "累計 \(nights.formatted()) 晚睡滿 \(hours.formatted()) 小時"
        case .sleepStreak(let nights, let hours): "連續 \(nights) 晚睡滿 \(hours.formatted()) 小時"
        case .earlyRiser(let days, let before, let hours):
            "累計 \(days.formatted()) 天在 \(Self.clock(before)) 前起床，且睡滿 \(hours.formatted()) 小時"
        case .earlyStreak(let days, let before, let hours):
            "連續 \(days) 天在 \(Self.clock(before)) 前起床，且睡滿 \(hours.formatted()) 小時"
        case .earlySleep(let nights, let before, let hours):
            "累計 \(nights.formatted()) 晚在 \(Self.clock(before)) 前睡著，且睡滿 \(hours.formatted()) 小時"
        case .earlySleepStreak(let nights, let before, let hours):
            "連續 \(nights) 晚在 \(Self.clock(before)) 前睡著，且睡滿 \(hours.formatted()) 小時"
        case .perfectStreak(let days, let steps, let hours):
            "連續 \(days) 天走滿 \(steps.formatted()) 步，而且每晚睡滿 \(hours.formatted()) 小時"
        case .waterDays(let days): "累計 \(days.formatted()) 天喝滿每日喝水目標"
        case .waterStreak(let days): "連續 \(days) 天喝滿每日喝水目標"
        case .breathDays(let days): "累計 \(days.formatted()) 天做一分鐘呼吸"
        case .breathStreak(let days): "連續 \(days) 天做一分鐘呼吸"
        case .calmDays(let days, let mp): "累計 \(days.formatted()) 天精神力在 \(mp) 以上（要戴手錶累積 7 天的基準）"
        case .routes(let count): count == 1 ? "完成第一次出發冒險（手錶記錄的也算）" : "累計完成 \(count.formatted()) 次出發冒險"
        case .longRoute(let meters): "單次冒險走滿 \((meters / 1000).formatted()) 公里"
        case .fogArea(let area): "世界迷霧解除 \(area.formatted()) 平方公里"
        case .festival(let festival, let days):
            "\(festival.title)期間（\(festival.period)）有 \(days) \(festival.habit.unit)\(festival.habit.text)"
        }
    }

    /// 進度條的終點
    var target: Double {
        switch self {
        case .starter: 1
        case .collect(let count): Double(count)
        case .stepsInDay(let steps), .totalSteps(let steps): steps
        case .stepDays(let days, _), .sleepNights(let days, _), .earlyRiser(let days, _, _), .earlySleep(let days, _, _): days
        case .stepStreak(let days, _), .sleepStreak(let days, _), .earlyStreak(let days, _, _),
             .earlySleepStreak(let days, _, _), .perfectStreak(let days, _, _): Double(days)
        case .waterDays(let days), .breathDays(let days), .calmDays(let days, _), .routes(let days): days
        case .waterStreak(let days), .breathStreak(let days), .festival(_, let days): Double(days)
        case .longRoute(let meters): meters / 1000
        case .fogArea(let area): area
        }
    }

    /// 進度的單位
    var unit: String {
        switch self {
        case .starter: ""
        case .collect: "隻"
        case .stepsInDay, .totalSteps: "步"
        case .stepDays, .stepStreak, .earlyRiser, .earlyStreak, .perfectStreak: "天"
        case .sleepNights, .sleepStreak, .earlySleep, .earlySleepStreak: "晚"
        case .waterDays, .waterStreak, .breathDays, .breathStreak, .calmDays: "天"
        case .routes: "次"
        case .longRoute: "公里"
        case .fogArea: "平方公里"
        case .festival(let festival, _): festival.habit.unit
        }
    }

    static func clock(_ minutes: Int) -> String {
        minutes >= 24 * 60 ? "0:00" : String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

extension CompanionSkin {
    /// 圖鑑編號順序（依區域）
    static let dexOrder: [CompanionSkin] = [
        .onigiri, .boba, .bun,
        .dog, .goblin, .mimic,
        .egg, .parrot, .griffin,
        .cat, .slime, .mushroom,
        .ghost, .wizard, .skeleton,
        .knight, .dwarf, .dragon,
        .frog, .mermaid, .unicorn,
        .owl, .monk, .gargoyle,
        .fox, .bard, .archer,
        .nian, .zongzi, .goldfish, .rabbit, .pumpkin, .snowman,
    ]

    /// 一般區域的精靈（不含節慶精靈，「精靈大師」稱號看這個）
    static var regularOrder: [CompanionSkin] { dexOrder.filter { $0.region != .festival } }

    /// 節慶精靈對應的節慶
    var festival: Festival? { Festival.allCases.first { $0.spirit == self } }

    var dexNumber: Int { (Self.dexOrder.firstIndex(of: self) ?? 0) + 1 }

    var region: SpiritRegion {
        switch self {
        case .onigiri, .boba, .bun: .riceVillage
        case .dog, .goblin, .mimic: .trailValley
        case .egg, .parrot, .griffin: .dawnHill
        case .cat, .slime, .mushroom: .dreamForest
        case .ghost, .wizard, .skeleton: .moonMarsh
        case .knight, .dwarf, .dragon: .royalCity
        case .frog, .mermaid, .unicorn: .sacredLake
        case .owl, .monk, .gargoyle: .calmTower
        case .fox, .bard, .archer: .frontier
        case .nian, .zongzi, .goldfish, .rabbit, .pumpkin, .snowman: .festival
        }
    }

    private static let wakeBefore = 7 * 60 + 30
    private static let midnight = 24 * 60

    var requirement: SpiritRequirement {
        switch self {
        case .onigiri: .starter
        case .boba: .stepsInDay(6000)
        case .bun: .sleepNights(1, hours: 7)
        case .dog: .totalSteps(50000)
        case .goblin: .stepStreak(days: 14, steps: 8000)
        case .mimic: .stepsInDay(12000)
        case .egg: .earlyRiser(3, before: Self.wakeBefore, hours: 6)
        case .parrot: .earlyStreak(days: 5, before: Self.wakeBefore, hours: 6)
        case .griffin: .earlyRiser(14, before: 7 * 60, hours: 6)
        case .cat: .sleepNights(7, hours: 7)
        case .slime: .sleepStreak(nights: 7, hours: 7)
        case .mushroom: .sleepNights(3, hours: 8)
        case .ghost: .earlySleep(3, before: Self.midnight, hours: 6)
        case .wizard: .earlySleepStreak(nights: 7, before: 23 * 60 + 30, hours: 6)
        case .skeleton: .earlySleep(20, before: Self.midnight, hours: 6)
        case .knight: .totalSteps(200_000)
        case .dwarf: .stepDays(7, steps: 10000)
        case .dragon: .perfectStreak(days: 21, steps: 6000, hours: 7)
        case .frog: .waterDays(3)
        case .mermaid: .waterStreak(days: 7)
        case .unicorn: .waterDays(20)
        case .owl: .breathDays(3)
        case .monk: .breathStreak(days: 5)
        case .gargoyle: .calmDays(10, mp: 60)
        case .fox: .routes(1)
        case .bard: .fogArea(1)
        case .archer: .longRoute(5000)
        case .nian, .zongzi, .goldfish, .rabbit, .pumpkin, .snowman:
            festival.map { .festival($0, days: $0.days) } ?? .starter
        }
    }

    /// 閃光版的條件：大約是原本的三倍（連續型是兩倍）
    var shinyRequirement: SpiritRequirement {
        switch self {
        case .onigiri: .collect(9)
        case .boba: .stepsInDay(10000)
        case .bun: .sleepNights(5, hours: 7)
        case .dog: .totalSteps(150_000)
        case .goblin: .stepStreak(days: 28, steps: 8000)
        case .mimic: .stepsInDay(18000)
        case .egg: .earlyRiser(10, before: Self.wakeBefore, hours: 6)
        case .parrot: .earlyStreak(days: 10, before: Self.wakeBefore, hours: 6)
        case .griffin: .earlyRiser(42, before: 7 * 60, hours: 6)
        case .cat: .sleepNights(21, hours: 7)
        case .slime: .sleepStreak(nights: 14, hours: 7)
        case .mushroom: .sleepNights(10, hours: 8)
        case .ghost: .earlySleep(10, before: Self.midnight, hours: 6)
        case .wizard: .earlySleepStreak(nights: 14, before: 23 * 60 + 30, hours: 6)
        case .skeleton: .earlySleep(60, before: Self.midnight, hours: 6)
        case .knight: .totalSteps(600_000)
        case .dwarf: .stepDays(21, steps: 10000)
        case .dragon: .perfectStreak(days: 42, steps: 6000, hours: 7)
        case .frog: .waterDays(10)
        case .mermaid: .waterStreak(days: 14)
        case .unicorn: .waterDays(60)
        case .owl: .breathDays(10)
        case .monk: .breathStreak(days: 10)
        case .gargoyle: .calmDays(30, mp: 60)
        case .fox: .routes(10)
        case .bard: .fogArea(3)
        case .archer: .longRoute(10000)
        case .nian, .zongzi, .goldfish, .rabbit, .pumpkin, .snowman:
            festival.map { .festival($0, days: $0.shinyDays) } ?? .starter
        }
    }

    var lore: String {
        switch self {
        case .onigiri: "冒險者的第一個夥伴。嘴巴很硬、心很軟，說不肯走，其實一直跟在你身後。"
        case .boba: "米糧村口的精靈，走累了會冒出珍珠泡泡，最愛聽腳步聲。"
        case .bun: "蒸籠是牠的床。睡飽的時候整個膨起來，睡不夠就扁扁的。"
        case .dog: "金黃色的毛，尾巴永遠在搖。走過的路越多，牠就越認得你。"
        case .goblin: "住在步道山谷最深處，只跟真正的健行者交朋友。其實很害羞。"
        case .mimic: "山谷裡的寶箱怪。一天走超過一萬兩千步的人，牠才肯打開箱子——裡面其實只有牠自己。"
        case .egg: "晨光丘的第一道陽光把牠煎得金黃，只在早起的人面前出現。"
        case .parrot: "每天第一個叫醒大家的精靈，嚮往作息規律的冒險者。"
        case .griffin: "在晨光丘上空巡邏的獅鷲，天剛亮就起飛，只載早起的冒險者。"
        case .cat: "夢之森的守門貓，睡覺專家。看你每晚都好好睡，才願意跟你走。"
        case .slime: "夜露凝成的精靈，只在連續好眠的夜裡慢慢成形。"
        case .mushroom: "夢之森的蘑菇怪，睡得越久長得越高。聽說牠的夢是彩色的。"
        case .ghost: "月影沼澤的小幽靈，最怕熬夜的人——因為熬夜的人比牠還像幽靈。"
        case .wizard: "月影沼澤的見習巫師，相信早睡是最強的魔法，每晚十一點半準時熄燈。"
        case .skeleton: "曾經是熬夜蝠手下的骷髏兵，看你天天早睡，終於決定改邪歸正。"
        case .knight: "王城的見習騎士，立志走遍元氣大陸。你走的每一步，都是牠的修行。"
        case .dwarf: "王城的矮人鐵匠，最欣賞腳踏實地的人。走滿一萬步的日子，牠會為你打一枚勳章。"
        case .dragon: "傳說中守護王城的龍寶寶。只有連續三週走好、睡好的冒險者，才見得到牠。"
        case .frog: "聖泉湖的青蛙王子。頭上的皇冠是湖水做的，喝水不夠的日子就會變得霧霧的。"
        case .mermaid: "住在湖底的小人魚，只有連續好幾天把水喝夠，湖水清到看得見底，牠才會浮上來打招呼。"
        case .unicorn: "傳說中聖泉的守護者。牠的角一碰到水，整座湖都會發光——前提是你也好好喝水。"
        case .owl: "靜心塔的貓頭鷹，一整天只做一件事：慢慢吸氣、慢慢吐氣。"
        case .monk: "塔裡修行的見習僧侶。牠說一分鐘的呼吸，可以把一整天的焦慮霧吹散。"
        case .gargoyle: "靜心塔頂的石像鬼，一動也不動地守了一千年，是全大陸最冷靜的精靈。"
        case .fox: "開拓區的斥候狐狸，專門探路。你第一次出發冒險，牠就悄悄跟在後面了。"
        case .bard: "到處唱歌的吟遊詩人。迷霧散開的地方，都會被牠寫成一首新的歌。"
        case .archer: "開拓區的精靈弓箭手，眼睛很好，最欣賞一口氣走很遠的冒險者。"
        case .nian: "過年才出現的年獸寶寶。其實牠不可怕，只是太愛熱鬧，吃飽了會想跟你出去走走。"
        case .zongzi: "端午節的粽子精靈，身上的繩子綁得緊緊的，說是準備好要划龍舟了。"
        case .goldfish: "夏日祭撈到的小金魚。天氣熱的時候，牠最在意你有沒有喝夠水。"
        case .rabbit: "中秋從月亮跳下來的玉兔。賞完月就催大家早點睡，說月亮明天還在。"
        case .pumpkin: "萬聖節的南瓜精靈，最怕熬夜的人——因為熬夜的人比牠還像鬼。"
        case .snowman: "聖誕節才堆得出來的小雪人，最喜歡看雪地上一長串的腳印。"
        }
    }

    var shinyLore: String {
        region == .festival
            ? "閃光\(title)！節慶的每一天都做到的冒險者才見得到。"
            : "傳說中的閃光\(title)，全身閃閃發亮，只出現在最堅持的冒險者身邊。"
    }

    /// 喚醒後一起學會的回話風格
    var unlocksStyle: CompanionStyle? {
        switch self {
        case .cat: .cat
        case .dog: .dog
        case .parrot: .bird
        default: nil
        }
    }
}

// MARK: - 收集進度

/// 精靈收集：從開始這天起計算步數與睡眠成就，喚醒過就永遠保留
@MainActor
final class SpiritCollection: ObservableObject {
    static let shared = SpiritCollection()

    /// 收集 5 隻後開放 emoji 造型
    static let emojiSkinUnlockCount = 5

    struct State: Codable {
        var start: Date
        var unlocked: [String: Date]
        var shiny: [String: Date] = [:]
        /// 還沒看過慶祝畫面的精靈；閃光版在名字後面加「*」
        var pending: [String] = []
        /// 上次算出來的進度（畫面顯示用）
        var progress: [String: Double] = [:]
        var shinyProgress: [String: Double] = [:]

        init(start: Date, unlocked: [String: Date]) {
            self.start = start
            self.unlocked = unlocked
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try container.decode(Date.self, forKey: .start)
            unlocked = try container.decode([String: Date].self, forKey: .unlocked)
            shiny = try container.decodeIfPresent([String: Date].self, forKey: .shiny) ?? [:]
            pending = try container.decodeIfPresent([String].self, forKey: .pending) ?? []
            progress = try container.decodeIfPresent([String: Double].self, forKey: .progress) ?? [:]
            shinyProgress = try container.decodeIfPresent([String: Double].self, forKey: .shinyProgress) ?? [:]
        }
    }

    /// 慶祝畫面要顯示的一隻精靈
    struct Celebration: Identifiable, Equatable {
        let skin: CompanionSkin
        let shiny: Bool
        var id: String { skin.rawValue + (shiny ? "*" : "") }
    }

    private static let key = "spiritCollection"
    /// 已解鎖的精靈另外存一份字串陣列，畫面每 0.5 秒重畫時讀這個就好，不用解整份 JSON（閃光版加「*」）
    private static let unlockedKey = "spiritUnlocked"

    @Published private(set) var state: State
    /// 昨晚的睡眠、今天的步數（圖鑑頁顯示用）
    @Published private(set) var lastNight: SleepNight?
    @Published private(set) var todaySteps: Double = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State(start: Date.now.startOfDay, unlocked: [CompanionSkin.onigiri.rawValue: .now])
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedSpirits") { seedForScreenshots() }
        #endif
        save()
        enforceUnlockedChoices()
    }

    #if DEBUG
    /// 開發用：模擬器截圖檢查畫面時，放一些已喚醒、閃光、進行中的精靈
    private func seedForScreenshots() {
        let day = Date.now.adding(days: -1)
        state = State(start: Date.now.adding(days: -20).startOfDay,
                      unlocked: Dictionary(uniqueKeysWithValues: ["onigiri", "boba", "bun", "dog", "cat", "parrot", "slime", "dragon",
                                                                  "frog", "owl", "fox", "archer", "rabbit"].map { ($0, day) }))
        state.shiny = ["cat": day, "dragon": .now, "rabbit": day]
        state.progress = ["goblin": 9, "mimic": 8200, "egg": 2, "griffin": 6, "mushroom": 1.5, "ghost": 1, "wizard": 5,
                          "skeleton": 4, "knight": 88000, "dwarf": 3, "mermaid": 3, "unicorn": 8, "monk": 2, "gargoyle": 4,
                          "bard": 0.6, "pumpkin": 1, "nian": 0, "snowman": 0]
        state.shinyProgress = ["boba": 8100, "bun": 3, "dog": 70000, "onigiri": 8]
        if ProcessInfo.processInfo.arguments.contains("-celebrate") { state.pending = ["dragon*"] }
    }
    #endif

    // MARK: 查詢（不用等 async，畫面直接讀）

    nonisolated static func isUnlocked(_ skin: CompanionSkin) -> Bool {
        skin == .onigiri || unlockedNames().contains(skin.rawValue)
    }

    nonisolated static func isShinyUnlocked(_ skin: CompanionSkin) -> Bool {
        unlockedNames().contains(skin.rawValue + "*")
    }

    nonisolated static func unlockedCount() -> Int {
        max(unlockedNames().filter { !$0.hasSuffix("*") }.count, 1)
    }

    private nonisolated static func unlockedNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: unlockedKey) ?? [CompanionSkin.onigiri.rawValue]
    }

    nonisolated static func isStyleUnlocked(_ style: CompanionStyle) -> Bool {
        guard let skin = CompanionSkin.allCases.first(where: { $0.unlocksStyle == style }) else { return true }
        return isUnlocked(skin)
    }

    nonisolated static var emojiSkinsUnlocked: Bool { unlockedCount() >= emojiSkinUnlockCount }

    func unlockedDate(_ skin: CompanionSkin, shiny: Bool = false) -> Date? {
        shiny ? state.shiny[skin.rawValue] : state.unlocked[skin.rawValue]
    }

    /// 目前進度（已解鎖的直接算滿）
    func progress(_ skin: CompanionSkin, shiny: Bool = false) -> Double {
        let requirement = shiny ? skin.shinyRequirement : skin.requirement
        if unlockedDate(skin, shiny: shiny) != nil { return requirement.target }
        let value = (shiny ? state.shinyProgress : state.progress)[skin.rawValue] ?? 0
        return min(value, requirement.target)
    }

    var unlockedTotal: Int { state.unlocked.count }
    var shinyTotal: Int { state.shiny.count }

    var celebration: Celebration? {
        guard let first = state.pending.first else { return nil }
        let shiny = first.hasSuffix("*")
        guard let skin = CompanionSkin(rawValue: shiny ? String(first.dropLast()) : first) else { return nil }
        return Celebration(skin: skin, shiny: shiny)
    }

    func dismissCelebration() {
        guard !state.pending.isEmpty else { return }
        state.pending.removeFirst()
        save()
    }

    // MARK: 計算

    /// App 回到前景時呼叫：讀「健康」的步數與睡眠，算進度、喚醒精靈
    func evaluate() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedSpirits") { return }
        #endif
        let health = HealthKitManager.shared
        let start = state.start
        let steps = await health.dailySteps(from: start, to: .now)
        let nights = await health.allSleepNights(from: start, to: .now)
        todaySteps = steps[Date.now.startOfDay] ?? 0
        lastNight = nights[Date.now.startOfDay]

        let days = Self.days(from: start, to: .now)
        let totals = LogService.shared.dayTotals(from: start, days: days.count)
        let waterGoal = AppSettings.waterGoal
        let routes = RouteStore.shared.routes.filter { $0.start >= start }
        let data = Record(days: days, steps: steps, nights: nights,
                          waterDays: Set(totals.filter { waterGoal > 0 && $0.value.water >= waterGoal }.keys),
                          breathDays: StressStore.breathingDays(), calmDays: StressStore.calmDays(),
                          routeCount: Double(routes.count), longestRoute: routes.map(\.distance).max() ?? 0,
                          fogArea: WorldFogStore.shared.clearedArea)
        var newly: [String] = []
        // 收集數量的條件要等其他精靈算完，所以跑兩輪
        for _ in 0..<2 {
            for skin in CompanionSkin.dexOrder {
                let value = data.value(of: skin.requirement, collected: state.unlocked.count)
                state.progress[skin.rawValue] = value
                if state.unlocked[skin.rawValue] == nil, value >= skin.requirement.target {
                    state.unlocked[skin.rawValue] = .now
                    newly.append(skin.rawValue)
                }
                let shinyValue = data.value(of: skin.shinyRequirement, collected: state.unlocked.count)
                state.shinyProgress[skin.rawValue] = shinyValue
                if state.unlocked[skin.rawValue] != nil, state.shiny[skin.rawValue] == nil,
                   shinyValue >= skin.shinyRequirement.target {
                    state.shiny[skin.rawValue] = .now
                    newly.append(skin.rawValue + "*")
                }
            }
        }
        state.pending.append(contentsOf: newly)
        save()
        if let first = celebration, !newly.isEmpty {
            CompanionStore.shared.show("\(first.shiny ? "閃光" : "")\(first.skin.title)醒過來了！")
        }
    }

    /// 一段期間的步數與睡眠，用來算各種條件
    private struct Record {
        let days: [Date]
        let steps: [Date: Double]
        let nights: [Date: SleepNight]
        /// 喝滿目標的日子（當天 0:00）
        let waterDays: Set<Date>
        /// 做過一分鐘呼吸、精神力夠高的日子（dayKey）
        let breathDays: Set<String>
        let calmDays: Set<String>
        let routeCount: Double
        let longestRoute: Double
        let fogArea: Double

        func value(of requirement: SpiritRequirement, collected: Int) -> Double {
            switch requirement {
            case .starter:
                return 1
            case .collect:
                return Double(collected)
            case .stepsInDay:
                return steps.values.max() ?? 0
            case .totalSteps:
                return steps.values.reduce(0, +)
            case .stepDays(_, let threshold):
                return Double(steps.values.filter { $0 >= threshold }.count)
            case .stepStreak(_, let threshold):
                return bestRun { (steps[$0] ?? 0) >= threshold ? 1 : nil }
            case .sleepNights(_, let hours):
                return nights.values.filter { $0.hours >= hours }.reduce(0) { $0 + $1.weight }
            case .sleepStreak(_, let hours):
                return bestRun { day in nights[day].flatMap { $0.hours >= hours ? $0.weight : nil } }
            case .earlyRiser(_, let before, let hours):
                return nights.values.filter { $0.wakeMinutes < before && $0.hours >= hours }.reduce(0) { $0 + $1.weight }
            case .earlyStreak(_, let before, let hours):
                return bestRun { day in
                    nights[day].flatMap { $0.wakeMinutes < before && $0.hours >= hours ? $0.weight : nil }
                }
            case .earlySleep(_, let before, let hours):
                return nights.values.filter { $0.isAsleep(before: before) && $0.hours >= hours }.reduce(0) { $0 + $1.weight }
            case .earlySleepStreak(_, let before, let hours):
                return bestRun { day in
                    nights[day].flatMap { $0.isAsleep(before: before) && $0.hours >= hours ? $0.weight : nil }
                }
            case .perfectStreak(_, let threshold, let hours):
                return bestRun { day in
                    guard (steps[day] ?? 0) >= threshold, let night = nights[day], night.hours >= hours else { return nil }
                    return night.weight
                }
            case .waterDays:
                return Double(waterDays.count)
            case .waterStreak:
                return bestRun { waterDays.contains($0) ? 1 : nil }
            case .breathDays:
                return Double(breathDays.count)
            case .breathStreak:
                return bestRun { breathDays.contains($0.dayKey) ? 1 : nil }
            case .calmDays:
                return Double(calmDays.count)
            case .routes:
                return routeCount
            case .longRoute:
                return longestRoute / 1000
            case .fogArea:
                return fogArea
            case .festival(let festival, _):
                // 每一年的活動期間分開算，取最好的一次
                guard let first = days.first, let last = days.last else { return 0 }
                return festival.windows(from: first, to: last.adding(days: 1)).map { window in
                    days.filter { window.contains($0) }.reduce(0.0) { total, day in
                        total + (festivalWeight(festival.habit, on: day) ?? 0)
                    }
                }.max() ?? 0
            }
        }

        /// 節慶那天有沒有做到（手動補記的睡眠算半天）
        private func festivalWeight(_ habit: FestivalHabit, on day: Date) -> Double? {
            switch habit {
            case .steps(let threshold): (steps[day] ?? 0) >= threshold ? 1 : nil
            case .water: waterDays.contains(day) ? 1 : nil
            case .sleep(let hours): nights[day].flatMap { $0.hours >= hours ? $0.weight : nil }
            case .earlySleep(let before, let hours):
                nights[day].flatMap { $0.isAsleep(before: before) && $0.hours >= hours ? $0.weight : nil }
            }
        }

        /// 最長連續天數（今天還沒達成不算斷掉，只是還沒加上去）
        private func bestRun(_ weight: (Date) -> Double?) -> Double {
            var best = 0.0, current = 0.0
            for (index, day) in days.enumerated() {
                if let value = weight(day) {
                    current += value
                    best = max(best, current)
                } else if index < days.count - 1 {
                    current = 0
                }
            }
            return best
        }
    }

    private static func days(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var day = start.startOfDay
        while day <= end {
            result.append(day)
            day = day.adding(days: 1)
        }
        return result
    }

    /// 選好帶在身邊的精靈
    func choose(_ skin: CompanionSkin, shiny: Bool) {
        guard state.unlocked[skin.rawValue] != nil else { return }
        UserDefaults.standard.set(skin.rawValue, forKey: SettingKey.companionSkin)
        UserDefaults.standard.set(shiny && state.shiny[skin.rawValue] != nil, forKey: SettingKey.companionShiny)
        // 手錶上的小夥伴跟著換
        PhoneConnectivity.shared.pushSummary()
    }

    /// 目前選的造型或回話風格還沒解鎖時，換回飯糰精靈、激勵風格
    private func enforceUnlockedChoices() {
        let defaults = UserDefaults.standard
        let skin = defaults.string(forKey: SettingKey.companionSkin) ?? ""
        if let preset = CompanionSkin(rawValue: skin), state.unlocked[preset.rawValue] == nil {
            defaults.set(CompanionSkin.onigiri.rawValue, forKey: SettingKey.companionSkin)
            defaults.set(false, forKey: SettingKey.companionShiny)
        } else if skin.hasPrefix(CompanionLook.emojiPrefix), state.unlocked.count < Self.emojiSkinUnlockCount {
            defaults.set(CompanionSkin.onigiri.rawValue, forKey: SettingKey.companionSkin)
        }
        if let style = CompanionStyle(rawValue: defaults.string(forKey: SettingKey.companionStyle) ?? ""),
           let skin = CompanionSkin.allCases.first(where: { $0.unlocksStyle == style }),
           state.unlocked[skin.rawValue] == nil {
            defaults.set(CompanionStyle.motivating.rawValue, forKey: SettingKey.companionStyle)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        let names = Array(state.unlocked.keys) + state.shiny.keys.map { $0 + "*" }
        UserDefaults.standard.set(names.sorted(), forKey: Self.unlockedKey)
    }
}
