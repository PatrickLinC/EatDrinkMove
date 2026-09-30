import Foundation
import HealthKit

/// 串接 Apple「健康」：
/// - 讀取 Apple Watch 記錄的步數、活動熱量、運動分鐘、體能訓練、體重、睡眠、心率變異度
/// - 把 App 記錄的飲食、喝水、體重寫回「健康」，其他 App 也能使用
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    /// 寫入「健康」的每筆資料都帶這個 metadata，刪除或修改時才找得到
    static let entryIDKey = "EatDrinkMoveEntryID"

    static let foodTypes: [HKQuantityTypeIdentifier] = [
        .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
        .dietaryFatTotal, .dietarySodium, .dietarySugar,
    ]

    let store = HKHealthStore()

    @Published private(set) var steps: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var exerciseMinutes: Double = 0
    @Published private(set) var latestWeight: Double?
    @Published private(set) var recentWorkouts: [HKWorkout] = []
    @Published private(set) var needsAuthorization = true
    /// 上次從「健康」同步的時間
    @Published private(set) var lastSync: Date?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 要求的權限有變動時加一，App 開啟時會自動再問一次（新增項目時 iOS 會把 App 當成還沒授權，連步數都讀不到）
    static let authorizationVersion = 2
    private static let authorizationVersionKey = "healthAuthorizationVersion"

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKQuantityType(.dietaryWater), HKQuantityType(.bodyMass),
            // 之後的路跑紀錄、呼吸練習會寫回「健康」
            HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKCategoryType(.mindfulSession),
        ]
        for id in Self.foodTypes { types.insert(HKQuantityType(id)) }
        return types
    }

    /// 路線圖用得到的都一次問完，避免之後每加一個功能就要再授權一次
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.appleStandHour),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
        ]
        for type in shareTypes { types.insert(type) }
        return types
    }

    // MARK: - 授權

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            UserDefaults.standard.set(Self.authorizationVersion, forKey: Self.authorizationVersionKey)
        } catch {
            print("HealthKit 授權失敗：\(error.localizedDescription)")
        }
        await updateAuthorizationState()
        await refreshToday()
        await LogService.shared.syncPendingToHealth()
    }

    /// App 更新後新增了要讀的項目：之前授權過的人自動再問一次（只問新增的項目）
    func requestNewPermissionsIfNeeded() async {
        guard isAvailable,
              UserDefaults.standard.bool(forKey: SettingKey.hasOnboarded),
              UserDefaults.standard.integer(forKey: Self.authorizationVersionKey) < Self.authorizationVersion else { return }
        await updateAuthorizationState()
        if needsAuthorization {
            await requestAuthorization()
        } else {
            UserDefaults.standard.set(Self.authorizationVersion, forKey: Self.authorizationVersionKey)
        }
    }

    /// 「健康」基於隱私不會告訴 App 使用者拒絕了哪些項目，只能知道是否已經問過
    func updateAuthorizationState() async {
        guard isAvailable else {
            needsAuthorization = false
            return
        }
        let share = shareTypes
        let read = readTypes
        let status: HKAuthorizationRequestStatus = await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: share, read: read) { status, _ in
                continuation.resume(returning: status)
            }
        }
        needsAuthorization = (status == .shouldRequest)
    }

    // MARK: - 讀取

    func refreshToday() async {
        guard isAvailable else { return }
        if needsAuthorization { await updateAuthorizationState() }
        guard !needsAuthorization else { return }

        let start = Date.now.startOfDay
        steps = await sum(.stepCount, unit: .count(), from: start, to: .now)
        activeCalories = await sum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: .now)
        exerciseMinutes = await sum(.appleExerciseTime, unit: .minute(), from: start, to: .now)
        latestWeight = await fetchLatestWeight()
        recentWorkouts = await fetchWorkouts(days: 7)
        lastSync = .now
        PhoneConnectivity.shared.pushSummary()
    }

    func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        do {
            let statistics = try await descriptor.result(for: store)
            return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch {
            return 0 // 沒有資料時 HealthKit 會丟錯誤，當作 0
        }
    }

    /// 最近幾天每天的加總，key 為當天 00:00
    func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [Date: Double] {
        await dailySums(id, unit: unit, from: Date.now.startOfDay.adding(days: -(days - 1)), to: .now)
    }

    /// 某段期間每天的加總（戰績圖表用），key 為當天 00:00
    func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> [Date: Double] {
        guard isAvailable, !needsAuthorization, start < end else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        var result: [Date: Double] = [:]
        do {
            let collection = try await descriptor.result(for: store)
            for statistics in collection.statistics() {
                result[statistics.startDate.startOfDay] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
            }
        } catch {
            print("讀取每日資料失敗：\(error.localizedDescription)")
        }
        return result
    }

    func dailySteps(from start: Date, to end: Date) async -> [Date: Double] {
        await dailySums(.stepCount, unit: .count(), from: start, to: end)
    }

    func dailyActiveCalories(from start: Date, to end: Date) async -> [Date: Double] {
        await dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
    }

    private func fetchLatestWeight() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: nil)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try? await descriptor.result(for: store)
        return samples?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    private func fetchWorkouts(days: Int) async -> [HKWorkout] {
        let start = Date.now.startOfDay.adding(days: -days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 50
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    // MARK: - 寫入

    func saveWater(ml: Double, date: Date, entryID: UUID) async -> Bool {
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
            start: date, end: date,
            metadata: [Self.entryIDKey: entryID.uuidString]
        )
        return await save([sample])
    }

    func saveFood(name: String, calories: Double, protein: Double, carbs: Double, fat: Double,
                  sodium: Double, sugar: Double, date: Date, entryID: UUID) async -> Bool {
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name, Self.entryIDKey: entryID.uuidString]
        var samples: [HKQuantitySample] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) {
            guard value > 0, value.isFinite else { return }
            samples.append(HKQuantitySample(
                type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date, end: date, metadata: metadata
            ))
        }
        add(.dietaryEnergyConsumed, .kilocalorie(), calories)
        add(.dietaryProtein, .gram(), protein)
        add(.dietaryCarbohydrates, .gram(), carbs)
        add(.dietaryFatTotal, .gram(), fat)
        add(.dietarySodium, .gramUnit(with: .milli), sodium)
        add(.dietarySugar, .gram(), sugar)
        guard !samples.isEmpty else { return true }
        return await save(samples)
    }

    func saveWeight(kg: Double, date: Date, entryID: UUID) async -> Bool {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date, end: date,
            metadata: [Self.entryIDKey: entryID.uuidString]
        )
        return await save([sample])
    }

    /// 刪除這筆紀錄先前寫進「健康」的資料
    func deleteSamples(entryID: UUID, types: [HKQuantityTypeIdentifier]) async {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.entryIDKey,
                                                    allowedValues: [entryID.uuidString])
        for id in types {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.deleteObjects(of: HKQuantityType(id), predicate: predicate) { _, _, _ in
                    continuation.resume()
                }
            }
        }
    }

    private func save(_ objects: [HKObject]) async -> Bool {
        guard isAvailable else { return false }
        return await withCheckedContinuation { continuation in
            store.save(objects) { success, error in
                if let error {
                    // 手機上鎖時「健康」資料受保護，會寫入失敗；App 下次開啟時會重試
                    print("HealthKit 寫入失敗：\(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - 顯示用

extension HKWorkout {
    var activeKcal: Double {
        statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: "跑步"
        case .walking: "步行"
        case .cycling: "騎自行車"
        case .swimming: "游泳"
        case .hiking: "健行"
        case .yoga: "瑜珈"
        case .pilates: "皮拉提斯"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "肌力訓練"
        case .highIntensityIntervalTraining: "高強度間歇訓練"
        case .coreTraining: "核心訓練"
        case .elliptical: "滑步機"
        case .rowing: "划船"
        case .stairClimbing, .stairs: "爬樓梯"
        case .cardioDance, .socialDance: "舞蹈"
        case .mixedCardio: "混合有氧"
        case .badminton: "羽球"
        case .basketball: "籃球"
        case .tennis: "網球"
        case .tableTennis: "桌球"
        case .jumpRope: "跳繩"
        default: "體能訓練"
        }
    }

    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .hiking: "figure.hiking"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "dumbbell.fill"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .coreTraining: "figure.core.training"
        case .elliptical: "figure.elliptical"
        case .rowing: "figure.rower"
        case .stairClimbing, .stairs: "figure.stairs"
        case .cardioDance, .socialDance: "figure.dance"
        case .badminton: "figure.badminton"
        case .basketball: "figure.basketball"
        case .tennis: "figure.tennis"
        case .tableTennis: "figure.table.tennis"
        case .jumpRope: "figure.jumprope"
        default: "figure.mixed.cardio"
        }
    }
}
