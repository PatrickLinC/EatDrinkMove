import Foundation
import WatchConnectivity

/// iPhone 端的 Apple Watch 連線：
/// - 接收手錶上記錄的喝水、常吃食物
/// - 把今日摘要推送到手錶顯示
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    @MainActor
    func pushSummary() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = try? JSONEncoder().encode(LogService.shared.todaySummary()) else { return }
        try? session.updateApplicationContext([WatchMessage.summary: data])
    }

    @MainActor
    private func summaryReply() -> [String: Any] {
        let data = (try? JSONEncoder().encode(LogService.shared.todaySummary())) ?? Data()
        return [WatchMessage.summary: data]
    }

    // MARK: - 處理手錶送來的指令

    private struct Command {
        enum Kind {
            case water(Double)
            case food(QuickFood)
            case requestSummary
            case unknown
        }
        let id: String?
        let date: Date
        let kind: Kind

        init(_ message: [String: Any]) {
            id = message[WatchMessage.id] as? String
            date = message[WatchMessage.date] as? Date ?? .now
            switch message[WatchMessage.action] as? String {
            case WatchMessage.Action.logWater:
                kind = .water(message[WatchMessage.amount] as? Double ?? 250)
            case WatchMessage.Action.logFood:
                if let data = message[WatchMessage.food] as? Data,
                   let food = try? JSONDecoder().decode(QuickFood.self, from: data) {
                    kind = .food(food)
                } else {
                    kind = .unknown
                }
            case WatchMessage.Action.requestSummary:
                kind = .requestSummary
            default:
                kind = .unknown
            }
        }
    }

    @MainActor
    private func handle(_ command: Command) {
        // 手錶在連線不穩時可能重送，用 id 避免重複記錄
        if let id = command.id {
            var processed = UserDefaults.standard.stringArray(forKey: SettingKey.processedWatchIDs) ?? []
            guard !processed.contains(id) else { return }
            processed.append(id)
            UserDefaults.standard.set(Array(processed.suffix(200)), forKey: SettingKey.processedWatchIDs)
        }
        switch command.kind {
        case .water(let ml):
            LogService.shared.logWater(ml, date: command.date, source: .watch)
        case .food(let food):
            LogService.shared.logQuickFood(food, date: command.date, source: .watch)
        case .requestSummary, .unknown:
            break
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushSummary() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // 使用者換了一支手錶時需要重新啟用
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushSummary() }
    }

    /// 手錶在旁邊時用這個即時送達，並回傳最新摘要
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let command = Command(message)
        Task { @MainActor in
            self.handle(command)
            replyHandler(self.summaryReply())
        }
    }

    /// 手錶不在旁邊時，資料會排隊等連上後送達
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let command = Command(userInfo)
        Task { @MainActor in self.handle(command) }
    }
}
