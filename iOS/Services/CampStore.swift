import Foundation
import SwiftUI

// MARK: - 營地建築

enum CampBuilding: String, CaseIterable, Identifiable {
    case home, firePit, garden, well, tower, spiritHouse, flowers, banner, lamp

    var id: String { rawValue }

    /// 最高等級（家從帳篷 Lv1 開始）
    var maxLevel: Int {
        switch self {
        case .home: 3
        case .firePit, .garden, .well, .tower, .spiritHouse: 2
        case .flowers, .banner, .lamp: 1
        }
    }

    /// 升到第 n 級要花的元氣幣（index 0 是蓋到 Lv1）
    var costs: [Int] {
        switch self {
        case .home: [0, 60, 150]
        case .firePit: [40, 100]
        case .garden: [50, 120]
        case .well: [50, 120]
        case .tower: [80, 180]
        case .spiritHouse: [100, 200]
        case .flowers: [30]
        case .banner: [30]
        case .lamp: [40]
        }
    }

    func title(level: Int) -> String {
        switch self {
        case .home: ["帳篷", "帳篷", "小木屋", "石屋"][min(max(level, 0), 3)]
        case .firePit: "營火台"
        case .garden: "菜園"
        case .well: "聖泉"
        case .tower: "瞭望台"
        case .spiritHouse: "精靈小屋"
        case .flowers: "花圃"
        case .banner: "旗幟"
        case .lamp: "路燈"
        }
    }

    var detail: String {
        switch self {
        case .home: "冒險者的家。從帳篷開始，慢慢蓋成小木屋、石屋。"
        case .firePit: "晚上大家圍著取暖、聊今天的冒險。"
        case .garden: "種滿蔬菜的小菜園，精靈們最愛來這裡散步。"
        case .well: "清涼的泉水，提醒大家記得喝水。"
        case .tower: "站在上面可以看到遠方的王城。"
        case .spiritHouse: "精靈的家。等級越高，越多精靈會出來營地散步。"
        case .flowers: "五顏六色的小花。"
        case .banner: "冒險隊的旗子，風一吹就飄起來。"
        case .lamp: "晚上替回家的冒險者照路。"
        }
    }

    func art(level: Int) -> PixelArt {
        switch self {
        case .home: level >= 3 ? .campStone : level == 2 ? .campCabin : .campTent
        case .firePit: .campfire
        case .garden: .campGarden
        case .well: .campWell
        case .tower: .campTower
        case .spiritHouse: .campSpiritHouse
        case .flowers: .campFlowers
        case .banner: .campBanner
        case .lamp: .campLamp
        }
    }
}

// MARK: - 精靈特性

/// 出戰精靈的小加成（羈絆 Lv2 起生效）
enum SpiritPerk {
    /// 某種元氣幣有拿到時多給幾枚
    case bonus(CoinSource, Int)
    /// 7:30 前起床且睡滿 6 小時，夢境能量多給
    case earlyWake(Int)
    /// 在某時間前睡著且睡滿 6 小時，夢境能量多給
    case earlySleep(before: Int, Int)
    /// 單日走滿幾步多給
    case bigWalk(steps: Double, Int)
    /// 旅途見聞每天的上限提高
    case journeyCap(Int)
    /// 白天的元氣幣多幾成
    case percentDay(Int)

    var text: String {
        switch self {
        case .bonus(let source, let coins): "\(source.title)的元氣幣 +\(coins)"
        case .earlyWake(let coins): "7:30 前起床，夢境能量 +\(coins)"
        case .earlySleep(let before, let coins): "\(SpiritRequirement.clock(before)) 前睡著，夢境能量 +\(coins)"
        case .bigWalk(let steps, let coins): "單日走滿 \(steps.formatted()) 步，元氣幣 +\(coins)"
        case .journeyCap(let coins): "旅途見聞每天多 \(coins) 枚上限"
        case .percentDay(let percent): "白天的元氣幣全部多 \(percent)%"
        }
    }
}

