import CoreLocation
import Foundation
import HealthKit
import SwiftUI

// MARK: - 路線

enum RouteKind: String, Codable, CaseIterable, Identifiable {
    case walk, brisk, run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: "散步"
        case .brisk: "快走"
        case .run: "跑步"
        }
    }

    var art: PixelArt {
        switch self {
        case .walk: .footprint
        case .brisk: .footprint
        case .run: .dumbbell
        }
    }

    var activity: HKWorkoutActivityType { self == .run ? .running : .walking }

    init(activity: HKWorkoutActivityType) {
        self = activity == .running ? .run : activity == .hiking ? .brisk : .walk
    }
}

/// 一條記錄好的路線（App 自己記的，或從「健康」讀進來的手錶體能訓練）
struct SavedRoute: Codable, Identifiable {
    enum Source: String, Codable { case app, health }

    var id: UUID
    var kind: RouteKind
    var start: Date
    var end: Date
    /// 公尺
    var distance: Double
    /// 經緯度（每幾公尺存一點）
    var points: [[Double]]
    var source: Source
    /// 累計爬升（公尺）；舊資料沒有
    var climb: Double? = nil
    /// 移動時間（不含暫停、停下來的時間）；舊資料沒有
    var moving: TimeInterval? = nil

    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// 顯示用的時間：有移動時間就用移動時間
    var activeTime: TimeInterval { moving ?? duration }
    var coordinates: [CLLocationCoordinate2D] { points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }

    /// 每公里幾分幾秒
    var pace: String { RouteStore.pace(seconds: activeTime, meters: distance) }
}

// MARK: - 開拓地圖的格子

/// 地圖切成約 170 公尺的方格
enum ExploreCell {
    static let latStep = 0.0015
    static let lonStep = 0.00165

    static func id(_ coordinate: CLLocationCoordinate2D) -> Int64 {
        let lat = Int64((coordinate.latitude / latStep).rounded(.down))
        let lon = Int64((coordinate.longitude / lonStep).rounded(.down))
        return (lat << 32) | (lon & 0xFFFF_FFFF)
    }

    /// 格子的四個角（畫圖用）
    static func corners(_ id: Int64) -> [CLLocationCoordinate2D] {
        let lat = Double(id >> 32) * latStep
        let lon = Double(Int32(truncatingIfNeeded: id)) * lonStep
        return [CLLocationCoordinate2D(latitude: lat, longitude: lon),
                CLLocationCoordinate2D(latitude: lat, longitude: lon + lonStep),
                CLLocationCoordinate2D(latitude: lat + latStep, longitude: lon + lonStep),
                CLLocationCoordinate2D(latitude: lat + latStep, longitude: lon)]
    }

    /// 一格大約幾平方公里
    static let area = 0.167 * 0.167

    /// 路線經過的格子（兩點之間每 50 公尺補一點，才不會漏格）
    static func cells(along coordinates: [CLLocationCoordinate2D]) -> Set<Int64> {
        var result = Set<Int64>()
        for (index, point) in coordinates.enumerated() {
            result.insert(id(point))
            guard index > 0 else { continue }
            let previous = coordinates[index - 1]
            let meters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            let steps = Int(meters / 50)
            guard steps > 1, steps < 400 else { continue }
            for step in 1..<steps {
                let t = Double(step) / Double(steps)
                result.insert(id(CLLocationCoordinate2D(latitude: previous.latitude + (point.latitude - previous.latitude) * t,
                                                        longitude: previous.longitude + (point.longitude - previous.longitude) * t)))
            }
        }
        return result
    }
}

// MARK: - 路線與開拓紀錄

@MainActor
final class RouteStore: ObservableObject {
    static let shared = RouteStore()

    /// 開拓新格子的元氣幣：每 10 格 1 枚，一天最多 5 枚
    static let dailyExploreCoinCap = 5

