import ActivityKit
import SwiftUI
import WidgetKit

@main
struct EatDrinkMoveWidgets: WidgetBundle {
    var body: some Widget {
        RouteLiveActivity()
    }
}

// MARK: - 出發冒險：鎖定畫面與動態島

struct RouteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RouteActivityAttributes.self) { context in
            RouteLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.window)
                .activitySystemActionForegroundColor(Color.ink)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        WidgetSprite(art: attributes.art, size: 28)
                        Text(RouteActivityText.status(attributes, state))
                            .font(.px(12))
                            .foregroundStyle(RouteActivityText.statusColor(state))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(RouteActivityText.kilometers(state.distance)) 公里")
                        .font(.px(16))
                        .foregroundStyle(Color.carbs)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        RouteTimerText(state: state)
                            .font(.px(28))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("配速 \(state.pace)")
                            .font(.px(12))
                            .foregroundStyle(Color.water)
                    }
                }
            } compactLeading: {
                WidgetSprite(art: attributes.art, size: 20)
            } compactTrailing: {
                Text(RouteActivityText.kilometers(state.distance))
                    .font(.px(12))
                    .foregroundStyle(Color.carbs)
                    .monospacedDigit()
            } minimal: {
                WidgetSprite(art: attributes.art, size: 18)
            }
        }
    }
}

struct RouteLockScreenView: View {
    let attributes: RouteActivityAttributes
    let state: RouteActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            WidgetSprite(art: attributes.art, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(RouteActivityText.status(attributes, state))
                    .font(.px(12))
                    .foregroundStyle(RouteActivityText.statusColor(state))
                RouteTimerText(state: state)
                    .font(.px(30))
                    .foregroundStyle(Color.ink)
                HStack(spacing: 12) {
                    Text("\(RouteActivityText.kilometers(state.distance)) 公里").foregroundStyle(Color.move)
                    Text("配速 \(state.pace)").foregroundStyle(Color.water)
                }
                .font(.px(12))
                .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// 走路中用系統計時器自己跳秒（App 不用每秒更新）；暫停、結束時固定
struct RouteTimerText: View {
    let state: RouteActivityAttributes.ContentState

    var body: some View {
        if let frozen = state.frozenElapsed {
            Text(RouteActivityText.clock(frozen)).monospacedDigit()
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
    }
}

enum RouteActivityText {
    static func status(_ attributes: RouteActivityAttributes, _ state: RouteActivityAttributes.ContentState) -> String {
        state.finished ? "\(attributes.title)完成！" : state.frozenElapsed != nil ? "\(attributes.title)・暫停" : "\(attributes.title)中"
    }

    static func statusColor(_ state: RouteActivityAttributes.ContentState) -> Color {
        state.finished ? .move : state.frozenElapsed != nil ? .carbs : .brand
    }

    static func kilometers(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(2)))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

extension RouteActivityAttributes {
    var art: PixelArt {
        let skin = CompanionSkin(rawValue: companion) ?? .onigiri
        return skin.art(shiny: shiny)
    }
}

/// 小工具裡的像素圖：每種顏色畫成一個形狀（小工具裡用形狀最穩）
struct WidgetSprite: View {
    let art: PixelArt
    var size: CGFloat

    var body: some View {
        // 小工具的 ForEach 識別碼要能編碼，所以用字串
        let colors = Set(art.rows.flatMap { $0 }).filter { PixelArt.color(for: $0) != nil }.map(String.init).sorted()
        ZStack {
            ForEach(colors, id: \.self) { key in
                let character = Character(key)
                PixelLayer(art: art, character: character)
                    .fill(PixelArt.color(for: character) ?? .clear)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PixelLayer: Shape {
    let art: PixelArt
    let character: Character

    func path(in rect: CGRect) -> Path {
        let height = art.rows.count
        let width = art.rows.map(\.count).max() ?? 0
        guard width > 0, height > 0 else { return Path() }
        let cell = min(rect.width / CGFloat(width), rect.height / CGFloat(height))
        let originX = rect.minX + (rect.width - cell * CGFloat(width)) / 2
        let originY = rect.minY + (rect.height - cell * CGFloat(height)) / 2
        var path = Path()
        for (y, row) in art.rows.enumerated() {
            for (x, value) in row.enumerated() where value == character {
                path.addRect(CGRect(x: originX + CGFloat(x) * cell, y: originY + CGFloat(y) * cell,
                                    width: cell + 0.3, height: cell + 0.3))
            }
        }
        return path
    }
}
