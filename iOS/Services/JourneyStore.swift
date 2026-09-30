import Foundation
import SwiftUI

// MARK: - 旅程路線

extension SpiritRegion {
    /// 大陸地圖上的旅程站點（聖泉湖、靜心塔、開拓區、節慶廣場靠生活習慣開放，不在旅程路線上）
    static let journeyStops: [SpiritRegion] = [.riceVillage, .trailValley, .dawnHill, .dreamForest, .moonMarsh, .royalCity]

    /// 從米糧村出發，累計走幾公里會抵達
    var journeyKm: Double {
        switch self {
        case .riceVillage: 0
        case .trailValley: 8
        case .dawnHill: 20
        case .dreamForest: 36
        case .moonMarsh: 56
        case .royalCity: 80
        case .sacredLake, .calmTower, .frontier, .festival: 0
        }
    }

    /// 地圖上的地標
    var landmark: PixelArt {
        switch self {
        case .riceVillage: .landmarkHouse
        case .trailValley: .landmarkMountain
        case .dawnHill: .landmarkDawn
        case .dreamForest: .landmarkTree
        case .moonMarsh: .landmarkMarsh
        case .royalCity: .landmarkCastle
        case .sacredLake, .calmTower, .frontier, .festival: art
        }
    }

    /// 石碑上的話（旅途見聞）
    var sayings: [String] {
        switch self {
        case .riceVillage: ["村口的石碑寫著：「吃飯要專心，才吃得出飽。」",
                            "田埂上的稻草人說：每一口都值得好好咀嚼。",
                            "米倉的老爺爺說：早餐吃得好，一整天都有力氣。"]
        case .trailValley: ["石碑寫著：「一次走不遠，每天走一點。」",
                            "山谷的回音說：累了就停一下，喝口水再走。",
                            "路邊的樹上刻著：走過的路，都會變成你的力氣。"]
        case .dawnHill: ["石碑寫著：「早起的人，看得到第一道光。」",
                         "晨光丘的風說：起床先喝一杯水，身體會醒得更快。",
                         "山坡上的公雞說：太陽起床的時候，你也起床吧。"]
        case .dreamForest: ["石碑寫著：「睡飽的人，心情比較好。」",
                            "樹洞裡傳來打呼聲：睡前一小時放下手機，會睡得更香。",
                            "貓頭鷹說：房間暗一點、涼一點，夢就會甜一點。"]
        case .moonMarsh: ["石碑寫著：「今天做不完的事，明天再做也沒關係。」",
                          "沼澤的青蛙說：深呼吸，吸四秒、吐六秒。",
                          "月光說：想吃宵夜的時候，先喝杯溫水、等十分鐘。"]
        case .royalCity: ["石碑寫著：「累積，是最強的魔法。」",
                          "城門的衛兵說：休息日也是冒險的一部分。",
                          "王城的鐘聲說：記得為自己走過的路驕傲。"]
        case .sacredLake, .calmTower, .frontier, .festival: []
        }
    }
}

// MARK: - 旅途見聞

/// 每走 1.2 公里遇到一件小事
struct Encounter: Identifiable {
    enum Kind { case chest, spirit, saying, spring, sign }

    let index: Int
    let kind: Kind
    let text: String
    let coins: Int
    var id: Int { index }

    var art: PixelArt {
        switch kind {
        case .chest: .chest
        case .spirit: .companion
        case .saying: .book
        case .spring: .drop
        case .sign: .footprint
        }
    }
}

// MARK: - 主線故事

enum StorySpeaker {
    case narrator, partner, sofa, bat, fog

    var art: PixelArt? {
        switch self {
        case .narrator, .partner: nil
        case .sofa: .monsterSofa
        case .bat: .monsterBat
        case .fog: .monsterFog
        }
    }

    func name(partner: String) -> String? {
        switch self {
        case .narrator: nil
        case .partner: partner.isEmpty ? "小卡" : partner
        case .sofa: "沙發怪"
        case .bat: "熬夜蝠"
        case .fog: "焦慮霧"
        }
    }
}