    private struct Saved: Codable {
        var routes: [SavedRoute] = []
        /// 格子 → 第一次走過的時間
        var cells: [Int64: Date] = [:]
        /// 已經讀進來的「健康」體能訓練
        var importedWorkouts: [UUID] = []
        var coinDay = ""
        var coinsToday = 0
        /// 今天還沒換成元氣幣的新格子數
        var pendingCells = 0

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            routes = try container.decodeIfPresent([SavedRoute].self, forKey: .routes) ?? []
            cells = try container.decodeIfPresent([Int64: Date].self, forKey: .cells) ?? [:]
            importedWorkouts = try container.decodeIfPresent([UUID].self, forKey: .importedWorkouts) ?? []
            coinDay = try container.decodeIfPresent(String.self, forKey: .coinDay) ?? ""
            coinsToday = try container.decodeIfPresent(Int.self, forKey: .coinsToday) ?? 0
            pendingCells = try container.decodeIfPresent(Int.self, forKey: .pendingCells) ?? 0
        }
    }

    @Published private var saved: Saved

    private static var fileURL: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "routes.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        } else {
            saved = Saved()
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedRoutes") { seedForScreenshots() }
        #endif
    }

    var routes: [SavedRoute] { saved.routes.sorted { $0.start > $1.start } }
    var cells: [Int64: Date] { saved.cells }
    var cellCount: Int { saved.cells.count }
    var exploredArea: Double { Double(cellCount) * ExploreCell.area }

    func newCells(since date: Date) -> Int { saved.cells.values.filter { $0 >= date }.count }

    func routes(on day: Date) -> [SavedRoute] {
        routes.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    // MARK: 新增

    /// 存一條路線，回傳這次新開拓的格子數與拿到的元氣幣
    @discardableResult
    func add(_ route: SavedRoute) -> (newCells: Int, coins: Int) {
        saved.routes.append(route)
        WorldFogStore.shared.clear(along: route.coordinates, day: route.start)
        let newCells = markCells(route)
        let coins = convertCellsToCoins(newCells)
        save()
        return (newCells, coins)
    }

    private func markCells(_ route: SavedRoute) -> Int {
        var count = 0
        for cell in ExploreCell.cells(along: route.coordinates) where saved.cells[cell] == nil {
            saved.cells[cell] = route.start
            count += 1
        }
        return count
    }

    private func convertCellsToCoins(_ newCells: Int) -> Int {
        let today = Date.now.dayKey
        if saved.coinDay != today {
            saved.coinDay = today
            saved.coinsToday = 0
            saved.pendingCells = 0
        }
        saved.pendingCells += newCells
        let earned = min(saved.pendingCells / 10, Self.dailyExploreCoinCap - saved.coinsToday)
        guard earned > 0 else { return 0 }
        saved.pendingCells -= earned * 10
        saved.coinsToday += earned
        AdventureStore.shared.addBonus(earned, source: .explore)
        return earned
    }

    // MARK: 讀「健康」的手錶路線

    /// 讀「健康」裡所有還沒讀過的散步／跑步／健行路線（包含很久以前的；App 自己存的不重複讀）
    func importFromHealth() async {
        let health = HealthKitManager.shared
        guard health.isAvailable, !health.needsAuthorization else { return }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: .now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await descriptor.result(for: health.store) else { return }
        let appSource = Bundle.main.bundleIdentifier ?? ""
        var added = false
        for workout in workouts where [.walking, .running, .hiking].contains(workout.workoutActivityType)
            && !saved.importedWorkouts.contains(workout.uuid)
            && workout.sourceRevision.source.bundleIdentifier != appSource {
            saved.importedWorkouts.append(workout.uuid)
            let locations = await health.routeLocations(of: workout)
            guard locations.count > 1 else { continue }
            let route = SavedRoute(id: workout.uuid, kind: RouteKind(activity: workout.workoutActivityType),
                                   start: workout.startDate, end: workout.endDate,
                                   distance: Self.length(of: locations), points: Self.thin(locations), source: .health,
                                   climb: Self.climb(of: locations), moving: workout.duration)
            saved.routes.append(route)
            WorldFogStore.shared.clear(along: route.coordinates, day: route.start)
            _ = convertCellsToCoins(markCells(route))
            added = true
        }
        if added || !workouts.isEmpty { save() }
    }

    // MARK: 工具

    nonisolated static func length(of locations: [CLLocation]) -> Double {
        zip(locations, locations.dropFirst()).reduce(0) { $0 + $1.0.distance(from: $1.1) }
    }

    /// 累計爬升：只用高度準確的點，高度變化超過 2 公尺才算（濾掉 GPS 高度的抖動）
    nonisolated static func climb(of locations: [CLLocation]) -> Double? {
        let good = locations.filter { $0.verticalAccuracy >= 0 && $0.verticalAccuracy <= 20 }
        guard var base = good.first?.altitude else { return nil }
        var total = 0.0
        for location in good.dropFirst() {
            let delta = location.altitude - base
            if delta >= 2 {
                total += delta
                base = location.altitude
            } else if delta <= -2 {
                base = location.altitude
            }
        }
        return total
    }

    /// 移動時間：相鄰兩點速度超過每秒 0.5 公尺才算，停下來等紅燈不算
    nonisolated static func movingTime(of locations: [CLLocation]) -> TimeInterval {
        zip(locations, locations.dropFirst()).reduce(0) { total, pair in
            let interval = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard interval > 0, interval < 60 else { return total }
            return pair.1.distance(from: pair.0) / interval > 0.5 ? total + interval : total
        }
    }

    /// 每 5 公尺以上留一點，檔案不會太大
    nonisolated static func thin(_ locations: [CLLocation]) -> [[Double]] {
        var result: [[Double]] = []
        var last: CLLocation?
        for location in locations {
            if let last, location.distance(from: last) < 5 { continue }
            result.append([location.coordinate.latitude, location.coordinate.longitude])
            last = location
        }
        return result
    }

    nonisolated static func pace(seconds: TimeInterval, meters: Double) -> String {
        guard meters > 50 else { return "--'--\"" }
        let perKm = seconds / (meters / 1000)
        return String(format: "%d'%02d\"", Int(perKm) / 60, Int(perKm) % 60)
    }

    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
        objectWillChange.send()
    }

    #if DEBUG
    /// 開發用：-seedRoutes 在台北放兩條路線來檢查畫面
    private func seedForScreenshots() {
        saved = Saved()
        func loop(_ lat: Double, _ lon: Double, _ size: Double, _ count: Int) -> [[Double]] {
            (0...count).map { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                return [lat + sin(angle) * size, lon + cos(angle) * size * 1.3 + sin(angle * 3) * size * 0.2]
            }
        }
        let walk = SavedRoute(id: UUID(), kind: .walk, start: .now.addingTimeInterval(-7200), end: .now.addingTimeInterval(-5400),
                              distance: 3420, points: loop(25.0330, 121.5654, 0.006, 80), source: .app, climb: 12, moving: 1720)
        let run = SavedRoute(id: UUID(), kind: .run, start: .now.adding(days: -2), end: .now.adding(days: -2).addingTimeInterval(1900),
                             distance: 5210, points: loop(25.0405, 121.5600, 0.009, 120), source: .health, climb: 31, moving: 1860)
        // 過去幾週的路線（檢查冒險統計的長條圖、連續週數）
        let older = [(9, 2400.0), (12, 4100), (16, 3000), (20, 6200), (26, 2800), (33, 5100), (40, 3600), (47, 7300)].map { day, meters in
            SavedRoute(id: UUID(), kind: meters > 5000 ? .run : .walk, start: .now.adding(days: -day), end: .now.adding(days: -day).addingTimeInterval(meters * 0.55),
                       distance: meters, points: loop(25.035 + Double(day) * 0.0004, 121.56, 0.004, 40), source: .health,
                       climb: meters / 150, moving: meters * 0.5)
        }
        // 同一條散步路線再走兩次（檢查常走路線的比較）
        let repeats = [(7, 1810.0), (14, 1905.0)].map { day, moving in
            SavedRoute(id: UUID(), kind: .walk, start: walk.start.adding(days: -day), end: walk.start.adding(days: -day).addingTimeInterval(moving + 60),
                       distance: 3380, points: walk.points, source: .app, climb: 11, moving: moving)
        }
        saved.routes = [walk, run] + older + repeats
        _ = markCells(walk)
        _ = markCells(run)
    }
    #endif
}

