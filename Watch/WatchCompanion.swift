import SwiftUI
import WatchKit

/// 手錶第一頁：iPhone 上帶著的精靈，會眨眼、跳動，點一下摸摸頭
struct CompanionPage: View {
    @EnvironmentObject private var store: WatchStore
    @State private var petLine: String?
    @State private var hearts = 0

    var body: some View {
        let summary = store.today
        let skin = summary.companion.flatMap(CompanionSkin.init(rawValue:)) ?? .onigiri
        let shiny = summary.companionShiny ?? false
        VStack(spacing: 6) {
            Button {
                pet(summary)
            } label: {
                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                    let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 2)
                    PixelSprite(art: skin.art(shiny: shiny, blink: tick % 8 == 0), size: 64)
                        .offset(y: tick % 2 == 0 ? -2 : 0)
                        .overlay(alignment: .topTrailing) {
                            if shiny { PixelSprite(art: .star, size: 12).opacity(tick % 3 == 0 ? 0.3 : 1) }
                        }
                        .overlay(alignment: .top) {
                            if hearts > 0 {
                                PixelSprite(art: .heart, size: 14)
                                    .offset(y: -14)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .id(hearts)
                            }
                        }
                }
                .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("摸摸\(skin.title)")

            Text(summary.companionName ?? "小卡").font(.px(12)).foregroundStyle(Color.soft)
            Text(petLine ?? Self.line(for: summary))
                .font(.px(12))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
                .frame(maxWidth: .infinity)
                .background { PixelPanel(fill: .window, shadow: nil, lineWidth: 2) }
        }
        .frame(maxWidth: .infinity)
    }

    private func pet(_ summary: DailySummary) {
        WKInterfaceDevice.current().play(.click)
        withAnimation(.easeOut(duration: 0.4)) { hearts += 1 }
        petLine = Self.petLines.randomElement()
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { petLine = nil }
        }
    }

    private static let petLines = ["嘿嘿，好舒服～", "再摸一下！", "一起去散步吧！", "今天也要加油喔！", "你的手暖暖的。"]

    /// 依今天的進度說一句話
    static func line(for summary: DailySummary) -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let waterLeft = summary.waterGoalML - summary.waterML
        let stepsLeft = summary.stepGoal - summary.steps
        if hour >= 23 || hour < 5 { return "很晚了，早點睡，夢境能量才會滿。" }
        if hour < 10, summary.waterML == 0 { return "早安！起床先喝一杯水吧。" }
        if waterLeft > 0, summary.waterML < summary.waterGoalML * Double(max(hour - 7, 0)) / 14 {
            return "口渴了嗎？再喝 \(Int(waterLeft)) ml 就達標。"
        }
        if stepsLeft > 0, hour >= 15 { return "還差 \(Int(stepsLeft).formatted()) 步，出去走走吧！" }
        if waterLeft <= 0, stepsLeft <= 0 { return "今天喝水、走路都達標了，好厲害！" }
        return "今天也一起冒險吧！"
    }
}