struct StoryLine {
    let speaker: StorySpeaker
    let text: String
}

struct StoryScene: Identifiable, Equatable {
    let id: String
    let title: String
    /// 抵達這個區域時播放
    let region: SpiritRegion
    let lines: [StoryLine]

    static func == (lhs: StoryScene, rhs: StoryScene) -> Bool { lhs.id == rhs.id }
}

/// 第一章「沉睡的大陸」：序章＋每抵達一個區域一段
enum Story {
    static let chapterOneTitle = "第一章　沉睡的大陸"

    static let chapterOne: [StoryScene] = [
        StoryScene(id: "c1-prologue", title: "序章　出發", region: .riceVillage, lines: [
            StoryLine(speaker: .narrator, text: "很久很久以前，元氣大陸上住著許多元氣精靈。"),
            StoryLine(speaker: .narrator, text: "直到某天，熬夜蝠、沙發怪和焦慮霧帶著壞習慣闖進大陸，精靈們一個個陷入了沉睡。"),
            StoryLine(speaker: .partner, text: "喂，冒險者！別發呆了，米糧村外面的路都長草了啦。"),
            StoryLine(speaker: .partner, text: "聽說只要好好走路、好好睡覺，沉睡的精靈就會醒過來。"),
            StoryLine(speaker: .partner, text: "……我才不是想跟你一起去喔，只是剛好順路而已！"),
            StoryLine(speaker: .narrator, text: "第一章「沉睡的大陸」開始。下一站：步道山谷（8 公里）。"),
        ]),
        StoryScene(id: "c1-trailValley", title: "抵達步道山谷", region: .trailValley, lines: [
            StoryLine(speaker: .narrator, text: "山谷的風呼呼吹過，路邊的長椅上躺滿了軟綿綿的影子。"),
            StoryLine(speaker: .sofa, text: "走那麼多路幹嘛？坐下來嘛……躺下來嘛……"),
            StoryLine(speaker: .partner, text: "是沙發怪！牠會讓人一坐下就起不來！"),
            StoryLine(speaker: .partner, text: "別理牠，我們繼續走。走得越遠，牠的影子就越淡。"),
            StoryLine(speaker: .sofa, text: "哼……你們會回來的……每個人最後都會回到沙發上……"),
            StoryLine(speaker: .narrator, text: "沙發怪的影子縮回了長椅底下。下一站：晨光丘（20 公里）。"),
        ]),
        StoryScene(id: "c1-dawnHill", title: "抵達晨光丘", region: .dawnHill, lines: [
            StoryLine(speaker: .narrator, text: "天快亮了，晨光丘上卻還掛著一片不肯散去的夜色。"),
            StoryLine(speaker: .bat, text: "嘻嘻，再滑一下手機嘛，才凌晨一點而已喔～"),
            StoryLine(speaker: .partner, text: "熬夜蝠！就是牠讓大家睡不飽，白天一直想吃零食。"),
            StoryLine(speaker: .partner, text: "早點睡、早點起，太陽一出來，牠就只能躲回洞裡。"),
            StoryLine(speaker: .bat, text: "哼，今晚我還會再來找你的！"),
            StoryLine(speaker: .narrator, text: "第一道陽光照亮了山坡。下一站：夢之森（36 公里）。"),
        ]),
        StoryScene(id: "c1-dreamForest", title: "抵達夢之森", region: .dreamForest, lines: [
            StoryLine(speaker: .narrator, text: "森林裡好安靜，每一棵樹都在打呼。"),
            StoryLine(speaker: .partner, text: "這裡的精靈要睡得夠久才會醒來……跟某人一樣。"),
            StoryLine(speaker: .partner, text: "聽說森林深處有一隻夜露凝成的精靈，只在連續好眠的夜裡出現。"),
            StoryLine(speaker: .narrator, text: "樹梢傳來一陣輕輕的笑聲，好像有誰在夢裡為你加油。"),
            StoryLine(speaker: .narrator, text: "下一站：月影沼澤（56 公里）。"),
        ]),
        StoryScene(id: "c1-moonMarsh", title: "抵達月影沼澤", region: .moonMarsh, lines: [
            StoryLine(speaker: .narrator, text: "沼澤上飄著灰灰的霧，一走進去，心就跟著悶了起來。"),
            StoryLine(speaker: .fog, text: "事情做不完……明天會更糟……要不要先吃點什麼壓壓驚……"),
            StoryLine(speaker: .partner, text: "是焦慮霧！深呼吸，慢慢吐氣，霧就會散一點。"),
            StoryLine(speaker: .partner, text: "累了就休息。想吃東西的時候，先喝口水、等十分鐘，不用跟自己過不去。"),
            StoryLine(speaker: .narrator, text: "霧淡了一些，遠方露出了王城的塔尖。下一站：王城（80 公里）。"),
        ]),
        StoryScene(id: "c1-royalCity", title: "抵達王城", region: .royalCity, lines: [
            StoryLine(speaker: .narrator, text: "王城的大門緩緩打開，醒過來的精靈們在廣場上等著你。"),
            StoryLine(speaker: .partner, text: "我們……真的走到了耶！"),
            StoryLine(speaker: .partner, text: "雖然我一路上抱怨很多，但這趟冒險，其實還滿開心的。"),
            StoryLine(speaker: .narrator, text: "可是城堡最高的塔上，有一雙發亮的眼睛正盯著你們——"),
            StoryLine(speaker: .bat, text: "嘻嘻，走到這裡算你厲害。不過真正的夜晚，現在才要開始……"),
            StoryLine(speaker: .narrator, text: "第一章「沉睡的大陸」完。第二章，敬請期待。"),
        ]),
    ]

