import Foundation
import UserNotifications

/// 聰明提醒：
/// - 三餐提醒：這一餐已經記錄（或標記沒吃）就不會再響
/// - 喝水提醒：剛喝過水會跳過下一次，今天達標後就停止
/// - 晚上回顧：提醒睡前確認一下今天的紀錄
/// - 通知上可直接按「喝了 250 ml」「拍照記錄」「30 分鐘後再提醒」；
///   手機上鎖時通知會轉到 Apple Watch，在手錶上按一樣有效
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    enum Category {
        static let water = "WATER"
        static let meal = "MEAL"
        static let review = "REVIEW"
    }

    enum Action {
        static let water250 = "WATER_250"
        static let water500 = "WATER_500"
        static let snooze = "SNOOZE"
        static let camera = "CAMERA"
        static let skipMeal = "SKIP_MEAL"
    }

    /// 由排程管理的通知前綴；「稍後提醒」用 snooze- 開頭，不會被重新排程清掉
    private let managedPrefixes = ["meal-", "water-", "review-", "comeback-"]
    private let center = UNUserNotificationCenter.current()
    private var refreshTask: Task<Void, Never>?

    func setup() {
        center.delegate = self
        let water250 = UNNotificationAction(identifier: Action.water250, title: "喝了 250 ml", options: [])
        let water500 = UNNotificationAction(identifier: Action.water500, title: "喝了 500 ml", options: [])
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "30 分鐘後再提醒", options: [])
        let camera = UNNotificationAction(identifier: Action.camera, title: "拍照記錄", options: [.foreground])
        let skip = UNNotificationAction(identifier: Action.skipMeal, title: "這餐沒吃", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.water, actions: [water250, water500, snooze],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.meal, actions: [camera, snooze, skip],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.review, actions: [],
                                   intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await MainActor.run { self.scheduleRefresh() } }
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 資料或設定變動後重新排程；短時間內多次呼叫只會執行最後一次
    @MainActor
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self.rescheduleAll()
        }
    }

    // MARK: - 排程

    @MainActor
    private func rescheduleAll() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        let oldIDs = pending.map(\.identifier).filter { id in managedPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)

        let status = LogService.shared.todayStatus()
        let now = Date.now
        var requests: [UNNotificationRequest] = []

        // iOS 最多保留 64 個待送通知，所以只排未來 4 天，App 每次開啟都會重新排
        for offset in 0..<4 {
            let day = now.startOfDay.adding(days: offset)
            let isToday = offset == 0

            if AppSettings.mealReminders {
                for meal in [MealType.breakfast, .lunch, .dinner] {
                    let fire = Date.at(minutes: AppSettings.mealTime(meal), on: day)
                    guard fire > now else { continue }
                    if isToday && status.handledMeals.contains(meal) { continue }
                    requests.append(mealRequest(meal, at: fire))
                }
            }

            if AppSettings.waterReminders {
                let interval = max(30, AppSettings.waterInterval)
                var minute = AppSettings.wakeTime + interval
                while minute <= AppSettings.sleepTime - 30 {
                    let fire = Date.at(minutes: minute, on: day)
                    minute += interval
                    guard fire > now else { continue }
                    if isToday {
                        if status.water >= status.waterGoal { break }
                        // 剛喝過水就跳過這一次
                        if let last = status.lastWater, fire.timeIntervalSince(last) < Double(interval * 60) * 0.75 {
                            continue
                        }
                    }
                    requests.append(waterRequest(at: fire, status: isToday ? status : nil))
                }
            }

            if AppSettings.eveningReview {
                let fire = Date.at(minutes: AppSettings.eveningTime, on: day)
                if fire > now {
                    requests.append(reviewRequest(at: fire, status: isToday ? status : nil))
                }
            }
        }

        for request in requests.prefix(60) {
            try? await center.add(request)
        }

        // 好幾天沒打開 App 時的溫柔提醒
        let comebackDate = Date.at(minutes: 12 * 60 + 15, on: now.startOfDay.adding(days: 4))
        try? await center.add(request(
            id: "comeback-\(comebackDate.dayKey)",
            title: "好幾天沒看到你的紀錄了 👋",
            body: "沒關係，從今天的下一餐重新開始就好。",
            category: Category.review, at: comebackDate
        ))
    }

    private func mealRequest(_ meal: MealType, at date: Date) -> UNNotificationRequest {
        let emoji = ["breakfast": "🍳", "lunch": "🍱", "dinner": "🍲"][meal.rawValue] ?? "🍽️"
        return request(
            id: "meal-\(date.dayKey)-\(meal.rawValue)",
            title: "\(meal.title)時間到了 \(emoji)",
            body: "吃之前拍張照，AI 幫你算熱量，不用事後回想。",
            category: Category.meal, at: date, userInfo: ["meal": meal.rawValue]
        )
    }

    private func waterRequest(at date: Date, status: TodayStatus?) -> UNNotificationRequest {
        let body: String
        if let status {
            body = "今天喝了 \(status.water.rounded0) / \(status.waterGoal.rounded0) ml，起來喝杯水吧。"
        } else {
            body = "起來喝杯水，順便伸展一下。"
        }
        return request(id: "water-\(date.dayKey)-\(date.minutesSinceMidnight)",
                       title: "喝水時間 💧", body: body, category: Category.water, at: date)
    }

    private func reviewRequest(at date: Date, status: TodayStatus?) -> UNNotificationRequest {
        var body = "營火升起來了，來收今天的元氣幣，順便設定明天的小目標。"
        if let status {
            let missing = [MealType.breakfast, .lunch, .dinner].filter { !status.handledMeals.contains($0) }
            if !missing.isEmpty {
                body = "還沒記錄：\(missing.map(\.title).joined(separator: "、"))。現在補上還記得！"
            } else if status.water < status.waterGoal {
                body = "三餐都記錄了 👍 今天還差 \((status.waterGoal - status.water).rounded0) ml 的水。"
            } else {
                body = "今天三餐和喝水都完成了，太棒了！🎉"
            }
        }
        return request(id: "review-\(date.dayKey)", title: "營火時間 🔥",
                       body: body, category: Category.review, at: date)
    }

    private func request(id: String, title: String, body: String, category: String,
                         at date: Date, userInfo: [String: String] = [:]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = category
        content.userInfo = userInfo
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func scheduleSnooze(title: String, body: String, category: String, meal: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = category
        if let meal { content.userInfo = ["meal": meal] }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        center.add(UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// App 開著的時候也顯示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 使用者按了通知或通知上的按鈕（包含在 Apple Watch 上按的）
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let title = content.title
        let body = content.body
        let mealRaw = content.userInfo["meal"] as? String
        let meal = mealRaw.flatMap(MealType.init(rawValue:))

        Task { @MainActor in
            switch action {
            case Action.water250:
                LogService.shared.logWater(250, source: .notification)
            case Action.water500:
                LogService.shared.logWater(500, source: .notification)
            case Action.snooze:
                self.scheduleSnooze(title: title, body: body, category: category, meal: mealRaw)
            case Action.skipMeal:
                if let meal { LogService.shared.skipMeal(meal) }
            case Action.camera:
                AppRouter.shared.openAddFood(meal: meal, start: .camera)
            case UNNotificationDefaultActionIdentifier:
                if category == Category.meal {
                    AppRouter.shared.openAddFood(meal: meal)
                } else if category == Category.review {
                    // 睡前提醒：直接打開營火
                    AppRouter.shared.selectedTab = .today
                    AdventureStore.shared.showCampfire = true
                } else {
                    AppRouter.shared.selectedTab = .today
                }
            default:
                break
            }
            completionHandler()
        }
    }
}