extension CompanionSkin {
    var perk: SpiritPerk {
        switch self {
        case .onigiri: .bonus(.meals, 2)
        case .boba: .bonus(.water, 2)
        case .bun: .bonus(.sleep, 2)
        case .dog: .bonus(.steps, 2)
        case .goblin: .bonus(.steps, 3)
        case .mimic: .bonus(.event, 3)
        case .egg: .earlyWake(2)
        case .parrot: .earlyWake(3)
        case .griffin: .journeyCap(2)
        case .cat: .bonus(.sleep, 3)
        case .slime: .bonus(.water, 3)
        case .mushroom: .bonus(.sleep, 2)
        case .ghost: .earlySleep(before: 24 * 60, 2)
        case .wizard: .earlySleep(before: 23 * 60 + 30, 3)
        case .skeleton: .bonus(.protein, 2)
        case .knight: .bonus(.steps, 3)
        case .dwarf: .bigWalk(steps: 10000, 5)
        case .dragon: .percentDay(10)
        case .frog: .bonus(.water, 3)
        case .mermaid: .bonus(.water, 4)
        case .unicorn: .bonus(.water, 5)
        case .owl: .earlySleep(before: 23 * 60, 3)
        case .monk: .earlyWake(3)
        case .gargoyle: .bonus(.sleep, 3)
        case .fox: .bigWalk(steps: 8000, 3)
        case .bard: .journeyCap(3)
        case .archer: .bigWalk(steps: 12000, 6)
        case .nian: .bonus(.meals, 3)
        case .zongzi: .bonus(.steps, 3)
        case .goldfish: .bonus(.water, 3)
        case .rabbit: .bonus(.sleep, 3)
        case .pumpkin: .earlySleep(before: 24 * 60, 3)
        case .snowman: .bonus(.steps, 3)
        }
    }