extension HealthKitManager {
    /// 一次體能訓練的 GPS 路線
    func routeLocations(of workout: HKWorkout) async -> [CLLocation] {
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))], sortDescriptors: [])
        guard let routes = try? await routeDescriptor.result(for: store), let route = routes.first else { return [] }
        var locations: [CLLocation] = []
        let query = HKWorkoutRouteQueryDescriptor(route)
        do {
            for try await location in query.results(for: store) { locations.append(location) }
        } catch {
            return locations
        }
        return locations
    }

    /// App 記錄的路線存成「健康」的體能訓練（熱量不另外寫，手機和手錶本來就會量）
    func saveRouteWorkout(kind: RouteKind, start: Date, end: Date, locations: [CLLocation]) async {
        guard isAvailable, end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = kind.activity
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else { return }
            guard locations.count > 1 else { return }
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await routeBuilder.insertRouteData(locations)
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
        } catch {
            print("存體能訓練失敗：\(error.localizedDescription)")
        }
    }
}

// MARK: - 記錄中

/// 按下「出發冒險」後的 GPS 記錄（螢幕關掉也會繼續）
@MainActor
final class RouteRecorder: ObservableObject {
    static let shared = RouteRecorder()

    enum Phase: Equatable { case idle, recording, paused, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var kind: RouteKind = .walk
    @Published private(set) var locations: [CLLocation] = []
    @Published private(set) var distance: Double = 0
    @Published private(set) var startDate: Date?
    /// 暫停的總秒數
    @Published private(set) var pausedTotal: TimeInterval = 0
    @Published private(set) var result: (route: SavedRoute, newCells: Int, coins: Int)?
    @Published var showRecorder = false
    @Published var locationDenied = false

