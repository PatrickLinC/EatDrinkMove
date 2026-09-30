import Foundation
import HealthKit

/// 久坐提醒：上班時間每個整點提醒起來動一動；最近一小時已經走了 250 步以上，下一次提醒就跳過。
/// 「健康」有新步數時（App 在背景也會被叫醒，大約一小時一次）重新排一次提醒。
@MainActor
enum SedentaryMonitor {
    static let stepsThreshold = 250.0
    private static var observing = false

    /// 最近一小時有沒有起來走動
    static func movedRecently() async -> Bool {
        let steps = await HealthKitManager.shared.sum(.stepCount, unit: .count(), from: .now.addingTimeInterval(-3600), to: .now)
        return steps >= stepsThreshold
    }

    /// 只有平日提醒時，週末不排
    static func isWorkday(_ day: Date) -> Bool {
        guard AppSettings.sedentaryWeekdaysOnly else { return true }
        return !Calendar.current.isDateInWeekend(day)
    }

    /// App 啟動、打開久坐提醒時呼叫
    static func startObservingIfNeeded() {
        guard AppSettings.sedentaryReminders, !observing, HKHealthStore.isHealthDataAvailable() else { return }
        observing = true
        let store = HealthKitManager.shared.store
        let type = HKQuantityType(.stepCount)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
            Task { @MainActor in
                await NotificationManager.shared.refreshNow()
                completion()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }
}
