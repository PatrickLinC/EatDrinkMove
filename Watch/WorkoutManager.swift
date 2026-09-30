import CoreLocation
import Foundation
import HealthKit
import WatchKit

/// 手錶上的冒險種類（跟 iPhone 的散步、快走、跑步一樣）
enum WatchRouteKind: String, CaseIterable, Identifiable {
    case walk, brisk, run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: "散步"
        case .brisk: "快走"
        case .run: "跑步"
        }
    }

    var activity: HKWorkoutActivityType { self == .run ? .running : self == .brisk ? .hiking : .walking }

    var art: PixelArt { self == .run ? .dumbbell : .footprint }
}

/// 在手錶上直接記錄散步、跑步：體能訓練＋GPS 路線，結束後存進「健康」，iPhone 會自動讀進足跡
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    enum Phase { case idle, running, paused, saving, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var kind: WatchRouteKind = .walk
    @Published private(set) var distance: Double = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var averageHeartRate: Double = 0
    /// 動態熱量（大卡）
    @Published private(set) var energy: Double = 0
    @Published private(set) var startDate: Date?
    @Published var errorMessage: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let location = CLLocationManager()
    /// 結束時的總時間（結束後 builder 就沒了，總結畫面用這個）
    private var finalElapsed: TimeInterval?

    /// 已經走了多久（不含暫停）
    func elapsed(at date: Date) -> TimeInterval {
        if let builder { return builder.elapsedTime(at: date) }
        if let finalElapsed { return finalElapsed }
        return startDate.map { date.timeIntervalSince($0) } ?? 0
    }

    /// 平均配速（每公里幾分幾秒）
    func pace(at date: Date) -> String {
        guard distance > 50 else { return "--'--\"" }
        let perKm = elapsed(at: date) / (distance / 1000)
        return String(format: "%d'%02d\"", Int(perKm) / 60, Int(perKm) % 60)
    }

    func start(_ kind: WatchRouteKind) async {
        guard phase == .idle || phase == .finished else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(),
                                         HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.distanceWalkingRunning)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            errorMessage = "沒有「健康」的權限"
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = kind.activity
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            self.kind = kind
            distance = 0
            heartRate = 0
            averageHeartRate = 0
            energy = 0
            finalElapsed = nil
            let now = Date.now
            startDate = now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            location.delegate = self
            location.desiredAccuracy = kCLLocationAccuracyBest
            location.activityType = .fitness
            location.requestWhenInUseAuthorization()
            location.startUpdatingLocation()
            phase = .running
            WKInterfaceDevice.current().play(.start)
        } catch {
            errorMessage = "開始失敗：\(error.localizedDescription)"
        }
    }

    func pause() {
        session?.pause()
        phase = .paused
    }

    func resume() {
        session?.resume()
        phase = .running
    }

    func end() async {
        guard let session, let builder else { return }
        phase = .saving
        finalElapsed = builder.elapsedTime(at: .now)
        location.stopUpdatingLocation()
        session.end()
        do {
            try await builder.endCollection(at: .now)
            if let workout = try await builder.finishWorkout() {
                _ = try? await routeBuilder?.finishRoute(with: workout, metadata: nil)
            }
            WKInterfaceDevice.current().play(.success)
        } catch {
            errorMessage = "儲存失敗：\(error.localizedDescription)"
        }
        self.session = nil
        self.builder = nil
        routeBuilder = nil
        phase = .finished
    }

    func close() { phase = .idle }

    #if DEBUG
    /// 開發用：-seedWorkout 顯示記錄中的畫面、-seedWorkoutDone 顯示總結（模擬器截圖檢查）
    func seedForScreenshots() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedWorkout") || arguments.contains("-seedWorkoutDone") else { return }
        kind = .walk
        distance = 1834
        heartRate = 112
        averageHeartRate = 106
        energy = 96
        startDate = .now.addingTimeInterval(-1254)
        phase = .running
        if arguments.contains("-seedWorkoutDone") {
            finalElapsed = 1254
            phase = .finished
        }
    }
    #endif

    fileprivate func update(from statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? heartRate
            averageHeartRate = statistics.averageQuantity()?.doubleValue(for: unit) ?? averageHeartRate
        case HKQuantityType(.distanceWalkingRunning):
            distance = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? distance
        case HKQuantityType(.activeEnergyBurned):
            energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? energy
        default:
            break
        }
    }

    fileprivate func add(_ locations: [CLLocation]) {
        guard phase == .running else { return }
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 30 }
        guard !good.isEmpty else { return }
        routeBuilder?.insertRouteData(good) { _, _ in }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, CLLocationManagerDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.errorMessage = error.localizedDescription }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let statistics = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in statistics.forEach(self.update(from:)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.add(locations) }
    }
}