    static func scene(arrivingAt region: SpiritRegion) -> StoryScene? {
        region == .riceVillage ? nil : chapterOne.first { $0.region == region }
    }
}

// MARK: - 旅程進度

/// 累計步行距離 → 大陸地圖上的位置、旅途見聞、主線故事
@MainActor
final class JourneyStore: ObservableObject {
    static let shared = JourneyStore()

    /// 每走幾公尺遇到一件事
    static let checkpointMeters: Double = 1200
    /// 旅途見聞一天最多給幾枚元氣幣
    static let dailyCoinCap = 6

    private struct State: Codable {
        var seenScenes: [String] = []
        /// 已經收下的見聞數量
        var collected = 0
        var coinDay = ""
        var coinsToday = 0
    }

    private static let key = "journeyState"
    @Published private var state: State
    /// 累計步行距離（公尺）
    @Published private(set) var meters: Double = 0
    /// 要播放的故事
    @Published var playing: StoryScene?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    var kilometers: Double { meters / 1000 }

    /// 目前所在（已抵達的最後一個）區域與下一站
    var currentRegion: SpiritRegion { SpiritRegion.journeyStops.last { $0.journeyKm <= kilometers } ?? .riceVillage }
    var nextRegion: SpiritRegion? { SpiritRegion.journeyStops.first { $0.journeyKm > kilometers } }

    func isReached(_ region: SpiritRegion) -> Bool { region.journeyKm <= kilometers }
    func hasSeen(_ scene: StoryScene) -> Bool { state.seenScenes.contains(scene.id) }

    // MARK: 讀資料

