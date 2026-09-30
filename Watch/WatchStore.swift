import Foundation
import WatchConnectivity
import WatchKit

/// 手錶端：顯示 iPhone 送來的今日摘要，把記錄送回 iPhone 儲存
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var summary: DailySummary
    @Published private(set) var lastSync: Date?

    private let cacheKey = "cachedSummary"
    private var pending: [[String: Any]] = []

    override init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(DailySummary.self, from: data) {
            summary = cached.normalizedForToday()
        } else {
            summary = DailySummary.empty.normalizedForToday()
        }
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// 過了午夜會自動歸零
    var today: DailySummary { summary.normalizedForToday() }

    // MARK: - 記錄

    func logWater(_ ml: Double) {
        var updated = today
        updated.waterML += ml
        summary = updated
        send([WatchMessage.action: WatchMessage.Action.logWater, WatchMessage.amount: ml])
        WKInterfaceDevice.current().play(.success)
    }

    func logFood(_ food: QuickFood) {
        guard let data = try? JSONEncoder().encode(food) else { return }
        var updated = today
        updated.calories += food.calories
        updated.protein += food.protein
        summary = updated
        send([WatchMessage.action: WatchMessage.Action.logFood, WatchMessage.food: data])
        WKInterfaceDevice.current().play(.success)
    }

    func requestRefresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchMessage.action: WatchMessage.Action.requestSummary],
                            replyHandler: { [weak self] reply in self?.apply(reply) },
                            errorHandler: nil)
    }

    /// iPhone 在旁邊就即時送出；不在旁邊就排隊，連上後自動補送
    private func send(_ payload: [String: Any]) {
        var message = payload
        message[WatchMessage.id] = UUID().uuidString
        message[WatchMessage.date] = Date()

        let session = WCSession.default
        guard session.activationState == .activated else {
            pending.append(message)
            return
        }
        if session.isReachable {
            session.sendMessage(message,
                                replyHandler: { [weak self] reply in self?.apply(reply) },
                                errorHandler: { _ in session.transferUserInfo(message) })
        } else {
            session.transferUserInfo(message)
        }
    }

    private func apply(_ dictionary: [String: Any]) {
        guard let data = dictionary[WatchMessage.summary] as? Data,
              let incoming = try? JSONDecoder().decode(DailySummary.self, from: data) else { return }
        DispatchQueue.main.async {
            self.summary = incoming.normalizedForToday()
            self.lastSync = .now
            UserDefaults.standard.set(data, forKey: self.cacheKey)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
        DispatchQueue.main.async {
            let queued = self.pending
            self.pending.removeAll()
            for message in queued { session.transferUserInfo(message) }
            self.requestRefresh()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
