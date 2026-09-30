import SwiftUI

/// 「圖鑑」分頁：精靈圖鑑、大陸地圖、食物圖鑑
struct DexView: View {
    enum Page: String, CaseIterable, Identifiable {
        case spirits, map, foods
        var id: String { rawValue }

        var title: String {
            switch self {
            case .spirits: "精靈"
            case .map: "地圖"
            case .foods: "食物"
            }
        }
    }

    @AppStorage("dexPage") private var page = Page.spirits.rawValue

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Page.allCases) { item in
                    Button(item.title) { page = item.rawValue }
                        .buttonStyle(.pixel(page == item.rawValue ? .primary : .secondary, fullWidth: true, fontSize: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            switch Page(rawValue: page) ?? .spirits {
            case .spirits: SpiritDexView()
            case .map: WorldMapView()
            case .foods: FoodDexView()
            }
        }
        .background(Color.paper)
    }
}

// MARK: - 精靈圖鑑

struct SpiritDexView: View {
    @ObservedObject private var collection = SpiritCollection.shared
    @State private var selected: CompanionSkin?
    @State private var showManualSleep = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "精靈圖鑑", subtitle: "SPIRIT DEX") {
                        PixelChip(text: "\(collection.unlockedTotal)／\(CompanionSkin.dexOrder.count)", color: .brand)
                    }
                    todayWindow
                    ForEach(SpiritRegion.allCases) { region in
                        regionWindow(region).id(region)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            #if DEBUG
            // 開發用：-dexRegion royalCity 捲到某個區域、-spirit dragon 打開某隻精靈（模擬器截圖檢查畫面）
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-dexRegion"), index + 1 < arguments.count,
                   let region = SpiritRegion(rawValue: arguments[index + 1]) {
                    try? await Task.sleep(for: .milliseconds(300))
                    reader.scrollTo(region, anchor: .top)
                }
                if let index = arguments.firstIndex(of: "-spirit"), index + 1 < arguments.count {
                    selected = CompanionSkin(rawValue: arguments[index + 1])
                }
            }
            #endif
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await collection.evaluate() }
            .sheet(item: $selected) { SpiritDetailSheet(skin: $0) }
            .sheet(isPresented: $showManualSleep) { ManualSleepSheet() }
        }
    }

    // MARK: 今日冒險

    private var todayWindow: some View {
        PixelWindow(title: "今日冒險") {
            HStack(spacing: 10) {
                PixelSprite(art: .footprint, size: 20)
                Text("今天走了")
                Spacer(minLength: 4)
                Text("\(collection.todaySteps.rounded0) 步").foregroundStyle(Color.move).monospacedDigit()
            }
            PixelDivider()
            HStack(alignment: .top, spacing: 10) {
                PixelSprite(art: .moon, size: 20)
                if let night = collection.lastNight {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("昨晚睡了 \(Self.duration(night.asleep))")
                        Text("\(night.start.formatted(date: .omitted, time: .shortened))–\(night.end.formatted(date: .omitted, time: .shortened))")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    PixelChip(text: night.isManual ? "手動・半晚" : "手錶", color: night.isManual ? .soft : .water)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("沒有昨晚的睡眠資料")
                        Text("戴 Apple Watch 睡覺會自動記錄")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    Button("補記") { showManualSleep = true }
                        .buttonStyle(.pixel(.secondary, fontSize: 12))
                }
            }
            PixelDivider()
            HStack(spacing: 12) {
                PixelChip(text: "精靈 \(collection.unlockedTotal)", color: .brand)
                PixelChip(text: "閃光 \(collection.shinyTotal)", color: .carbs)
                Spacer(minLength: 0)
                Text("\(collection.state.start.formatted(.dateTime.month().day())) 起計算")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) 小時 \(minutes % 60) 分"
    }

    // MARK: 區域

    private func regionWindow(_ region: SpiritRegion) -> some View {
        PixelWindow(title: region.title, tint: region.color) {
            HStack(spacing: 8) {
                PixelSprite(art: region.art, size: 16)
                Text(region.detail)
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(region.spirits) { skin in
                    Button { selected = skin } label: { SpiritCard(skin: skin) }
                        .buttonStyle(.plain)
                }
            }
            if region == .festival, let next = Festival.allCases.compactMap({ festival in festival.upcoming().map { (festival, $0) } })
                .min(by: { $0.1.start < $1.1.start }) {
                HStack(spacing: 8) {
                    PixelSprite(art: next.0.decorationArt, size: 16)
                    Text(next.0.isActive() ? "\(next.0.title)活動進行中！" : "下一個節慶：\(next.0.title)")
                        .font(.px(12))
                        .foregroundStyle(next.0.isActive() ? Color.calorie : Color.soft)
                    Spacer(minLength: 4)
                    if !next.0.isActive() {
                        Text(FestivalScheduleText.range(next.1.start, next.1.end.adding(days: -1)))
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                }
            }
        }
    }
}

/// 圖鑑裡的一格
struct SpiritCard: View {
    let skin: CompanionSkin
    @ObservedObject private var collection = SpiritCollection.shared

    var body: some View {
        let unlocked = collection.unlockedDate(skin) != nil
        let shiny = collection.unlockedDate(skin, shiny: true) != nil
        VStack(spacing: 4) {
            Text("No.\(String(format: "%03d", skin.dexNumber))")
                .font(.px(12))
                .foregroundStyle(Color.soft)
            ZStack(alignment: .topTrailing) {
                if unlocked {
                    PixelSprite(art: skin.art(shiny: shiny), size: 48)
                        .overlay { if shiny { ShinySparkles(size: 48, tick: 1) } }
                } else {
                    PixelSprite(art: skin.art, size: 48, tint: .track)
                        .overlay { PixelSprite(art: .lock, size: 16) }
                }
            }
            .frame(width: 52, height: 52)
            Text(unlocked ? skin.title : "？？？")
                .font(.px(12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if unlocked {
                PixelChip(text: shiny ? "閃光" : "已喚醒", color: shiny ? .carbs : skin.region.color)
            } else {
                PixelBar(value: collection.progress(skin), total: skin.requirement.target,
                         color: skin.region.color, segments: 5, height: 6, overIsBad: false)
                    .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .pixelPanel(fill: unlocked ? .window : .paper, shadow: nil, lineWidth: 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unlocked ? "\(skin.title)\(shiny ? "，閃光版" : "")" : "還沒喚醒的精靈")
    }
}

// MARK: - 精靈詳細

struct SpiritDetailSheet: View {
    let skin: CompanionSkin
    @ObservedObject private var collection = SpiritCollection.shared
    @AppStorage(SettingKey.companionSkin) private var currentSkin = ""
    @AppStorage(SettingKey.companionShiny) private var currentShiny = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let unlocked = collection.unlockedDate(skin) != nil
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        versionCard(shiny: false)
                        versionCard(shiny: true)
                    }

                    PixelWindow(title: "No.\(String(format: "%03d", skin.dexNumber)) \(unlocked ? skin.title : "？？？")",
                                tint: skin.region.color) {
                        HStack(spacing: 8) {
                            PixelSprite(art: skin.region.art, size: 16)
                            Text(skin.region.title).font(.px(12)).foregroundStyle(Color.soft)
                        }
                        Text(unlocked ? skin.lore : skin.region == .festival
                             ? "只在\(skin.festival?.title ?? "節慶")出現的精靈。錯過了也沒關係，明年還會再來。"
                             : "還在\(skin.region.title)沉睡，達成條件就會醒過來。")
                            .fixedSize(horizontal: false, vertical: true)
                        if collection.unlockedDate(skin, shiny: true) != nil {
                            Text(skin.shinyLore)
                                .font(.px(12))
                                .foregroundStyle(Color.carbs)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let style = skin.unlocksStyle {
                            Text("喚醒後學會「\(style.title)」回話風格")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                        }
                    }

                    if unlocked { bondWindow }

                    requirementWindow(title: "喚醒條件", requirement: skin.requirement, shiny: false)
                    requirementWindow(title: "閃光條件", requirement: skin.shinyRequirement, shiny: true)
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("精靈資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }

    /// 羈絆等級、特性、羈絆故事
    private var bondWindow: some View {
        let camp = CampStore.shared
        let level = camp.bondLevel(skin)
        return PixelWindow(title: "羈絆 Lv.\(level)", tint: .protein) {
            if let progress = camp.bondProgress(skin) {
                PixelBar(value: Double(progress.current), total: Double(progress.needed), color: .protein, overIsBad: false)
                Text("再 \(progress.needed - progress.current) 點升到 Lv.\(level + 1)。帶牠當夥伴時，領到的元氣幣也會變成羈絆。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 8) {
                PixelChip(text: camp.perkActive(skin) ? "特性" : "Lv.\(CampStore.perkBondLevel) 特性",
                          color: camp.perkActive(skin) ? .move : .soft, filled: camp.perkActive(skin))
                Text(skin.perk.text).font(.px(12)).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(skin.bondStories.enumerated()), id: \.offset) { index, story in
                let needed = index == 0 ? 3 : 5
                PixelDivider()
                Text(level >= needed ? story : "羈絆 Lv.\(needed) 解鎖牠的故事")
                    .font(.px(12))
                    .foregroundStyle(level >= needed ? Color.ink : Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func versionCard(shiny: Bool) -> some View {
        let unlocked = collection.unlockedDate(skin, shiny: shiny) != nil
        let isCurrent = currentSkin == skin.rawValue && currentShiny == shiny
        return VStack(spacing: 8) {
            Text(shiny ? "閃光" : "一般").font(.px(12)).foregroundStyle(shiny ? Color.carbs : Color.soft)
            if unlocked {
                CompanionAvatar(size: 80, animated: true, look: .sprite(skin), shiny: shiny)
            } else {
                PixelSprite(art: skin.art, size: 80, tint: .track)
                    .overlay { PixelSprite(art: .lock, size: 24) }
            }
            if isCurrent {
                PixelChip(text: "目前的夥伴", color: .move)
            } else if unlocked {
                Button("帶牠出發") {
                    collection.choose(skin, shiny: shiny)
                    currentSkin = skin.rawValue
                    currentShiny = shiny
                }
                .buttonStyle(.pixel(.primary, fontSize: 12))
            } else {
                PixelChip(text: "未解鎖", color: .soft, filled: false)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .pixelPanel(fill: unlocked ? .window : .paper)
    }

    private func requirementWindow(title: String, requirement: SpiritRequirement, shiny: Bool) -> some View {
        let date = collection.unlockedDate(skin, shiny: shiny)
        let value = collection.progress(skin, shiny: shiny)
        return PixelWindow(title: title, tint: shiny ? .carbs : skin.region.color) {
            Text(requirement.text).fixedSize(horizontal: false, vertical: true)
            if case .festival(let festival, _) = requirement {
                FestivalScheduleText(festival: festival)
            }
            if case .starter = requirement {
                EmptyView()
            } else {
                PixelBar(value: value, total: requirement.target, color: shiny ? .carbs : skin.region.color, overIsBad: false)
                HStack {
                    Text("\(Self.number(value))／\(Self.number(requirement.target)) \(requirement.unit)")
                        .monospacedDigit()
                    Spacer()
                    if let date {
                        Text("\(date.formatted(.dateTime.month().day())) 達成")
                            .font(.px(12))
                            .foregroundStyle(Color.move)
                    }
                }
                .font(.px(12))
            }
            if shiny, collection.unlockedDate(skin) == nil {
                Text("要先喚醒一般版，才會出現閃光版。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
        }
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? Int(value).formatted() : value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - 喚醒慶祝

struct SpiritCelebrationView: View {
    let celebration: SpiritCollection.Celebration
    var onDone: () -> Void

    var body: some View {
        let skin = celebration.skin
        ZStack {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text(celebration.shiny ? "閃光精靈出現了！" : "精靈甦醒了！")
                        .font(.px(24))
                        .foregroundStyle(celebration.shiny ? Color.carbs : Color.ink)
                        .padding(.top, 40)
                    HStack(spacing: 16) {
                        PixelSprite(art: .star, size: 20)
                        CompanionAvatar(size: 144, animated: true, look: .sprite(skin), shiny: celebration.shiny)
                        PixelSprite(art: .star, size: 20)
                    }
                    PixelWindow(title: "No.\(String(format: "%03d", skin.dexNumber)) \(celebration.shiny ? "閃光" : "")\(skin.title)",
                                tint: celebration.shiny ? .carbs : skin.region.color) {
                        HStack(spacing: 8) {
                            PixelSprite(art: skin.region.art, size: 16)
                            Text(skin.region.title).font(.px(12)).foregroundStyle(Color.soft)
                        }
                        Text(celebration.shiny ? skin.shinyLore : skin.lore)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("達成：\((celebration.shiny ? skin.shinyRequirement : skin.requirement).text)")
                            .font(.px(12))
                            .foregroundStyle(Color.move)
                            .fixedSize(horizontal: false, vertical: true)
                        if !celebration.shiny, let style = skin.unlocksStyle {
                            Text("學會了「\(style.title)」回話風格！")
                                .font(.px(12))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    VStack(spacing: 10) {
                        Button("帶牠出發") {
                            SpiritCollection.shared.choose(skin, shiny: celebration.shiny)
                            onDone()
                        }
                        .buttonStyle(.pixel(.primary, fullWidth: true))
                        Button("先收進圖鑑") { onDone() }
                            .buttonStyle(.pixel(.secondary, fullWidth: true))
                    }
                }
                .padding(24)
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }
}

// MARK: - 手動補記睡眠

struct ManualSleepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bedtime = Date.at(minutes: 23 * 60 + 30)
    @State private var wake = Date.at(minutes: 7 * 60 + 30)

    /// 睡著時間在中午以後的算前一天
    private var bedDate: Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return Date.at(minutes: minutes, on: minutes >= 12 * 60 ? Date.now.adding(days: -1) : .now)
    }

    private var wakeDate: Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: wake)
        return Date.at(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    var body: some View {
        let length = wakeDate.timeIntervalSince(bedDate)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelWindow(title: "昨晚的睡眠") {
                        DatePicker("幾點睡著", selection: $bedtime, displayedComponents: .hourAndMinute)
                        DatePicker("幾點起床", selection: $wake, displayedComponents: .hourAndMinute)
                        PixelDivider()
                        Text(length > 0 ? "共 \(SpiritDexView.duration(length))" : "起床時間要比睡著時間晚")
                            .foregroundStyle(length > 0 ? Color.ink : Color.danger)
                    }
                    Text("手動補記只算半晚；戴 Apple Watch 睡覺，資料會自動記錄並算一整晚。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("補記") {
                        ManualSleepStore.save(start: bedDate, end: wakeDate)
                        Task { await SpiritCollection.shared.evaluate() }
                        dismiss()
                    }
                    .buttonStyle(.pixel(.primary, fullWidth: true))
                    .disabled(length <= 0 || length > 16 * 3600)
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("補記睡眠")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }
}
