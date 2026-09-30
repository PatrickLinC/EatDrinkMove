import SwiftUI

// MARK: - 大陸地圖

struct WorldMapView: View {
    @ObservedObject private var journey = JourneyStore.shared
    @ObservedObject private var spirits = SpiritCollection.shared
    @State private var collected: Int?

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "大陸地圖", subtitle: "WORLD MAP") {
                        PixelChip(text: "\(Self.km(journey.kilometers)) km", color: .move)
                    }
                    journeyWindow
                    encounterWindow
                    PixelWindow(title: "元氣大陸") {
                        MapCanvas(kilometers: journey.kilometers, fog: StressStore.shared.fogActive)
                            .frame(height: 1080)
                    }
                    .id("map")
                    storyWindow.id("story")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .task {
                #if DEBUG
                // 開發用：-scrollTo map／mapMiddle／story 捲到某個位置截圖
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-scrollTo"), index + 1 < arguments.count {
                    try? await Task.sleep(for: .milliseconds(300))
                    let target = arguments[index + 1]
                    reader.scrollTo(target == "mapMiddle" ? "map" : target, anchor: target == "mapMiddle" ? .center : .top)
                }
                #endif
                journey.playPrologueIfNeeded()
            }
        }
    }

    static func km(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }

    // MARK: 旅程

    private var journeyWindow: some View {
        PixelWindow(title: "旅程", tint: .move) {
            HStack(spacing: 10) {
                PixelSprite(art: journey.currentRegion.landmark, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("目前在\(journey.currentRegion.title)")
                    Text("\(spirits.state.start.formatted(.dateTime.month().day())) 起的步行＋跑步距離")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
            }
            if let next = journey.nextRegion {
                let from = journey.currentRegion.journeyKm
                PixelBar(value: journey.kilometers - from, total: next.journeyKm - from, color: .move, overIsBad: false)
                HStack {
                    Text("下一站：\(next.title)")
                    Spacer()
                    Text("還有 \(Self.km(next.journeyKm - journey.kilometers)) km").foregroundStyle(Color.move).monospacedDigit()
                }
                .font(.px(12))
            } else {
                Text("抵達王城了！第一章完成，繼續走還會遇到旅途見聞。")
                    .font(.px(12))
                    .foregroundStyle(Color.move)
            }
        }
    }

    // MARK: 旅途見聞

    private var encounterWindow: some View {
        let encounters = journey.newEncounters
        let coins = encounters.reduce(0) { $0 + $1.coins }
        return PixelWindow(title: "旅途見聞", tint: .carbs) {
            if encounters.isEmpty {
                let next = Double(journey.reachedCheckpoints + 1) * JourneyStore.checkpointMeters - journey.meters
                Text("每走 1.2 公里會遇到一件事。下一件還要走 \(Int(max(next, 0))) 公尺。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
                if let collected {
                    Text(collected > 0 ? "收下了 \(collected) 枚元氣幣！" : "今天的見聞獎勵已經拿滿了，明天再來。")
                        .font(.px(12))
                        .foregroundStyle(Color.carbs)
                }
            } else {
                ForEach(encounters) { encounter in
                    HStack(alignment: .top, spacing: 10) {
                        PixelSprite(art: encounter.art, size: 24)
                        Text(encounter.text).font(.px(12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                Button(coins > 0 ? "收下見聞" : "收下") {
                    withAnimation { collected = journey.collectEncounters() }
                }
                .buttonStyle(.pixel(.primary, fullWidth: true))
                Text("見聞的元氣幣一天最多 \(journey.dailyCap) 枚。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
        }
    }

    // MARK: 主線故事

    private var storyWindow: some View {
        PixelWindow(title: "主線故事", tint: .fat) {
            Text(Story.chapterOneTitle)
            ForEach(Story.chapterOne) { scene in
                let unlocked = journey.hasSeen(scene) || (scene.region == .riceVillage || journey.isReached(scene.region))
                HStack(spacing: 10) {
                    PixelSprite(art: scene.region.landmark, size: 20, tint: unlocked ? nil : .track)
                    Text(unlocked ? scene.title : "？？？")
                        .foregroundStyle(unlocked ? Color.ink : Color.soft)
                    Spacer(minLength: 4)
                    if unlocked {
                        Button(journey.hasSeen(scene) ? "重看" : "播放") { journey.playing = scene }
                            .buttonStyle(.pixel(.secondary, fontSize: 12))
                    } else {
                        Text("抵達\(scene.region.title)").font(.px(12)).foregroundStyle(Color.soft)
                    }
                }
            }
        }
    }
}

/// 地圖本體：蜿蜒的小路、六個地標、目前位置的小夥伴
struct MapCanvas: View {
    let kilometers: Double
    /// 今天有焦慮霧時，霧會飄在小夥伴旁邊
    var fog = false

    private static let columns: [CGFloat] = [0.28, 0.72, 0.3, 0.7, 0.3, 0.55]

    var body: some View {
        GeometryReader { geometry in
            let regions = SpiritRegion.journeyStops
            let points = regions.indices.map { index in point(index, in: geometry.size) }
            ZStack(alignment: .topLeading) {
                // 草地的小點（固定位置，每次畫出來都一樣）
                Canvas { context, size in
                    var seed: UInt64 = 7
                    for _ in 0..<70 {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let x = CGFloat(seed >> 33 % 1000) / 1000 * size.width
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let y = CGFloat(seed >> 33 % 1000) / 1000 * size.height
                        context.fill(Path(CGRect(x: x, y: y, width: 4, height: 4)), with: .color(.move.opacity(0.25)))
                        context.fill(Path(CGRect(x: x + 4, y: y - 4, width: 4, height: 4)), with: .color(.move.opacity(0.25)))
                    }
                    // 小路：一格一格的石板，走過的是主色
                    for index in 0..<(points.count - 1) {
                        let from = points[index], to = points[index + 1]
                        let startKm = regions[index].journeyKm, endKm = regions[index + 1].journeyKm
                        let length = hypot(to.x - from.x, to.y - from.y)
                        let steps = Int(length / 16)
                        for step in 0...steps {
                            let t = CGFloat(step) / CGFloat(max(steps, 1))
                            let x = from.x + (to.x - from.x) * t, y = from.y + (to.y - from.y) * t
                            let walked = startKm + Double(t) * (endKm - startKm) <= kilometers
                            let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                            context.fill(Path(rect), with: .color(walked ? .brand : .track))
                        }
                    }
                }

                ForEach(regions.indices, id: \.self) { index in
                    landmark(regions[index])
                        .position(x: points[index].x, y: points[index].y + 8)
                }

                if fog {
                    let hero = heroPosition(points: points)
                    PixelSprite(art: .monsterFog, size: 56)
                        .opacity(0.9)
                        .position(x: hero.x - 56, y: hero.y - 24)
                }
                // 小夥伴站在目前的位置
                VStack(spacing: 2) {
                    CompanionAvatar(size: 40)
                    PixelChip(text: "\(WorldMapView.km(kilometers)) km", color: .move)
                }
                .position(heroPosition(points: points))
            }
        }
    }

    private func point(_ index: Int, in size: CGSize) -> CGPoint {
        let count = CGFloat(SpiritRegion.journeyStops.count - 1)
        let top: CGFloat = 80, bottom: CGFloat = 110
        let y = size.height - bottom - (size.height - top - bottom) * CGFloat(index) / count
        return CGPoint(x: size.width * Self.columns[index], y: y)
    }

    private func heroPosition(points: [CGPoint]) -> CGPoint {
        let regions = SpiritRegion.journeyStops
        for index in 0..<(regions.count - 1) where kilometers < regions[index + 1].journeyKm {
            let t = (kilometers - regions[index].journeyKm) / (regions[index + 1].journeyKm - regions[index].journeyKm)
            let from = points[index], to = points[index + 1]
            return CGPoint(x: from.x + (to.x - from.x) * t + 36, y: from.y + (to.y - from.y) * t - 20)
        }
        let last = points[points.count - 1]
        return CGPoint(x: last.x + 52, y: last.y - 20)
    }

    private func landmark(_ region: SpiritRegion) -> some View {
        let reached = region.journeyKm <= kilometers
        return VStack(spacing: 4) {
            PixelSprite(art: region.landmark, size: 72, tint: reached ? nil : .track)
            if reached {
                PixelTag(text: region.title, fill: region.color, size: 12)
            } else {
                PixelChip(text: "？？？・\(region.journeyKm.formatted()) km", color: .soft, filled: false)
            }
        }
    }
}

// MARK: - 故事播放

/// 像素對話框：一個字一個字出現，點一下看下一句
struct StoryView: View {
    let scene: StoryScene
    var onDone: () -> Void
    @AppStorage(SettingKey.companionName) private var companionName = "小卡"
    @State private var index = 0
    @State private var shown = 0

    private var line: StoryLine { scene.lines[min(index, scene.lines.count - 1)] }
    private var fullText: [Character] { Array(line.text) }
    private var isTyping: Bool { shown < fullText.count }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    PixelTag(text: scene.title, fill: scene.region.color)
                    Spacer()
                    Button("略過") { onDone() }
                        .buttonStyle(.pixel(.secondary, fontSize: 12))
                }

                Spacer(minLength: 0)

                // 旁白時只有地標；有角色說話時地標退到後上方、角色站在前面
                ZStack(alignment: .bottom) {
                    PixelSprite(art: scene.region.landmark, size: line.speaker == .narrator ? 160 : 112)
                        .opacity(line.speaker == .narrator ? 1 : 0.3)
                        .offset(y: line.speaker == .narrator ? -40 : -128)
                    portrait
                }
                .frame(height: 260)
                .animation(.easeOut(duration: 0.2), value: index)

                Spacer(minLength: 0)

                PixelWindow(title: line.speaker.name(partner: companionName), tint: line.speaker == .partner ? .brand : .ink) {
                    Text(String(fullText.prefix(shown)))
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("\(index + 1)／\(scene.lines.count)").font(.px(12)).foregroundStyle(Color.soft)
                        Spacer()
                        if !isTyping {
                            Text(index == scene.lines.count - 1 ? "完" : "▼").font(.px(12)).foregroundStyle(Color.soft)
                        }
                    }
                }
                Text("點一下繼續").font(.px(12)).foregroundStyle(Color.soft)
            }
            .padding(20)
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        #if DEBUG
        // 開發用：-storyLine 2 直接從第二句開始（截圖檢查角色頭像）
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if let at = arguments.firstIndex(of: "-storyLine"), at + 1 < arguments.count, let line = Int(arguments[at + 1]) {
                index = min(max(line - 1, 0), scene.lines.count - 1)
            }
        }
        #endif
        .task(id: index) {
            shown = 0
            while shown < fullText.count {
                try? await Task.sleep(for: .milliseconds(35))
                if Task.isCancelled { return }
                shown += 1
            }
        }
    }

    @ViewBuilder private var portrait: some View {
        switch line.speaker {
        case .narrator:
            EmptyView()
        case .partner:
            CompanionAvatar(size: 112)
        default:
            if let art = line.speaker.art {
                PixelSprite(art: art, size: 128)
            }
        }
    }

    private func advance() {
        if isTyping {
            shown = fullText.count
        } else if index < scene.lines.count - 1 {
            index += 1
        } else {
            onDone()
        }
    }
}
