import SwiftUI

// MARK: - 記錄中（跟「體能訓練」一樣：中間看數據，往右滑是控制）

struct WorkoutSessionView: View {
    @ObservedObject private var workout = WorkoutManager.shared
    @State private var page = 1

    init() {
        #if DEBUG
        // 開發用：-workoutControls 直接顯示控制頁
        if ProcessInfo.processInfo.arguments.contains("-workoutControls") { _page = State(initialValue: 0) }
        #endif
    }

    var body: some View {
        if workout.phase == .finished || workout.phase == .saving {
            WorkoutSummaryView()
        } else {
            TabView(selection: $page) {
                WorkoutControlsView { page = 1 }
                    .containerBackground(Color.paper, for: .tabView)
                    .tag(0)
                WorkoutMetricsView()
                    .containerBackground(Color.paper, for: .tabView)
                    .tag(1)
            }
            .tabViewStyle(.page)
        }
    }
}

/// 時間、動態熱量、心率、距離、平均配速
struct WorkoutMetricsView: View {
    @ObservedObject private var workout = WorkoutManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate)
            let paused = workout.phase == .paused
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    PixelSprite(art: workout.kind.art, size: 12)
                    Text(paused ? "\(workout.kind.title)・暫停" : "\(workout.kind.title)中")
                        .font(.px(12))
                        .foregroundStyle(paused ? Color.carbs : Color.move)
                }
                Text(WorkoutClock.text(workout.elapsed(at: timeline.date)))
                    .font(.px(30))
                    .foregroundStyle(paused ? Color.carbs : Color.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                metric("\(Int(workout.energy))", unit: "動態大卡", color: .calorie)
                metric(workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "--", unit: "下／分", color: .protein) {
                    // 心跳：每秒縮放一次
                    PixelSprite(art: .heart, size: 12)
                        .scaleEffect(!paused && workout.heartRate > 0 && tick % 2 == 0 ? 1 : 0.75)
                }
                metric((workout.distance / 1000).formatted(.number.precision(.fractionLength(2))), unit: "公里", color: .move)
                metric(workout.pace(at: timeline.date), unit: "平均配速", color: .water)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ value: String, unit: String, color: Color,
                        @ViewBuilder icon: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            icon()
            Text(value)
                .font(.px(22))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(unit).font(.px(12)).foregroundStyle(Color.soft)
        }
    }
}

/// 暫停／繼續、結束
struct WorkoutControlsView: View {
    @ObservedObject private var workout = WorkoutManager.shared
    /// 按完回到數據頁
    var onAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if workout.phase == .paused {
                    control("繼續", art: Self.play, tint: .move) { workout.resume() }
                } else {
                    control("暫停", art: Self.pause, tint: .carbs) { workout.pause() }
                }
                control("結束", art: Self.stop, tint: .danger) { Task { await workout.end() } }
            }
            Text("結束後會存到「健康」，iPhone 的足跡會自動出現。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func control(_ title: String, art: PixelArt, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onAction()
        } label: {
            VStack(spacing: 6) {
                PixelSprite(art: art, size: 24, tint: tint)
                Text(title).font(.px(12)).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background { PixelPanel(fill: .window, border: tint, shadow: nil, lineWidth: 3) }
        }
        .buttonStyle(.plain)
    }

    // 暫停、繼續、結束的像素圖示（畫的時候整張換成按鈕的顏色）
    private static let pause = PixelArt([
        "........",
        ".kk..kk.",
        ".kk..kk.",
        ".kk..kk.",
        ".kk..kk.",
        ".kk..kk.",
        ".kk..kk.",
        "........",
    ])
    private static let play = PixelArt([
        "........",
        ".kk.....",
        ".kkkk...",
        ".kkkkkk.",
        ".kkkkkk.",
        ".kkkk...",
        ".kk.....",
        "........",
    ])
    private static let stop = PixelArt([
        "........",
        ".kkkkkk.",
        ".kkkkkk.",
        ".kkkkkk.",
        ".kkkkkk.",
        ".kkkkkk.",
        ".kkkkkk.",
        "........",
    ])
}

/// 結束後的總結
struct WorkoutSummaryView: View {
    @ObservedObject private var workout = WorkoutManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.phase == .saving ? "儲存中…" : "\(workout.kind.title)完成！")
                    .font(.px(16))
                    .foregroundStyle(Color.move)
                row("時間", WorkoutClock.text(workout.elapsed(at: .now)), color: .ink)
                row("距離", "\((workout.distance / 1000).formatted(.number.precision(.fractionLength(2)))) 公里", color: .move)
                row("動態熱量", "\(Int(workout.energy)) 大卡", color: .calorie)
                row("平均心率", workout.averageHeartRate > 0 ? "\(Int(workout.averageHeartRate)) 下／分" : "--", color: .protein)
                row("平均配速", workout.pace(at: .now), color: .water)
                if workout.phase == .finished {
                    Text("已存到「健康」，iPhone 的足跡會自動出現。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("完成") { workout.close() }
                        .font(.px(12))
                        .tint(Color.brand)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
            Spacer(minLength: 4)
            Text(value).font(.px(16)).foregroundStyle(color).monospacedDigit()
        }
    }
}

enum WorkoutClock {
    /// 1 小時內 12:34，超過 1:02:03
    static func text(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