    /// 羈絆升級時解鎖的小故事（Lv3、Lv5）
    var bondStories: [String] {
        switch self {
        case .onigiri: ["飯糰精靈偷偷說：其實第一天看到你的時候，牠就決定要跟你走了。",
                        "「喂，冒險者……謝謝你一直沒丟下我。」海苔都紅了。"]
        case .boba: ["珍奶精靈說牠的珍珠是用腳步聲做的，你走越多，牠的珍珠越Q。",
                     "牠把最圓的一顆珍珠送給你：「這是我們一起走過的路。」"]
        case .bun: ["小籠包說，睡飽的人身上有一種香香的蒸氣味。",
                    "牠把蒸籠讓出一半給你：「今晚一起好好睡吧。」"]
        case .dog: ["小狗記得你走過的每一條路，連轉角的電線桿都記得。",
                    "牠叼來一片葉子，是你們第一次散步時經過的那棵樹。"]
        case .goblin: ["哥布林承認，牠以前也是一坐就起不來的類型。",
                       "「是你讓我知道，每天走一點就夠了。」牠第一次笑出聲。"]
        case .mimic: ["寶箱怪說牠最怕被當成普通箱子坐上去。",
                      "牠打開蓋子，裡面放著你每天的冒險紀錄——牠一直幫你收著。"]
        case .egg: ["荷包蛋說，早上的陽光是一天裡最好吃的調味料。",
                    "「明天也一起看日出吧！」蛋黃亮晶晶的。"]
        case .parrot: ["小鳥每天第一個醒來，因為想第一個跟你說早安。",
                       "牠學會了你的名字，每天早上都會叫一遍。"]
        case .griffin: ["獅鷲說，從天上看，你走過的路像一條發光的線。",
                        "牠讓你坐上背：「下次，我們一起飛去還沒去過的地方。」"]
        case .cat: ["貓咪說，睡覺是世界上最重要的工作，你終於懂了。",
                    "牠窩在你腳邊打呼，好像在說：這裡就是牠的家。"]
        case .slime: ["水滴史萊姆說，牠是由好幾個好眠的夜晚凝成的。",
                      "牠輕輕貼在你手上，涼涼的，像清晨的露水。"]
        case .mushroom: ["蘑菇怪說，睡飽的夢是彩色的，熬夜的夢是灰色的。",
                         "牠分給你一個彩色的夢：「今晚帶著它睡吧。」"]
        case .ghost: ["小幽靈其實很怕黑，所以最喜歡早睡的人。",
                      "「有你在，晚上就不可怕了。」牠變得有點透明，是開心的那種。"]
        case .wizard: ["見習巫師說，早睡這個魔法練了好久才學會。",
                       "牠把魔法書的第一頁送給你，上面寫著：「晚安，是最強的咒語。」"]
        case .skeleton: ["骷髏兵說，當初跟著熬夜蝠，是因為晚上太寂寞。",
                         "「現在我有你們了。」牠的骨頭喀啦喀啦響，是在笑。"]
        case .knight: ["見習騎士每天擦亮盔甲，因為你走的每一步都是牠的修行。",
                       "牠單膝跪下：「冒險者，請讓我守護你的旅程。」"]
        case .dwarf: ["矮人鐵匠為你打了一枚勳章，上面刻著你走過的公里數。",
                      "「腳踏實地的人，最值得尊敬。」牠用力拍了拍你的肩。"]
        case .dragon: ["龍寶寶說，牠在王城等了好久，才等到走好、睡好的冒險者。",
                       "牠在你身邊蜷成一團：「以後，換我來守護你。」"]
        case .frog: ["青蛙王子說，牠的皇冠其實是一滴很大的露水。",
                     "「多虧你每天喝水，湖水才這麼清。」牠把皇冠借你戴了一下。"]
        case .mermaid: ["小人魚說，湖底能聽見你每一次倒水的聲音。",
                        "牠送你一片會發光的鱗片：「口渴的時候，看看它。」"]
        case .unicorn: ["獨角獸很少讓人靠近，但牠會在你喝水的時候悄悄走過來。",
                        "牠低下頭，讓你摸摸牠的角：「聖泉會一直為你湧出來。」"]
        case .owl: ["貓頭鷹說，慢慢吐氣的時候，心裡的霧就會跟著散掉。",
                    "牠陪你在塔頂看星星，一句話也沒說，卻很安心。"]
        case .monk: ["見習僧侶說，牠也常常分心，所以才要每天練習。",
                     "「今天也辛苦了。」牠替你敲了一下塔頂的鐘，聲音好輕。"]
        case .gargoyle: ["石像鬼說，一千年來牠學到最重要的事：急也沒有用。",
                         "牠第一次動了動翅膀：「有你在，我不用再一個人守塔了。」"]
        case .fox: ["斥候狐狸說，牠最喜歡跟在你後面，看你發現新的小巷。",
                    "牠把一張手繪地圖塞給你，上面畫滿了你走過的路。"]
        case .bard: ["吟遊詩人把你走過的街道編成了一首歌，還押韻。",
                     "「冒險者的歌，要一起走才寫得完。」牠彈了最後一個音。"]
        case .archer: ["精靈弓箭手說，牠在很遠的地方就看到你走過來了。",
                       "牠把一支羽毛箭送給你：「下次，我們走得更遠一點。」"]
        case .nian: ["年獸寶寶說，牠不是來嚇人的，只是想湊熱鬧。",
                     "牠咬著一個紅包跑過來：「明年過年，我們還要一起！」"]
        case .zongzi: ["粽子精靈說，牠身上的繩子綁得越緊，力氣越大。",
                       "牠把繩子解開一點點：「跟你在一起，可以放鬆了。」"]
        case .goldfish: ["小金魚說，夏天最重要的就是水，牠比誰都懂。",
                         "牠在水裡吐了一個愛心形狀的泡泡給你。"]
        case .rabbit: ["玉兔說，月亮上也有一座營地，但沒有這裡熱鬧。",
                       "牠分你半個月餅：「月亮每年都會圓，我也每年都會來。」"]
        case .pumpkin: ["南瓜精靈的臉是自己刻的，牠說笑臉比較好看。",
                        "「今晚也早點睡吧。」牠把燈火調得暗暗的。"]
        case .snowman: ["小雪人說，牠最喜歡數雪地上的腳印。",
                        "牠把圍巾分你一半：「就算天氣熱了，我也會記得你。」"]
        }
    }

    /// 目前帶著的精靈（emoji 造型沒有特性）
    static var active: CompanionSkin? {
        let defaults = UserDefaults.standard
        let skin = defaults.string(forKey: SettingKey.companionSkin) ?? ""
        if skin.hasPrefix(CompanionLook.emojiPrefix), SpiritCollection.emojiSkinsUnlocked { return nil }
        if let preset = CompanionSkin(rawValue: skin), SpiritCollection.isUnlocked(preset) { return preset }
        if let animal = CompanionStyle(rawValue: defaults.string(forKey: SettingKey.companionStyle) ?? "")?.animalSkin,
           SpiritCollection.isUnlocked(animal) { return animal }
        return .onigiri
    }
}

// MARK: - 營地、羈絆、稱號