    private let manager = CLLocationManager()
    private var updates: Task<Void, Never>?
    private var session: CLBackgroundActivitySession?
    private var pausedAt: Date?

    var elapsed: TimeInterval {
        guard let startDate else { return 0 }
        let paused = pausedTotal + (pausedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
        return Date.now.timeIntervalSince(startDate) - paused
    }

    func start(_ kind: RouteKind) {
        guard phase == .idle || phase == .finished else { return }
        manager.requestWhenInUseAuthorization()
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            locationDenied = true
            return
        }
        self.kind = kind
        locations = []
        distance = 0
        pausedTotal = 0
        pausedAt = nil
        result = nil
        startDate = .now
        phase = .recording
        showRecorder = true
        RouteActivityController.start(kind: kind, startDate: .now)
        session = CLBackgroundActivitySession()
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self else { return }
                    if let location = update.location { self.receive(location) }
                }
            } catch {
                print("定位中斷：\(error.localizedDescription)")
            }
        }
    }

    private func receive(_ location: CLLocation) {
        guard phase == .recording, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { return }
        if let last = locations.last {
            let meters = location.distance(from: last)
            let seconds = max(location.timestamp.timeIntervalSince(last.timestamp), 0.1)
            // GPS 飄移：一秒跑超過 12 公尺不算
            guard meters / seconds < 12 else { return }
            guard meters >= 3 else { return }
            distance += meters
        }
        locations.append(location)
        RouteActivityController.update(distance: distance, elapsed: elapsed, paused: false)
    }

    func pause() {
        guard phase == .recording else { return }
        pausedAt = .now
        phase = .paused
        RouteActivityController.update(distance: distance, elapsed: elapsed, paused: true, force: true)
    }

    func resume() {
        guard phase == .paused, let pausedAt else { return }
        pausedTotal += Date.now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
        // 暫停時走的路不接起來：從下一個點重新開始算
        if let last = locations.last { locations.append(last) }
        phase = .recording
        RouteActivityController.update(distance: distance, elapsed: elapsed, paused: false, force: true)
    }

    /// 結束並存檔
    func finish() async {
        if phase == .paused { resume() }
        updates?.cancel()
        updates = nil
        session?.invalidate()
        session = nil
        guard let startDate else { return }
        let end = Date.now
        let route = SavedRoute(id: UUID(), kind: kind, start: startDate, end: end, distance: distance,
                               points: RouteStore.thin(locations), source: .app,
                               climb: RouteStore.climb(of: locations), moving: RouteStore.movingTime(of: locations))
        let saved = RouteStore.shared.add(route)
        result = (route, saved.newCells, saved.coins)
        phase = .finished
        RouteActivityController.finish(distance: distance, elapsed: elapsed)
        await HealthKitManager.shared.saveRouteWorkout(kind: kind, start: startDate, end: end, locations: locations)
    }

    /// 不存，直接放棄
    func discard() {
        RouteActivityController.cancel()
        updates?.cancel()
        updates = nil
        session?.invalidate()
        session = nil
        phase = .idle
        showRecorder = false
    }

    func close() {
        phase = .idle
        showRecorder = false
        result = nil
    }

    #if DEBUG
    /// 開發用：-seedRecording 顯示記錄中的畫面，-seedRecordingDone 顯示完成畫面
    func seedForScreenshots() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedRecording") || arguments.contains("-seedRecordingDone") else { return }
        let points = (0...60).map { index -> CLLocation in
            let t = Double(index) / 60
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: 25.0330 + t * 0.008, longitude: 121.5654 + sin(t * 6) * 0.002),
                              altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                              timestamp: Date.now.addingTimeInterval(-900 + t * 900))
        }
        locations = points
        distance = RouteStore.length(of: points)
        startDate = .now.addingTimeInterval(-912)
        kind = .walk
        phase = .recording
        showRecorder = true
        RouteActivityController.start(kind: .walk, startDate: startDate!)
        RouteActivityController.update(distance: distance, elapsed: elapsed, paused: false, force: true)
        if arguments.contains("-seedRecordingDone") {
            let route = SavedRoute(id: UUID(), kind: .walk, start: startDate!, end: .now, distance: distance,
                                   points: RouteStore.thin(points), source: .app, climb: 8, moving: 880)
            result = (route, 23, 2)
            phase = .finished
        }
    }
    #endif
}
