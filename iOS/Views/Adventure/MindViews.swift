import SwiftUI

// MARK: - 精神力詳細

struct StressDetailView: View {
    @ObservedObject private var stress = StressStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let reading = stress.reading {
                        mpWindow(reading)
                        measureWindow(reading)
                        historyWindow
                    } else {
                        PixelWindow(title: "建立基準中", tint: .fat) {
                            Text("已經有 \(min(stress.baselineDays, StressStore.baselineDaysNeeded))／\(StressStore.baselineDaysNeeded) 天的心率變異度資料。")
                            PixelBar(value: Double(stress.baselineDays), total: Double(StressStore.baselineDaysNeeded),
                                     color: .fat, overIsBad: false)
                            Text("戴著 Apple Watch 生活、睡覺，手錶會自動量。累積一週後，就能跟你自己的平常狀態比較。")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button("一分鐘呼吸") {
                        dismiss()
                        stress.showBreathing = true
                    }
                    .buttonStyle(.pixel(.primary, fullWidth: true))

                    PixelWindow(title: "精神力是什麼？") {
                        Text("心率變異度（HRV）是心跳和心跳之間間隔的變化。休息夠、壓力小的時候通常比較高；累了、壓力大、沒睡好的時候會變低。")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("每個人的 HRV 差很多，所以這裡只跟你自己過去 30 天比：HRV 比平常低、靜止心率比平常高，精神力就會下降。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("這只是生活參考，不是醫療判斷。身體不舒服請找醫師。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("精神力")
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

    private func mpWindow(_ reading: StressReading) -> some View {
        PixelWindow(title: "今天的精神力", tint: .fat) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(reading.mp)").font(.px(48)).foregroundStyle(Color.fat).monospacedDigit()
                VStack(alignment: .leading, spacing: 4) {
                    PixelChip(text: reading.level.title, color: .fat)
                    Text("MP／100").font(.px(12)).foregroundStyle(Color.soft)
                }
                Spacer()
                if reading.level.summonsFog {
                    PixelSprite(art: .monsterFog, size: 48)
                }
            }
            PixelBar(value: Double(reading.mp), total: 100, color: .fat, overIsBad: false)
            Text(reading.level.advice).fixedSize(horizontal: false, vertical: true)
            if reading.level.summonsFog {
                Text(stress.calmedToday ? "今天已經做過呼吸，焦慮霧散去了。" : "焦慮霧出現了！做一分鐘呼吸就能驅散。")
                    .font(.px(12))
                    .foregroundStyle(stress.calmedToday ? Color.move : Color.fat)
            }
        }
    }

    private func measureWindow(_ reading: StressReading) -> some View {
        PixelWindow(title: "今天和平常") {
            HStack {
                Text("心率變異度")
                Spacer()
                Text("\(Int(reading.hrv.rounded())) ms").monospacedDigit()
                Text("平常 \(Int(reading.hrvBaseline.rounded()))").font(.px(12)).foregroundStyle(Color.soft)
            }
            if let resting = reading.restingHeartRate, let baseline = reading.restingBaseline {
                HStack {
                    Text("靜止心率")
                    Spacer()
                    Text("\(Int(resting.rounded())) 下／分").monospacedDigit()
                    Text("平常 \(Int(baseline.rounded()))").font(.px(12)).foregroundStyle(Color.soft)
                }
            }
            Text("\(reading.measuredAt.formatted(date: .omitted, time: .shortened)) 的最新資料，比較的是過去 30 天。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
    }

    private var historyWindow: some View {
        PixelWindow(title: "最近 7 天") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    let day = Date.now.adding(days: -offset).startOfDay
                    let mp = stress.history[day]
                    VStack(spacing: 4) {
                        Text(mp.map(String.init) ?? "—").font(.px(12)).foregroundStyle(Color.soft).monospacedDigit()
                        Rectangle()
                            .fill(mp == nil ? Color.track : Color.fat)
                            .frame(height: max(CGFloat(mp ?? 0) * 0.8, 4))
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.px(12))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
    }
}

// MARK: - 一分鐘呼吸

/// 吸 4 秒、吐 6 秒，一分鐘 6 次；方塊跟著變大變小，小夥伴坐在中間
struct BreathingView: View {
    var onDone: () -> Void
    @State private var startedAt: Date?
    @State private var finished: (coins: Int, fogCleared: Bool)?
    @State private var phaseIndex = 0

    private static let duration: TimeInterval = 60
    private static let inhale: TimeInterval = 4
    private static let cycle: TimeInterval = 10

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("一分鐘呼吸").font(.px(24))
                    Text("吸氣 4 秒、吐氣 6 秒，跟著方塊呼吸").font(.px(12)).foregroundStyle(Color.soft)
                }
                .padding(.top, 32)

                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    let elapsed = startedAt.map { min(timeline.date.timeIntervalSince($0), Self.duration) } ?? 0
                    breathScene(elapsed: elapsed)
                        .onChange(of: Int(elapsed / Self.cycle * 2) + (elapsed.truncatingRemainder(dividingBy: Self.cycle) < Self.inhale ? 0 : 1)) { _, value in
                            phaseIndex = value
                        }
                        .onChange(of: elapsed >= Self.duration) { _, done in
                            if done { finish() }
                        }
                }
                Spacer(minLength: 0)

                if let finished {
                    PixelWindow(title: "完成！", tint: .move) {
                        Text(finished.fogCleared ? "焦慮霧散去了，心情平靜多了。" : "做得很好，心情平靜多了。")
                        if finished.coins > 0 {
                            HStack(spacing: 6) {
                                PixelSprite(art: .coin, size: 16)
                                Text("+\(finished.coins) 元氣幣").foregroundStyle(Color.carbs)
                            }
                        }
                        Text("已經記錄到「健康」的正念分鐘。").font(.px(12)).foregroundStyle(Color.soft)
                    }
                    Button("完成") { onDone() }
                        .buttonStyle(.pixel(.primary, fullWidth: true))
                } else if startedAt == nil {
                    Button("開始") {
                        startedAt = .now
                    }
                    .buttonStyle(.pixel(.primary, fullWidth: true))
                    Button("先不要") { onDone() }
                        .buttonStyle(.pixel(.secondary, fullWidth: true))
                } else {
                    Button("提早結束") { onDone() }
                        .buttonStyle(.pixel(.secondary, fullWidth: true))
                }
            }
            .padding(24)
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .sensoryFeedback(.impact(weight: .light), trigger: phaseIndex)
        #if DEBUG
        // 開發用：-breathingRun 直接從第 2 秒開始（截圖檢查進行中的畫面）
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-breathingRun") { startedAt = Date.now.addingTimeInterval(-2) }
        }
        #endif
    }

    @ViewBuilder
    private func breathScene(elapsed: TimeInterval) -> some View {
        let running = startedAt != nil && finished == nil
        let inCycle = elapsed.truncatingRemainder(dividingBy: Self.cycle)
        let inhaling = inCycle < Self.inhale
        let scale = !running ? 0.4 : inhaling ? inCycle / Self.inhale : 1 - (inCycle - Self.inhale) / (Self.cycle - Self.inhale)
        // 大小一格一格變（8 點一格），比較像像素遊戲
        let side = ((80 + 140 * scale) / 8).rounded() * 8
        VStack(spacing: 20) {
            ZStack {
                Rectangle()
                    .fill(Color.water.opacity(0.25))
                    .frame(width: side + 32, height: side + 32)
                Rectangle()
                    .fill(Color.water.opacity(0.5))
                    .frame(width: side, height: side)
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 3))
                CompanionAvatar(size: 56, animated: false)
                // 焦慮霧：呼吸越久越淡
                PixelSprite(art: .monsterFog, size: 72)
                    .opacity(finished != nil ? 0 : 1 - elapsed / Self.duration)
                    .offset(x: 110, y: -110)
            }
            .frame(width: 260, height: 260)

            if running {
                let left = Int(((inhaling ? Self.inhale : Self.cycle) - inCycle).rounded(.up))
                Text(inhaling ? "吸氣… \(left)" : "吐氣… \(left)")
                    .font(.px(24))
                    .foregroundStyle(inhaling ? Color.water : Color.fat)
                PixelBar(value: elapsed, total: Self.duration, color: .water, overIsBad: false)
                    .padding(.horizontal, 24)
            } else if finished == nil {
                Text("準備好了就按開始").font(.px(16)).foregroundStyle(Color.soft)
            }
        }
    }

    private func finish() {
        guard finished == nil, let startedAt else { return }
        let fog = StressStore.shared.fogActive
        Task {
            let coins = await StressStore.shared.finishBreathing(start: startedAt, end: .now)
            withAnimation { finished = (coins, fog) }
        }
    }
}
