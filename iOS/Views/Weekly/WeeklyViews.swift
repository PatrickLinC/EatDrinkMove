import SwiftUI

// MARK: - 今日頁：每日任務

/// 四個習慣的兩層目標、連續保底、本週頭目
struct HabitWindow: View {
    @ObservedObject private var weekly = WeeklyStore.shared
    /// 飲食、喝水有變動時重新算
    let refreshKey: Int
    @State private var showBoss = false

    var body: some View {
        PixelWindow(title: "每日任務", tint: .move) {
            ForEach(Array(Habit.allCases.enumerated()), id: \.element) { index, habit in
                if index > 0 { PixelDivider() }
                habitRow(habit)
            }
            Text("達到最低標就算保底，連續紀錄不會斷。").font(.px(12)).foregroundStyle(Color.soft)

            if let boss = weekly.boss {
                PixelDivider()
                Button { showBoss = true } label: {
                    HStack(spacing: 10) {
                        PixelSprite(art: boss.habit.boss.art, size: 32, tint: boss.defeated ? .track : nil)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(boss.defeated ? "打倒了\(boss.habit.boss.name)！" : "本週頭目：\(boss.habit.boss.name)")
                            PixelBar(value: Double(weekly.bossHP), total: Double(WeeklyStore.bossHP), color: .protein,
                                     segments: 10, height: 6, overIsBad: false)
                        }
                        Text("HP \(weekly.bossHP)").font(.px(12)).monospacedDigit()
                        PixelSprite(art: .cursor, size: 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if weekly.reviewWeekStart != nil {
                Button("每週回顧（+\(WeeklyStore.reviewReward) 元氣幣）") { weekly.showReview = true }
                    .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
            }
        }
        .task(id: refreshKey) { await weekly.refresh() }
        .sheet(isPresented: $showBoss) { BossView() }
    }

    private func habitRow(_ habit: Habit) -> some View {
        let progress = weekly.today[habit]
        let tier = progress?.tier ?? .none
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PixelSprite(art: habit.art, size: 16)
                Text(habit.title)
                Spacer(minLength: 4)
                if let streak = weekly.streaks[habit], streak > 1 {
                    Text("連續 \(streak) 天").font(.px(12)).foregroundStyle(Color.soft)
                }
                if tier != .none {
                    PixelChip(text: tier.title, color: tier == .ideal ? .carbs : habit.color)
                }
            }
            if let progress {
                TwoTierBar(value: progress.value, floor: progress.floor, ideal: progress.ideal, color: habit.color)
                HStack {
                    Text(habit.format(progress.value)).monospacedDigit()
                    Spacer()
                    Text("最低 \(habit.format(progress.floor))・理想 \(habit.format(progress.ideal))")
                        .foregroundStyle(Color.soft)
                }
                .font(.px(12))
            }
        }
    }
}

/// 進度條上標出最低標的位置
struct TwoTierBar: View {
    let value: Double
    let floor: Double
    let ideal: Double
    let color: Color

    var body: some View {
        PixelBar(value: value, total: ideal, color: color, segments: 10, height: 8, overIsBad: false)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let x = geometry.size.width * CGFloat(min(max(floor / max(ideal, 1), 0), 1))
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 3, height: geometry.size.height + 8)
                        .position(x: x, y: geometry.size.height / 2)
                }
            }
            .accessibilityLabel("最低標 \(Int(floor))，理想標 \(Int(ideal))")
    }
}

// MARK: - 頭目戰

