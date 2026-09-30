import SwiftUI

// MARK: - 今日頁的冒險視窗

/// 今日頁：睡眠分數、今日事件、元氣幣與營火
struct AdventureWindow: View {
    @ObservedObject private var adventure = AdventureStore.shared
    @ObservedObject private var journey = JourneyStore.shared
    @ObservedObject private var stress = StressStore.shared
    /// 飲食、喝水有變動時重新算今天的進度
    let refreshKey: Int

    var body: some View {
        let event = adventure.todayEvent
        let pending = adventure.todayUnclaimed.values.reduce(0, +)
        PixelWindow(title: "冒險") {
            Button { adventure.showMorning = true } label: {
                HStack(spacing: 10) {
                    PixelSprite(art: .moon, size: 20)
                    if let score = adventure.score {
                        Text("睡眠分數")
                        Text("\(score.total)").foregroundStyle(Color.water).monospacedDigit()
                        PixelChip(text: score.rating, color: .water)
                    } else {
                        Text("昨晚沒有睡眠資料").foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    Text("夢境報告").font(.px(12)).foregroundStyle(Color.soft)
                    PixelSprite(art: .cursor, size: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            PixelDivider()

            HStack(alignment: .top, spacing: 10) {
                PixelSprite(art: event.art, size: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                    Text(event.detail)
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if adventure.today.eventDone(event) {
                    PixelChip(text: "達成", color: .move)
                }
            }

            if stress.fogActive {
                PixelDivider()
                HStack(spacing: 10) {
                    PixelSprite(art: .monsterFog, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("焦慮霧出現了").foregroundStyle(Color.fat)
                        Text("今天身體有點緊繃，想吃零食時先喝杯水。").font(.px(12)).foregroundStyle(Color.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button("呼吸驅散") { stress.showBreathing = true }
                        .buttonStyle(.pixel(.primary, fontSize: 12))
                }
            }

            PixelDivider()

            NavigationLink {
                WorldMapView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 10) {
                    PixelSprite(art: journey.currentRegion.landmark, size: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("旅程 \(WorldMapView.km(journey.kilometers)) km")
                        if let next = journey.nextRegion {
                            Text("\(next.title)還有 \(WorldMapView.km(next.journeyKm - journey.kilometers)) km")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                        }
                    }
                    Spacer(minLength: 4)
                    if !journey.newEncounters.isEmpty {
                        PixelChip(text: "見聞 ×\(journey.newEncounters.count)", color: .carbs)
                    }
                    Text("大陸地圖").font(.px(12)).foregroundStyle(Color.soft)
                    PixelSprite(art: .cursor, size: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            PixelDivider()

            NavigationLink {
                FootprintView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 10) {
                    PixelSprite(art: .footprint, size: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("出發冒險")
                        Text("記錄散步、跑步路線・已開拓 \(RouteStore.shared.cellCount) 格")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    Text("足跡").font(.px(12)).foregroundStyle(Color.soft)
                    PixelSprite(art: .cursor, size: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let goal = adventure.todayGoal {
                HStack(spacing: 10) {
                    PixelSprite(art: goal.art, size: 20)
                    Text("今天的小目標：\(goal.title)")
                    Spacer(minLength: 0)
                }
            }

            PixelDivider()

            HStack(spacing: 10) {
                PixelSprite(art: .coin, size: 20)
                Text("元氣幣 \(adventure.balance)").monospacedDigit()
                if pending > 0 {
                    Text("今天 +\(pending)").font(.px(12)).foregroundStyle(Color.carbs)
                }
                Spacer(minLength: 4)
                Button(adventure.campfireAvailable ? "升營火" : "18:00 營火") { adventure.showCampfire = true }
                    .buttonStyle(.pixel(adventure.campfireAvailable ? .primary : .secondary, fontSize: 12))
                    .disabled(!adventure.campfireAvailable)
            }
        }
        .task(id: refreshKey) { await adventure.refreshToday() }
    }
}

// MARK: - 起床夢境結算

struct MorningReportView: View {
    var onDone: () -> Void
    @ObservedObject private var adventure = AdventureStore.shared
    @AppStorage(SettingKey.companionName) private var companionName = "小卡"
    @State private var result: (sleep: Int, meteor: Bool, perk: Int, yesterday: Int)?
    @State private var eventRevealed = false
    @State private var showManualSleep = false

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 4) {
                        Text("夢境結算").font(.px(24))
                        Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    CompanionSpeech(name: companionName, text: Self.morningLine(adventure.score, adventure.lastNight))

                    sleepWindow
                    coinWindow

                    if let goal = adventure.todayGoal {
                        PixelWindow(title: "昨晚說好的小目標", tint: .move) {
                            HStack(spacing: 10) {
                                PixelSprite(art: goal.art, size: 24)
                                Text("今天要\(goal.title)！")
                            }
                        }
                    }

                    eventWindow

                    Button("出發冒險！") { onDone() }
                        .buttonStyle(.pixel(.primary, fullWidth: true))
                }
                .padding(20)
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task { result = await adventure.claimMorning() }
        .sheet(isPresented: $showManualSleep, onDismiss: {
            Task {
                await adventure.refresh()
                result = await adventure.claimMorning()
            }
        }) { ManualSleepSheet() }
    }

    private var sleepWindow: some View {
        PixelWindow(title: "昨晚的睡眠", tint: .water) {
            if let night = adventure.lastNight, let score = adventure.score {
                HStack(alignment: .center, spacing: 12) {
                    Text("\(score.total)").font(.px(48)).foregroundStyle(Color.water).monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        PixelChip(text: score.rating, color: .water)
                        Text(night.isManual ? "手動補記" : "Apple Watch").font(.px(12)).foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(SpiritDexView.duration(night.asleep))
                        Text("\(night.start.formatted(date: .omitted, time: .shortened))–\(night.end.formatted(date: .omitted, time: .shortened))")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                }
                ForEach(score.parts, id: \.title) { part in
                    HStack(spacing: 8) {
                        Text(part.title).font(.px(12)).frame(width: 96, alignment: .leading)
                        PixelBar(value: Double(part.value), total: Double(part.max), color: .water,
                                 segments: 8, height: 6, overIsBad: false)
                        Text("\(part.value)／\(part.max)").font(.px(12)).monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                if night.deep + night.rem > 0 {
                    Text("深層 \(Self.short(night.deep))・快速動眼 \(Self.short(night.rem))・清醒 \(Self.short(night.awake))")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
                if score.isEstimated {
                    Text("最近的睡眠資料比較少，部分項目是估計的。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
                if let type = adventure.chronotype {
                    PixelDivider()
                    HStack(alignment: .top, spacing: 8) {
                        PixelChip(text: type.title, color: .brand)
                        Text(type.advice).font(.px(12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("昨晚沒有睡眠資料。戴 Apple Watch 睡覺會自動記錄，也可以手動補記（算半晚）。")
                    .fixedSize(horizontal: false, vertical: true)
                Button("補記昨晚的睡眠") { showManualSleep = true }
                    .buttonStyle(.pixel(.secondary, fullWidth: true))
            }
        }
    }

    private var coinWindow: some View {
        PixelWindow(title: "夢境能量", tint: .carbs) {
            if let result {
                row("夢境能量", result.sleep, badge: result.meteor ? "流星雨加倍" : nil)
                if result.perk > 0, let active = CampStore.shared.activePerk {
                    row("夥伴特性：\(active.skin.title)", result.perk, badge: nil)
                }
                if result.yesterday > 0 { row("昨天的冒險獎勵", result.yesterday, badge: nil) }
                PixelDivider()
                HStack(spacing: 8) {
                    PixelSprite(art: .coin, size: 16)
                    Text("元氣幣 \(adventure.balance)").monospacedDigit()
                }
            } else {
                PixelLoadingDots()
            }
        }
    }

    private func row(_ title: String, _ coins: Int, badge: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
            if let badge { PixelChip(text: badge, color: .carbs) }
            Spacer(minLength: 4)
            Text("+\(coins)").foregroundStyle(Color.carbs).monospacedDigit()
        }
    }

    private var eventWindow: some View {
        let event = adventure.todayEvent
        return PixelWindow(title: "今日事件", tint: .brand) {
            if eventRevealed {
                HStack(alignment: .top, spacing: 10) {
                    PixelSprite(art: event.art, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                        Text(event.detail).font(.px(12)).foregroundStyle(Color.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Button("翻開今日事件") { withAnimation(.easeOut(duration: 0.25)) { eventRevealed = true } }
                    .buttonStyle(.pixel(.secondary, fullWidth: true))
            }
        }
    }

    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60):\(String(format: "%02d", minutes % 60))" : "\(minutes) 分"
    }

    /// 小夥伴早安的話：沒睡好時提醒隔天比較容易餓
    static func morningLine(_ score: SleepScore?, _ night: SleepNight?) -> String {
        guard let score, let night else {
            return "早安！昨晚沒看到你的睡眠紀錄。戴著手錶睡覺，我就能幫你看夢境喔。"
        }
        if night.hours < 6 {
            return "昨晚睡不到 6 小時，今天會比較容易餓。先吃蛋白質和蔬菜，晚上早點休息喔。"
        }
        switch score.total {
        case 85...: return "睡得真好！精神滿滿，今天一起出發冒險吧！"
        case 70..<85: return "睡得還不錯，今天也一起加油。"
        default: return "昨晚睡得普普，今天多喝水、午餐吃飽一點，比較不會想亂吃零食。"
        }
    }
}

// MARK: - 睡前營火

struct CampfireView: View {
    var onDone: () -> Void
    @ObservedObject private var adventure = AdventureStore.shared
    @AppStorage(SettingKey.companionName) private var companionName = "小卡"
    @State private var collected: Int?

    var body: some View {
        let today = adventure.today
        let event = adventure.todayEvent
        let coins = adventure.dayCoins(today, event: event)
        let perkName = CampStore.shared.activePerk?.skin.title
        let pending = adventure.todayUnclaimed.values.reduce(0, +)
        ZStack {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 4) {
                        Text("營火").font(.px(24))
                        Text("今天的冒險到這裡").font(.px(12)).foregroundStyle(Color.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    HStack(alignment: .bottom, spacing: 12) {
                        CompanionAvatar(size: 64)
                        TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
                            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.35)
                            PixelSprite(art: tick % 2 == 0 ? .campfire : .campfireFlicker, size: 96)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    CompanionSpeech(name: companionName, text: Self.story(today, event: event), showsAvatar: false)

                    PixelWindow(title: "今天的元氣幣", tint: .carbs) {
                        ForEach(CoinSource.allCases.filter { ![.sleep, .journey, .calm, .boss, .review, .explore].contains($0) && ($0 != .perk || coins[.perk] != nil) }, id: \.self) { source in
                            HStack {
                                Text(source == .event ? "\(source.title)：\(event.title)"
                                     : source == .perk ? "\(source.title)：\(perkName ?? "")" : source.title)
                                    .foregroundStyle((coins[source] ?? 0) > 0 ? Color.ink : Color.soft)
                                Spacer(minLength: 4)
                                Text("+\(coins[source] ?? 0)").monospacedDigit()
                                    .foregroundStyle((coins[source] ?? 0) > 0 ? Color.carbs : Color.soft)
                            }
                        }
                        PixelDivider()
                        if let collected {
                            Text(collected > 0 ? "收下了 \(collected) 枚元氣幣！" : "今天的元氣幣都收好了")
                                .foregroundStyle(Color.carbs)
                        } else if pending > 0 {
                            Button("收下 +\(pending) 元氣幣") {
                                withAnimation { collected = adventure.claimToday() }
                            }
                            .buttonStyle(.pixel(.primary, fullWidth: true))
                        } else {
                            Text("今天的元氣幣都收好了").foregroundStyle(Color.soft)
                        }
                        HStack(spacing: 8) {
                            PixelSprite(art: .coin, size: 16)
                            Text("元氣幣 \(adventure.balance)").monospacedDigit()
                        }
                    }

                    PixelWindow(title: "明天的小目標", tint: .move) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(TomorrowGoal.allCases) { goal in
                                let selected = adventure.tomorrowGoal == goal
                                Button { adventure.setTomorrowGoal(goal) } label: {
                                    HStack(spacing: 8) {
                                        PixelSprite(art: goal.art, size: 20)
                                        Text(goal.title)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(10)
                                    .pixelPanel(fill: selected ? .track : .window, border: selected ? .brand : .ink,
                                                shadow: nil, lineWidth: 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        Text("明天早上的夢境結算會提醒你。").font(.px(12)).foregroundStyle(Color.soft)
                    }

                    Text(event == .meteor
                         ? "今晚是流星雨夜，11 點前睡著，明早夢境能量加倍！"
                         : "火光暖暖的，該準備睡囉。早點放下手機，明早夢境結算見！")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)

                    if WeeklyStore.shared.reviewWeekStart != nil {
                        Button("每週回顧（+\(WeeklyStore.reviewReward) 元氣幣）") {
                            onDone()
                            WeeklyStore.shared.showReview = true
                        }
                        .buttonStyle(.pixel(.primary, fullWidth: true))
                    }

                    Button("晚安") { onDone() }
                        .buttonStyle(.pixel(.secondary, fullWidth: true))
                }
                .padding(20)
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task { await adventure.refreshToday() }
    }

    /// 小夥伴講今天的冒險
    static func story(_ today: DayProgress, event: DailyEvent) -> String {
        var lines: [String] = []
        lines.append("今天我們走了 \(Int(today.steps).formatted()) 步。")
        let meals = [MealType.breakfast, .lunch, .dinner].filter(today.loggedMeals.contains).map(\.title)
        lines.append(meals.isEmpty ? "今天還沒記錄三餐，明天記得跟我分享吃了什麼。" : "記錄了\(meals.joined(separator: "、"))。")
        lines.append(today.water >= today.waterGoal
                     ? "水喝到 \(Int(today.water)) ml，聖泉都亮起來了！"
                     : "喝了 \(Int(today.water))／\(Int(today.waterGoal)) ml 的水。")
        if event.bonus > 0 {
            lines.append(today.eventDone(event) ? "\(event.title)的任務完成了！" : "\(event.title)的任務明天再挑戰也沒關係。")
        }
        return lines.joined()
    }
}

// MARK: - 小夥伴說話

/// 小夥伴頭像＋對話框
struct CompanionSpeech: View {
    let name: String
    let text: String
    /// 畫面上已經有小夥伴時（例如營火旁）就不再放頭像
    var showsAvatar = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsAvatar { CompanionAvatar(size: 48) }
            PixelWindow(title: name.isEmpty ? "小卡" : name) {
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