    /// App 回到前景時呼叫：讀從開始那天起的步行距離；抵達新區域就播放那段故事
    func refresh() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-seedJourney"), index + 1 < arguments.count,
           let value = Double(arguments[index + 1]) {
            meters = value
            if let index = arguments.firstIndex(of: "-story"), index + 1 < arguments.count {
                playing = Story.chapterOne.first { $0.id == arguments[index + 1] }
            }
            return
        }
        #endif
        let start = SpiritCollection.shared.state.start
        let daily = await HealthKitManager.shared.dailySums(.distanceWalkingRunning, unit: .meter(), from: start, to: .now)
        meters = daily.values.reduce(0, +)
        // 序章看過才會接著播抵達的故事（序章在第一次打開地圖時播）
        guard state.seenScenes.contains("c1-prologue"), playing == nil else { return }
        playing = SpiritRegion.journeyStops
            .filter(isReached)
            .compactMap(Story.scene(arrivingAt:))
            .first { !hasSeen($0) }
    }

    /// 第一次打開地圖時播序章
    func playPrologueIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-noStory") { return }
        #endif
        guard playing == nil, let prologue = Story.chapterOne.first, !hasSeen(prologue) else { return }
        playing = prologue
    }

    func finish(_ scene: StoryScene) {
        if !state.seenScenes.contains(scene.id) { state.seenScenes.append(scene.id) }
        playing = nil
        save()
        // 一次走過好幾個區域時，接著播下一段
        Task { await refreshStoryOnly() }
    }

    private func refreshStoryOnly() async {
        try? await Task.sleep(for: .milliseconds(400))
        guard playing == nil else { return }
        playing = SpiritRegion.journeyStops.filter(isReached).compactMap(Story.scene(arrivingAt:)).first { !hasSeen($0) }
    }

    // MARK: 旅途見聞

    var reachedCheckpoints: Int { Int(meters / Self.checkpointMeters) }

    /// 見聞每天的元氣幣上限（獅鷲的特性會提高）
    var dailyCap: Int {
        if case .journeyCap(let extra) = CampStore.shared.activePerk?.perk { return Self.dailyCoinCap + extra }
        return Self.dailyCoinCap
    }

    /// 還沒收下的見聞（最多列最近 8 件）
    var newEncounters: [Encounter] {
        let first = max(state.collected + 1, reachedCheckpoints - 7)
        guard first <= reachedCheckpoints else { return [] }
        return (first...reachedCheckpoints).map(encounter(at:))
    }

    /// 收下見聞；元氣幣一天最多 6 枚，超過的只留故事
    @discardableResult
    func collectEncounters() -> Int {
        let today = Date.now.dayKey
        if state.coinDay != today {
            state.coinDay = today
            state.coinsToday = 0
        }
        let total = newEncounters.reduce(0) { $0 + $1.coins }
        let coins = max(0, min(total, dailyCap - state.coinsToday))
        state.coinsToday += coins
        state.collected = reachedCheckpoints
        save()
        if coins > 0 { AdventureStore.shared.addBonus(coins, source: .journey) }
        return coins
    }

    /// 第幾件見聞（用編號算，同一件永遠一樣）
    func encounter(at index: Int) -> Encounter {
        var hash: UInt64 = 14695981039346656037 &+ UInt64(index)
        for _ in 0..<3 { hash = (hash ^ (hash >> 29)) &* 1099511628211 }
        let km = Double(index) * Self.checkpointMeters / 1000
        let region = SpiritRegion.journeyStops.last { $0.journeyKm <= km } ?? .riceVillage
        let next = SpiritRegion.journeyStops.first { $0.journeyKm > km }
        switch hash % 100 {
        case ..<20:
            return Encounter(index: index, kind: .chest, text: "路邊的草叢裡有個小寶箱，裡面有 3 枚元氣幣！", coins: 3)
        case ..<40:
            let spirit = region.spirits[Int(hash >> 8) % region.spirits.count]
            let name = SpiritCollection.isUnlocked(spirit) ? spirit.title : "一隻看不清楚的精靈"
            return Encounter(index: index, kind: .spirit, text: "\(name)從樹後探出頭，看了你一眼，又害羞地躲回去了。", coins: 1)
        case ..<70:
            let sayings = region.sayings
            return Encounter(index: index, kind: .saying, text: sayings[Int(hash >> 16) % sayings.count], coins: 1)
        case ..<85:
            return Encounter(index: index, kind: .spring, text: "發現一口清泉。冒險者，也記得幫自己補充水分！", coins: 1)
        default:
            if let next {
                let left = (next.journeyKm - km).formatted(.number.precision(.fractionLength(1)))
                return Encounter(index: index, kind: .sign, text: "路標寫著：距離\(next.title)還有 \(left) 公里。", coins: 1)
            }
            return Encounter(index: index, kind: .sign, text: "路標寫著：前方是還沒有人走過的地方。", coins: 1)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