struct BossView: View {
    @ObservedObject private var weekly = WeeklyStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let boss = weekly.boss {
                        VStack(spacing: 12) {
                            PixelSprite(art: boss.habit.boss.art, size: 128, tint: boss.defeated ? .track : nil)
                            Text(boss.defeated ? "打倒了\(boss.habit.boss.name)！" : boss.habit.boss.name).font(.px(24))
                            PixelBar(value: Double(weekly.bossHP), total: Double(WeeklyStore.bossHP), color: .protein, overIsBad: false)
                            Text("HP \(weekly.bossHP)／\(WeeklyStore.bossHP)").font(.px(12)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)

                        PixelWindow(title: "弱點", tint: .protein) {
                            HStack(spacing: 8) {
                                PixelSprite(art: boss.habit.art, size: 20)
                                Text("\(boss.habit.title)：這個習慣的傷害加倍")
                            }
                            Text("牠是上週最弱的習慣變成的。這週把\(boss.habit.title)守住，就能把牠打跑。")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        PixelWindow(title: "這週的戰況") {
                            HStack(alignment: .bottom, spacing: 6) {
                                ForEach(0..<7, id: \.self) { offset in
                                    let day = weekly.weekStart.adding(days: offset)
                                    let damage = weekly.week[day].map { tiers in
                                        tiers.reduce(0) { $0 + $1.value.damage * ($1.key == boss.habit ? 2 : 1) }
                                    }
                                    VStack(spacing: 4) {
                                        Text(damage.map { "-\($0)" } ?? "").font(.px(12)).foregroundStyle(Color.protein)
                                        Rectangle()
                                            .fill(damage == nil ? Color.track : Color.protein)
                                            .frame(height: max(CGFloat(damage ?? 0) * 2.4, 4))
                                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.px(12))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 110, alignment: .bottom)
                        }
                    }

                    PixelWindow(title: "規則") {
                        Text("每天每個習慣：達到最低標打 3 點、理想標打 5 點，弱點習慣再加倍。")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("整週都守住最低標就打得贏。打贏得到 \(WeeklyStore.bossReward) 元氣幣；沒打贏頭目只是逃走，下週再來，不會有任何懲罰。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("週末頭目戰")
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
}

// MARK: - 每週回顧

struct WeeklyReviewView: View {
    var onDone: () -> Void
    @ObservedObject private var weekly = WeeklyStore.shared
    @AppStorage(SettingKey.companionName) private var companionName = "小卡"
    @State private var step = 0
    @State private var bestDay: Date?
    @State private var stuck: Habit?
    @State private var noStuck = false
    @State private var adjust = 0
    @State private var reward: Int?

    private var start: Date { weekly.reviewWeekStart ?? weekly.weekStart }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 4) {
                        Text("每週回顧").font(.px(24))
                        Text("\(start.formatted(.dateTime.month().day()))–\(start.adding(days: 6).formatted(.dateTime.month().day()))")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    if let reward {
                        CompanionSpeech(name: companionName, text: summary)
                        HStack(spacing: 6) {
                            PixelSprite(art: .coin, size: 16)
                            Text("+\(reward) 元氣幣").foregroundStyle(Color.carbs)
                        }
                        Button("完成") { onDone() }
                            .buttonStyle(.pixel(.primary, fullWidth: true))
                    } else {
                        CompanionSpeech(name: companionName, text: question)
                        switch step {
                        case 0: dayPicker
                        case 1: habitPicker
                        default: adjustPicker
                        }
                        HStack(spacing: 10) {
                            if step > 0 {
                                Button("上一題") { step -= 1 }
                                    .buttonStyle(.pixel(.secondary, fullWidth: true))
                            }
                            Button(step == 2 || (step == 1 && noStuck) ? "送出" : "下一題") { next() }
                                .buttonStyle(.pixel(.primary, fullWidth: true))
                        }
                        Button("之後再說") { onDone() }
                            .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                    }
                }
                .padding(20)
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .onAppear { stuck = weekly.weakest(weekStart: start) }
    }

    private var question: String {
        switch step {
        case 0: "這週辛苦了！先想想看，這週哪一天最順？"
        case 1: "那這週卡在哪裡呢？我猜是\(weekly.weakest(weekStart: start)?.title ?? "某個習慣")，對嗎？"
        default: "\(stuck?.title ?? "這個習慣")下週的最低標要調整嗎？調低一點比較容易保住連續紀錄喔。"
        }
    }

    private var summary: String {
        var text = "收到！"
        if let bestDay { text += "\(bestDay.formatted(.dateTime.weekday(.wide)))的你超棒，" }
        if let stuck, adjust != 0 {
            text += "下週\(stuck.title)的最低標改成 \(stuck.format(stuck.floor(level: weekly.floorLevel(stuck))))。"
        } else {
            text += "下週照這個步調繼續。"
        }
        return text + "我們一起加油！"
    }

    private var dayPicker: some View {
        let scores = weekly.dayScores(weekStart: start)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = start.adding(days: offset)
                let selected = bestDay == day
                // 四個習慣的達成換成 0–4 顆星
                let stars = min(((scores[day] ?? 0) + 1) / 2, 4)
                Button { bestDay = day } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        HStack(spacing: 1) {
                            ForEach(0..<4, id: \.self) { index in
                                PixelSprite(art: .star, size: 10, tint: index < stars ? nil : .track)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .pixelPanel(fill: selected ? .track : .window, border: selected ? .brand : .ink, shadow: nil, lineWidth: 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var habitPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(Habit.allCases) { habit in
                choice(habit.title, art: habit.art, selected: !noStuck && stuck == habit) {
                    stuck = habit
                    noStuck = false
                }
            }
            choice("都還好", art: .star, selected: noStuck) {
                noStuck = true
                stuck = nil
            }
        }
    }

    private var adjustPicker: some View {
        VStack(spacing: 8) {
            if let stuck {
                let level = weekly.floorLevel(stuck)
                ForEach([(-1, "調低一點"), (0, "維持"), (1, "調高一點")], id: \.0) { value, title in
                    let newLevel = min(max(level + value, -2), 2)
                    choice("\(title)：\(stuck.format(stuck.floor(level: newLevel)))", art: stuck.art, selected: adjust == value) {
                        adjust = value
                    }
                }
            }
        }
    }

    private func choice(_ title: String, art: PixelArt, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PixelSprite(art: art, size: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(10)
            .pixelPanel(fill: selected ? .track : .window, border: selected ? .brand : .ink, shadow: nil, lineWidth: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func next() {
        if step == 0 {
            step = 1
        } else if step == 1 && !noStuck {
            step = 2
        } else {
            withAnimation {
                reward = weekly.submitReview(weekStart: start, bestDay: bestDay, stuck: noStuck ? nil : stuck,
                                             adjust: noStuck ? 0 : adjust)
            }
        }
    }
}

// MARK: - 冒險編年史（戰績頁）

struct ChronicleWindow: View {
    @ObservedObject private var weekly = WeeklyStore.shared
    @State private var selected: WeeklyStore.Chronicle?

    var body: some View {
        PixelWindow(title: "冒險編年史", tint: .brand, spacing: 0) {
            let items = (weekly.current.map { [$0] } ?? []) + weekly.chronicles
            if items.isEmpty {
                Text("每週會自動整理成一章冒險日誌。").font(.px(12)).foregroundStyle(Color.soft)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, chronicle in
                if index > 0 { PixelDivider() }
                Button { selected = chronicle } label: {
                    HStack(spacing: 10) {
                        PixelSprite(art: .book, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ChronicleCard.title(chronicle.weekStart) + (index == 0 && weekly.current != nil ? "（進行中）" : ""))
                            Text("\(Int(chronicle.steps).formatted()) 步・保底 \(chronicle.floorDays) 天")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                        }
                        Spacer(minLength: 4)
                        PixelSprite(art: .cursor, size: 12)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { ChronicleSheet(chronicle: $0) }
    }
}

struct ChronicleSheet: View {
    let chronicle: WeeklyStore.Chronicle
    @Environment(\.dismiss) private var dismiss
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ChronicleCard(chronicle: chronicle)
                    if let image {
                        ShareLink(item: image, preview: SharePreview(ChronicleCard.title(chronicle.weekStart), image: image)) {
                            Text("存成圖片分享")
                        }
                        .buttonStyle(.pixel(.primary, fullWidth: true))
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("冒險編年史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task {
            let renderer = ImageRenderer(content: ChronicleCard(chronicle: chronicle).frame(width: 360).padding(12).background(Color.paper))
            renderer.scale = 3
            if let uiImage = renderer.uiImage { image = Image(uiImage: uiImage) }
        }
    }
}

/// 一週的冒險日誌卡片（也用來存成圖片）
struct ChronicleCard: View {
    let chronicle: WeeklyStore.Chronicle

    static func title(_ start: Date) -> String {
        "\(start.formatted(.dateTime.month().day())) 那週的冒險"
    }

    var body: some View {
        PixelWindow(title: Self.title(chronicle.weekStart)) {
            HStack(spacing: 10) {
                CompanionAvatar(size: 40, animated: false)
                Text("\(AppBrand.name)・冒險日誌").font(.px(12)).foregroundStyle(Color.soft)
            }
            row(.footprint, "走了", "\(Int(chronicle.steps).formatted()) 步")
            row(.moon, "平均睡眠分數", chronicle.sleepAverage.map { "\(Int($0.rounded()))" } ?? "—")
            row(.star, "保底的日子", "\(chronicle.floorDays) 天（完美 \(chronicle.idealDays) 天）")
            if let best = chronicle.bestDay {
                row(.sun, "最順的一天", best.formatted(.dateTime.month().day().weekday(.wide)))
            }
            if !chronicle.spirits.isEmpty {
                row(.book, "喚醒的精靈", chronicle.spirits.joined(separator: "、"))
            }
            if let boss = chronicle.boss {
                HStack(spacing: 10) {
                    PixelSprite(art: boss.habit.boss.art, size: 32, tint: boss.defeated ? .track : nil)
                    let ongoing = chronicle.weekStart >= AppSettings.startOfWeek(.now)
                    Text(boss.defeated ? "打倒了\(boss.habit.boss.name)！"
                         : ongoing ? "正在對戰\(boss.habit.boss.name)（HP \(max(WeeklyStore.bossHP - boss.damage, 0))）"
                         : "\(boss.habit.boss.name)逃走了，下次再戰")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func row(_ art: PixelArt, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            PixelSprite(art: art, size: 16)
            Text(title).font(.px(12)).foregroundStyle(Color.soft)
            Spacer(minLength: 4)
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