@MainActor
final class CampStore: ObservableObject {
    static let shared = CampStore()

    /// 羈絆各等級需要的點數（Lv1–5）
    static let bondThresholds = [0, 30, 90, 200, 400]
    /// 特性從羈絆幾級開始生效
    static let perkBondLevel = 2

    private struct State: Codable {
        var levels: [String: Int] = [CampBuilding.home.rawValue: 1]
        var bonds: [String: Int] = [:]
        /// 蓋過的節慶裝飾（Festival 的 rawValue）
        var decorations: [String] = []

        init(levels: [String: Int] = [CampBuilding.home.rawValue: 1], bonds: [String: Int] = [:], decorations: [String] = []) {
            self.levels = levels
            self.bonds = bonds
            self.decorations = decorations
        }

        // 新欄位用 decodeIfPresent，更新版本時營地不會被重設
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            levels = try container.decodeIfPresent([String: Int].self, forKey: .levels) ?? [CampBuilding.home.rawValue: 1]
            bonds = try container.decodeIfPresent([String: Int].self, forKey: .bonds) ?? [:]
            decorations = try container.decodeIfPresent([String].self, forKey: .decorations) ?? []
        }
    }

    private static let key = "campState"
    @Published private var state: State

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
        #if DEBUG
        // 開發用：-seedCamp 放幾棟建築和羈絆來檢查畫面
        if ProcessInfo.processInfo.arguments.contains("-seedCamp") {
            state = State(levels: ["home": 2, "firePit": 1, "garden": 2, "well": 1, "flowers": 1, "spiritHouse": 1],
                          bonds: ["cat": 120, "onigiri": 40, "dog": 12], decorations: ["midAutumn"])
        }
        #endif
    }

    // MARK: 建築

    func level(_ building: CampBuilding) -> Int { state.levels[building.rawValue] ?? 0 }

    /// 下一級的費用；已經滿級回傳 nil
    func nextCost(_ building: CampBuilding) -> Int? {
        let level = level(building)
        return level < building.maxLevel ? building.costs[level] : nil
    }

    var campLevel: Int { CampBuilding.allCases.reduce(0) { $0 + level($1) } }

    /// 營地裡散步的精靈數量：精靈小屋 Lv1 6 隻、滿級 12 隻（再多營地就太擠了）
    var wanderLimit: Int {
        switch level(.spiritHouse) {
        case 0: 3
        case 1: 6
        default: 12
        }
    }

    func build(_ building: CampBuilding) -> Bool {
        guard let cost = nextCost(building), AdventureStore.shared.spend(cost) else { return false }
        state.levels[building.rawValue] = level(building) + 1
        save()
        return true
    }

    // MARK: 節慶裝飾

    func hasDecoration(_ festival: Festival) -> Bool { state.decorations.contains(festival.rawValue) }

    /// 只有那個節慶期間能蓋
    func buildDecoration(_ festival: Festival) -> Bool {
        guard !hasDecoration(festival), Festival.active() == festival,
              AdventureStore.shared.spend(festival.decorationCost) else { return false }
        state.decorations.append(festival.rawValue)
        save()
        return true
    }

    // MARK: 羈絆

    func bondPoints(_ skin: CompanionSkin) -> Int { state.bonds[skin.rawValue] ?? 0 }

    func bondLevel(_ skin: CompanionSkin) -> Int {
        let points = bondPoints(skin)
        return (Self.bondThresholds.lastIndex { points >= $0 } ?? 0) + 1
    }

    /// 在這一級裡的進度（目前、需要）；滿級回傳 nil
    func bondProgress(_ skin: CompanionSkin) -> (current: Int, needed: Int)? {
        let level = bondLevel(skin)
        guard level < Self.bondThresholds.count else { return nil }
        let from = Self.bondThresholds[level - 1], to = Self.bondThresholds[level]
        return (bondPoints(skin) - from, to - from)
    }

    func perkActive(_ skin: CompanionSkin) -> Bool { bondLevel(skin) >= Self.perkBondLevel }

    /// 目前帶著的精靈、而且特性已經生效
    var activePerk: (skin: CompanionSkin, perk: SpiritPerk)? {
        guard let skin = CompanionSkin.active, perkActive(skin) else { return nil }
        return (skin, skin.perk)
    }

    /// 領到元氣幣時，帶著的精靈一起累積羈絆
    func addBond(_ points: Int) {
        guard points > 0, let skin = CompanionSkin.active else { return }
        let before = bondLevel(skin)
        state.bonds[skin.rawValue, default: 0] += points
        save()
        let after = bondLevel(skin)
        if after > before {
            CompanionStore.shared.show("和\(skin.title)的羈絆升到 Lv.\(after) 了！")
        }
    }

    var maxBondLevel: Int { CompanionSkin.dexOrder.map(bondLevel).max() ?? 1 }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        objectWillChange.send()
    }
}

