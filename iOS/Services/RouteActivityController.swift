import ActivityKit
import Foundation

/// 出發冒險時的鎖定畫面、動態島：開始時建立，走路中每 10 秒更新距離，結束時顯示成果
@MainActor
enum RouteActivityController {
    private static var activity: Activity<RouteActivityAttributes>?
    private static var lastUpdate = Date.distantPast

    static func start(kind: RouteKind, startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            #if DEBUG
            try? "disabled".write(to: FileManager.default.temporaryDirectory.appending(path: "activity-error.txt"), atomically: true, encoding: .utf8)
            #endif
            return
        }
        // 上次沒關掉的（例如 App 被系統關掉）先收掉
        for old in Activity<RouteActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        let skin = CompanionSkin.active ?? .onigiri
        let shiny = UserDefaults.standard.bool(forKey: SettingKey.companionShiny) && SpiritCollection.isShinyUnlocked(skin)
        let attributes = RouteActivityAttributes(kind: kind.rawValue, title: kind.title, companion: skin.rawValue, shiny: shiny)
        let state = RouteActivityAttributes.ContentState(distance: 0, timerStart: startDate, frozenElapsed: nil,
                                                         pace: RouteStore.pace(seconds: 0, meters: 0))
        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            print("無法顯示在鎖定畫面：\(error)")
            #if DEBUG
            try? "\(error)".write(to: FileManager.default.temporaryDirectory.appending(path: "activity-error.txt"), atomically: true, encoding: .utf8)
            #endif
        }
        lastUpdate = .now
    }

    /// 走路中：距離變了才需要更新（計時器由系統自己跳），最多 10 秒一次；暫停、繼續時馬上更新
    static func update(distance: Double, elapsed: TimeInterval, paused: Bool, force: Bool = false) {
        guard let activity, force || Date.now.timeIntervalSince(lastUpdate) >= 10 else { return }
        lastUpdate = .now
        let state = RouteActivityAttributes.ContentState(
            distance: distance, timerStart: Date.now.addingTimeInterval(-elapsed),
            frozenElapsed: paused ? elapsed : nil, pace: RouteStore.pace(seconds: elapsed, meters: distance))
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    /// 存檔完成：成果在鎖定畫面留 15 分鐘
    static func finish(distance: Double, elapsed: TimeInterval) {
        guard let activity else { return }
        let state = RouteActivityAttributes.ContentState(
            distance: distance, timerStart: Date.now.addingTimeInterval(-elapsed), frozenElapsed: elapsed,
            pace: RouteStore.pace(seconds: elapsed, meters: distance), finished: true)
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(15 * 60))) }
        self.activity = nil
    }

    /// 放棄：馬上收掉
    static func cancel() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
