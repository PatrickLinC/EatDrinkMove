import SwiftUI

/// 「營地」分頁：用元氣幣蓋建築，已喚醒的精靈會在營地裡散步
struct CampView: View {
    @ObservedObject private var camp = CampStore.shared
    @ObservedObject private var adventure = AdventureStore.shared
    @ObservedObject private var spirits = SpiritCollection.shared
    @State private var built = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "營地", subtitle: "CAMP") {
                        HStack(spacing: 6) {
                            PixelSprite(art: .coin, size: 16)
                            Text("\(adventure.balance)").font(.px(16)).foregroundStyle(Color.carbs).monospacedDigit()
                        }
                    }
                    PixelWindow(title: "營地 Lv.\(camp.campLevel)") {
                        CampScene()
                            .frame(height: 360)
                    }
                    if let festival = Festival.active() { festivalWindow(festival) }
                    partnerWindow
                    buildWindow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.success, trigger: built)
        }
    }

    // MARK: 夥伴（羈絆與特性）

    private var partnerWindow: some View {
        PixelWindow(title: "夥伴", tint: .brand) {
            if let skin = CompanionSkin.active {
                HStack(spacing: 12) {
                    CompanionAvatar(size: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(skin.title)
                            PixelChip(text: "羈絆 Lv.\(camp.bondLevel(skin))", color: .protein)
                        }
                        if let progress = camp.bondProgress(skin) {
                            PixelBar(value: Double(progress.current), total: Double(progress.needed), color: .protein,
                                     segments: 8, height: 6, overIsBad: false)
                            Text("再 \(progress.needed - progress.current) 點升級。領到元氣幣時，牠也會一起累積羈絆。")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("羈絆已經滿級了！").font(.px(12)).foregroundStyle(Color.protein)
                        }
                    }
                }
                PixelDivider()
                HStack(alignment: .top, spacing: 8) {
                    PixelChip(text: camp.perkActive(skin) ? "特性生效中" : "羈絆 Lv.\(CampStore.perkBondLevel) 生效",
                              color: camp.perkActive(skin) ? .move : .soft, filled: camp.perkActive(skin))
                    Text(skin.perk.text).font(.px(12)).fixedSize(horizontal: false, vertical: true)
                }
                Text("在「圖鑑」點精靈可以換夥伴，每隻的特性都不一樣。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            } else {
                Text("目前用的是 emoji 造型，沒有精靈特性。在「圖鑑」選一隻精靈帶在身邊吧。")
                    .font(.px(12))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 節慶

    private func festivalWindow(_ festival: Festival) -> some View {
        PixelWindow(title: "\(festival.title)活動中", tint: .calorie) {
            HStack(alignment: .top, spacing: 12) {
                PixelSprite(art: festival.decorationArt, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("限定裝飾：\(festival.decorationTitle)")
                    Text("只有\(festival.title)期間能蓋，蓋了就一直留在營地。錯過了明年還會再來。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if camp.hasDecoration(festival) {
                PixelChip(text: "已經放在營地了", color: .move)
            } else {
                Button {
                    if camp.buildDecoration(festival) { built += 1 }
                } label: {
                    HStack(spacing: 4) {
                        PixelSprite(art: .coin, size: 12)
                        Text("蓋 \(festival.decorationCost)")
                    }
                }
                .buttonStyle(.pixel(adventure.balance >= festival.decorationCost ? .primary : .secondary, fontSize: 12))
                .disabled(adventure.balance < festival.decorationCost)
            }
        }
    }

    // MARK: 建造

    private var buildWindow: some View {
        PixelWindow(title: "建造", tint: .carbs, spacing: 0) {
            ForEach(Array(CampBuilding.allCases.enumerated()), id: \.element.id) { index, building in
                if index > 0 { PixelDivider() }
                buildRow(building)
            }
            Text("元氣幣靠睡好、走路、喝水、記錄三餐賺，蓋的東西只是讓營地變漂亮，不影響其他功能。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buildRow(_ building: CampBuilding) -> some View {
        let level = camp.level(building)
        let cost = camp.nextCost(building)
        return HStack(spacing: 10) {
            PixelSprite(art: building.art(level: max(level, 1)), size: 36, tint: level == 0 ? .track : nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(building.title(level: max(level, 1)))
                    if level > 0 && building.maxLevel > 1 {
                        Text("Lv.\(level)").font(.px(12)).foregroundStyle(Color.brand)
                    }
                }
                Text(building.detail).font(.px(12)).foregroundStyle(Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let cost {
                Button {
                    if camp.build(building) { built += 1 }
                } label: {
                    HStack(spacing: 4) {
                        PixelSprite(art: .coin, size: 12)
                        Text(level == 0 ? "蓋 \(cost)" : "升級 \(cost)")
                    }
                }
                .buttonStyle(.pixel(adventure.balance >= cost ? .primary : .secondary, fontSize: 12))
                .disabled(adventure.balance < cost)
            } else {
                PixelChip(text: "完成", color: .move)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - 營地畫面

/// 草地上的建築（沒蓋的是虛線建地），已喚醒的精靈走來走去
struct CampScene: View {
    @ObservedObject private var camp = CampStore.shared
    @ObservedObject private var spirits = SpiritCollection.shared
    /// 點到的精靈或建築說的話（顯示 5 秒）
    @State private var speech: Speech?

    private struct Speech: Equatable {
        enum Speaker: Equatable { case spirit(CompanionSkin), building(CampBuilding) }
        let speaker: Speaker
        let text: String
        let until: Date
    }

    /// 節慶裝飾的位置（建築之間的空地）
    private static let decorationSlots: [(Festival, CGPoint)] = [
        (.newYear, CGPoint(x: 0.3, y: 0.2)),
        (.dragonBoat, CGPoint(x: 0.7, y: 0.2)),
        (.summer, CGPoint(x: 0.335, y: 0.6)),
        (.midAutumn, CGPoint(x: 0.665, y: 0.6)),
        (.halloween, CGPoint(x: 0.32, y: 0.9)),
        (.christmas, CGPoint(x: 0.68, y: 0.9)),
    ]

    /// 建築的位置（比例）和大小
    private static let slots: [(CampBuilding, CGPoint, CGFloat)] = [
        (.tower, CGPoint(x: 0.14, y: 0.2), 64),
        (.home, CGPoint(x: 0.5, y: 0.22), 96),
        (.spiritHouse, CGPoint(x: 0.86, y: 0.22), 64),
        (.garden, CGPoint(x: 0.17, y: 0.62), 64),
        (.firePit, CGPoint(x: 0.5, y: 0.6), 52),
        (.well, CGPoint(x: 0.83, y: 0.62), 64),
        (.flowers, CGPoint(x: 0.14, y: 0.9), 44),
        (.banner, CGPoint(x: 0.5, y: 0.9), 44),
        (.lamp, CGPoint(x: 0.86, y: 0.88), 48),
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    grass(size: size)
                    ForEach(Self.slots, id: \.0) { building, point, length in
                        slot(building, length: length, tick: Int(time / 0.35))
                            .contentShape(Rectangle())
                            .onTapGesture { talk(.building(building)) }
                            .position(x: point.x * size.width, y: point.y * size.height)
                    }
                    ForEach(Self.decorationSlots.filter { camp.hasDecoration($0.0) }, id: \.0) { festival, point in
                        PixelSprite(art: festival.decorationArt, size: 36)
                            .position(x: point.x * size.width, y: point.y * size.height)
                    }
                    ForEach(Array(wanderers.enumerated()), id: \.element) { index, skin in
                        let spot = position(of: index, time: time, size: size)
                        PixelSprite(art: skin.art(shiny: spirits.unlockedDate(skin, shiny: true) != nil,
                                                  blink: Int(time * 2 + Double(index)) % 9 == 0), size: 28)
                            .scaleEffect(x: spot.facingLeft ? -1 : 1, y: 1)
                            .offset(y: Int(time / 0.35 + Double(index)) % 2 == 0 ? -1 : 0)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture { talk(.spirit(skin)) }
                            .position(spot.point)
                            .accessibilityLabel("跟\(skin.title)說話")
                            .accessibilityAddTraits(.isButton)
                    }
                    if let speech, speech.until > timeline.date, let point = speakerPoint(speech.speaker, time: time, size: size) {
                        Text(speech.text)
                            .font(.px(12))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 190)
                            .padding(8)
                            .background { PixelPanel(fill: .window, shadow: .pxShadow, lineWidth: 2) }
                            .position(x: min(max(point.x, 104), size.width - 104), y: max(point.y - 48, 30))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
        }
        #if DEBUG
        // 開發用：-campTalk 打開時第一隻精靈先說話（截圖檢查對話框）
        .task {
            if ProcessInfo.processInfo.arguments.contains("-campTalk"), let first = wanderers.first {
                try? await Task.sleep(for: .seconds(1))
                talk(.spirit(first))
                speech = speech.map { Speech(speaker: $0.speaker, text: $0.text, until: .now.addingTimeInterval(30)) }
            }
        }
        #endif
    }

    // MARK: 對話

    private func talk(_ speaker: Speech.Speaker) {
        let text: String
        switch speaker {
        case .spirit(let skin):
            var lines = Self.chatter.map { "\(skin.title)：\($0)" }
            // 羈絆 Lv3 以上會說出自己的故事
            if camp.bondLevel(skin) >= 3, let story = skin.bondStories.first { lines.append(story) }
            lines.removeAll { $0 == speech?.text }
            text = lines.randomElement() ?? skin.title
        case .building(let building):
            let level = camp.level(building)
            text = level > 0 ? "\(building.title(level: level))：\(building.detail)" : "這裡可以蓋\(building.title(level: 1))，到下面的「建造」看看。"
        }
        withAnimation(.easeOut(duration: 0.2)) { speech = Speech(speaker: speaker, text: text, until: .now.addingTimeInterval(5)) }
    }

    private func speakerPoint(_ speaker: Speech.Speaker, time: TimeInterval, size: CGSize) -> CGPoint? {
        switch speaker {
        case .spirit(let skin):
            guard let index = wanderers.firstIndex(of: skin) else { return nil }
            return position(of: index, time: time, size: size).point
        case .building(let building):
            guard let slot = Self.slots.first(where: { $0.0 == building }) else { return nil }
            return CGPoint(x: slot.1.x * size.width, y: slot.1.y * size.height - slot.2 / 2 + 20)
        }
    }

    private static let chatter = [
        "今天也一起加油吧！", "營地住起來好舒服。", "你今天有喝水嗎？", "走一走，心情會變好喔。",
        "我剛剛在菜園看到一隻蝴蝶！", "晚上記得早點睡。", "謝謝你每天都來看我們。", "營火的味道好香。",
        "要不要出去散個步？", "今天的天空好藍。",
    ]

    /// 出來散步的精靈：帶著的夥伴一定在，其他每天輪流（最多 wanderLimit 隻）
    private var wanderers: [CompanionSkin] {
        let active = CompanionSkin.active
        let others = CompanionSkin.dexOrder.filter { spirits.unlockedDate($0) != nil && $0 != active }
        let shift = others.isEmpty ? 0 : (Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0) % others.count
        let rotated = Array(others[shift...] + others[..<shift])
        return Array(((active.map { [$0] } ?? []) + rotated).prefix(camp.wanderLimit))
    }

    private func grass(size: CGSize) -> some View {
        Canvas { context, canvas in
            var seed: UInt64 = 11
            for _ in 0..<40 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(seed >> 33 % 1000) / 1000 * canvas.width
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let y = CGFloat(seed >> 33 % 1000) / 1000 * canvas.height
                context.fill(Path(CGRect(x: x, y: y, width: 4, height: 4)), with: .color(.move.opacity(0.25)))
                context.fill(Path(CGRect(x: x + 4, y: y - 4, width: 4, height: 4)), with: .color(.move.opacity(0.25)))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder private func slot(_ building: CampBuilding, length: CGFloat, tick: Int) -> some View {
        let level = camp.level(building)
        if level > 0 {
            let art: PixelArt = building == .firePit ? (tick % 2 == 0 ? .campfire : .campfireFlicker) : building.art(level: level)
            PixelSprite(art: art, size: length)
                .overlay(alignment: .topTrailing) {
                    if level >= 2 && building != .home {
                        PixelSprite(art: .star, size: 14).offset(x: 4, y: -4)
                    }
                }
        } else {
            Rectangle()
                .strokeBorder(Color.track, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: length * 0.8, height: length * 0.6)
                .overlay { Text("建地").font(.px(12)).foregroundStyle(Color.track) }
        }
    }

    /// 每隻精靈在幾個點之間慢慢走，走到了換下一個點（用時間算，不用存狀態）
    private func position(of index: Int, time: TimeInterval, size: CGSize) -> (point: CGPoint, facingLeft: Bool) {
        let leg = 6.0 // 走一段要幾秒
        let phase = time / leg + Double(index) * 1.7
        let step = Int(phase)
        let t = phase - Double(step)
        func waypoint(_ n: Int) -> CGPoint {
            var hash = UInt64(bitPattern: Int64(n &* 7919 &+ index &* 104729))
            hash = (hash ^ (hash >> 17)) &* 0x9E3779B97F4A7C15
            let x = 0.1 + Double(hash % 1000) / 1000 * 0.8
            // 兩條草地走道：上排建築和中間那排之間、中間那排和花圃之間（不要站在建築上）
            let lane = (hash >> 40) % 2 == 0 ? 0.38 : 0.74
            let y = lane + Double((hash >> 20) % 1000) / 1000 * 0.08
            return CGPoint(x: x * size.width, y: y * size.height)
        }
        let from = waypoint(step), to = waypoint(step + 1)
        // 前半段走、後半段停下來
        let walk = min(t * 1.6, 1)
        let point = CGPoint(x: from.x + (to.x - from.x) * walk, y: from.y + (to.y - from.y) * walk)
        return (point, to.x < from.x)
    }
}

// MARK: - 稱號

/// 選一個稱號顯示在今日頁的狀態視窗
struct TitleView: View {
    @AppStorage(HeroTitle.storageKey) private var heroTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PixelWindow(title: "稱號", spacing: 0) {
                    row(title: "依等級自動", condition: "記錄越多，等級稱號會跟著升級", unlocked: true, selected: heroTitle.isEmpty) {
                        heroTitle = ""
                    }
                    ForEach(HeroTitle.allCases) { title in
                        PixelDivider()
                        row(title: title.title, condition: title.condition, unlocked: title.isUnlocked,
                            selected: heroTitle == title.rawValue) {
                            heroTitle = title.rawValue
                        }
                    }
                }
                Text("選好的稱號會顯示在「今日」的狀態視窗。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
            .padding(16)
        }
        .background(Color.paper)
        .navigationTitle("稱號")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, condition: String, unlocked: Bool, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(selected ? Color.brand : Color.window)
                    .frame(width: 14, height: 14)
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(unlocked ? title : "？？？")
                    Text(condition).font(.px(12)).foregroundStyle(Color.soft)
                }
                Spacer(minLength: 4)
                if !unlocked { PixelSprite(art: .lock, size: 16) }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .opacity(unlocked ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(unlocked)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