// MARK: - 稱號

enum HeroTitle: String, CaseIterable, Identifiable {
    case novice, walker, dawn, dreamGuard, moonMage, royalKnight, collector, master, shinyHunter,
         campOwner, rich, bondFriend, steady, explorer, lakeGuard, calmSage, pioneer, festivalFan, voyager

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novice: "見習冒險者"
        case .walker: "步道行者"
        case .dawn: "晨光使者"
        case .dreamGuard: "夢境守護者"
        case .moonMage: "月影法師"
        case .royalKnight: "王城騎士"
        case .collector: "精靈收藏家"
        case .master: "精靈大師"
        case .shinyHunter: "閃光獵人"
        case .campOwner: "營地主人"
        case .rich: "元氣富翁"
        case .bondFriend: "精靈摯友"
        case .steady: "不倒翁冒險者"
        case .explorer: "開拓者"
        case .lakeGuard: "聖泉守護者"
        case .calmSage: "靜心賢者"
        case .pioneer: "開拓先鋒"
        case .festivalFan: "節慶達人"
        case .voyager: "大陸旅人"
        }
    }

    var condition: String {
        switch self {
        case .novice: "一開始就有"
        case .walker: "旅程累計 20 公里"
        case .dawn: "喚醒晨光丘的三隻精靈"
        case .dreamGuard: "喚醒夢之森的三隻精靈"
        case .moonMage: "喚醒月影沼澤的三隻精靈"
        case .royalKnight: "旅程抵達王城"
        case .collector: "喚醒 9 隻精靈"
        case .master: "喚醒全部 \(CompanionSkin.regularOrder.count) 隻一般精靈"
        case .shinyHunter: "取得 3 隻閃光精靈"
        case .campOwner: "營地等級 10"
        case .rich: "累計獲得 500 元氣幣"
        case .bondFriend: "任一隻精靈羈絆 Lv.5"
        case .steady: "連續記錄 14 天"
        case .explorer: "開拓地圖 100 格"
        case .lakeGuard: "喚醒聖泉湖的三隻精靈"
        case .calmSage: "喚醒靜心塔的三隻精靈"
        case .pioneer: "喚醒開拓區的三隻精靈"
        case .festivalFan: "喚醒 3 隻節慶精靈"
        case .voyager: "旅程抵達開拓區（185 公里）"
        }
    }

    @MainActor
    var isUnlocked: Bool {
        let spirits = SpiritCollection.shared
        let journey = JourneyStore.shared
        func region(_ region: SpiritRegion) -> Bool { region.spirits.allSatisfy { spirits.unlockedDate($0) != nil } }
        switch self {
        case .novice: return true
        case .walker: return journey.kilometers >= 20
        case .dawn: return region(.dawnHill)
        case .dreamGuard: return region(.dreamForest)
        case .moonMage: return region(.moonMarsh)
        case .royalKnight: return journey.isReached(.royalCity)
        case .collector: return spirits.unlockedTotal >= 9
        case .master: return CompanionSkin.regularOrder.allSatisfy { spirits.unlockedDate($0) != nil }
        case .shinyHunter: return spirits.shinyTotal >= 3
        case .campOwner: return CampStore.shared.campLevel >= 10
        case .rich: return AdventureStore.shared.lifetimeEarned >= 500
        case .bondFriend: return CampStore.shared.maxBondLevel >= 5
        case .steady: return LogService.shared.streak() >= 14
        case .explorer: return RouteStore.shared.cellCount >= 100
        case .lakeGuard: return region(.sacredLake)
        case .calmSage: return region(.calmTower)
        case .pioneer: return region(.frontier)
        case .festivalFan: return SpiritRegion.festival.spirits.filter { spirits.unlockedDate($0) != nil }.count >= 3
        case .voyager: return journey.isReached(.frontier)
        }
    }

    static let storageKey = "heroTitle"
}
