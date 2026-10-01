import CoreLocation
import Foundation
import HealthKit

// MARK: - 足跡日記

/// 每一天去過哪些格子（約 44 公尺一格）、解除了幾格新迷霧。
/// 世界迷霧自動解除、出發冒險、手錶路線、照片都會記進拍攝／經過的那一天。
@MainActor
final class FootprintDiary: ObservableObject {
    static let shared = FootprintDiary()

    struct Day: Codable {
        var visited: Set<Int64> = []
        /// 這天第一次解除的格子數
        var newCells = 0
        /// 這天走過的位置（緯度、經度、時間），畫成路線
        var track: [[Double]] = []

        init() {}

        // 新欄位用 decodeIfPresent，舊的日記不會讀不出來
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            visited = try container.decodeIfPresent(Set<Int64>.self, forKey: .visited) ?? []
            newCells = try container.decodeIfPresent(Int.self, forKey: .newCells) ?? 0
            track = try container.decodeIfPresent([[Double]].self, forKey: .track) ?? []
        }
    }

    /// dayKey → 那天的足跡
    @Published private(set) var days: [String: Day] = [:]
    private var saveTask: Task<Void, Never>?

    private static let recapKey = "footprintRecapSeen"
    private static let backfilledKey = "footprintDiaryBackfilled"

    private static var fileURL: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "footprints.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([String: Day].self, from: data) {
            days = saved
        }
    }

    /// 第一次：把已經記錄的路線補進日記（每條路線記在出發那天）
    func backfillIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.backfilledKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.backfilledKey)
        for route in RouteStore.shared.routes {
            WorldFogStore.shared.clear(along: route.coordinates, save: false, day: route.start)
        }
        WorldFogStore.shared.saveNow()
    }

    func record(visited: [Int64], newCells: Int, on date: Date) {
        guard !visited.isEmpty else { return }
        let key = date.dayKey
        var day = days[key] ?? Day()
        day.visited.formUnion(visited)
        day.newCells += newCells
        days[key] = day
        scheduleSave()
    }

    /// 記一個位置點：要夠準（100 公尺內），離上一點 20 公尺以上才記
    func addTrack(_ location: CLLocation) {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= 100 else { return }
        let key = location.timestamp.dayKey
        var day = days[key] ?? Day()
        if let last = day.track.last, last.count >= 2,
           CLLocation(latitude: last[0], longitude: last[1]).distance(from: location) < 20 { return }
        guard day.track.count < 5000 else { return }
        let coordinate = location.coordinate
        day.track.append([coordinate.latitude, coordinate.longitude, location.timestamp.timeIntervalSince1970])
        days[key] = day
        scheduleSave()
    }

    func day(_ date: Date) -> Day? { days[date.dayKey] }

    // MARK: 昨天的結算

    /// 今天第一次打開足跡時顯示昨天的結算（看過就不再出現）
    var pendingRecap: Date? {
        let yesterday = Date.now.startOfDay.adding(days: -1)
        guard UserDefaults.standard.string(forKey: Self.recapKey) != yesterday.dayKey else { return nil }
        return yesterday
    }

    func dismissRecap() {
        UserDefaults.standard.set(Date.now.startOfDay.adding(days: -1).dayKey, forKey: Self.recapKey)
        objectWillChange.send()
    }

    // MARK: 存檔

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        // 只留最近兩年
        let cutoff = Date.now.adding(days: -730).dayKey
        let kept = days.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

/// 某一天的足跡摘要：格子、路線、步數、距離
struct FootprintDaySummary {
    let date: Date
    let visited: Set<Int64>
    let newCells: Int
    let routes: [SavedRoute]
    /// 平常走動的位置軌跡（已經切成一段一段：中間斷超過 30 分鐘或 1.5 公里就分開）
    var track: [[CLLocationCoordinate2D]] = []
    var steps: Double = 0
    var meters: Double = 0

    var area: Double { Double(visited.count) * FogCell.area }
    var isEmpty: Bool { visited.isEmpty && routes.isEmpty && track.isEmpty && steps == 0 }
    var hasLines: Bool { !routes.isEmpty || !track.isEmpty }

    @MainActor
    static func load(_ date: Date) async -> FootprintDaySummary {
        let day = date.startOfDay
        let record = FootprintDiary.shared.day(day)
        var summary = FootprintDaySummary(date: day, visited: record?.visited ?? [], newCells: record?.newCells ?? 0,
                                          routes: RouteStore.shared.routes(on: day))
        summary.track = Self.segments(record?.track ?? [])
        let health = HealthKitManager.shared
        summary.steps = await health.sum(.stepCount, unit: .count(), from: day, to: day.adding(days: 1))
        summary.meters = await health.sum(.distanceWalkingRunning, unit: .meter(), from: day, to: day.adding(days: 1))
        return summary
    }

    /// 把位置點切成一段一段的線
    static func segments(_ points: [[Double]]) -> [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var last: (location: CLLocation, time: Double)?
        for point in points.sorted(by: { ($0.count > 2 ? $0[2] : 0) < ($1.count > 2 ? $1[2] : 0) }) where point.count >= 3 {
            let location = CLLocation(latitude: point[0], longitude: point[1])
            if let last, point[2] - last.time > 30 * 60 || location.distance(from: last.location) > 1500 {
                if current.count > 1 { result.append(current) }
                current = []
            }
            current.append(location.coordinate)
            last = (location, point[2])
        }
        if current.count > 1 { result.append(current) }
        return result
    }

    /// 地圖要框住的範圍：有路線就框路線，沒有才框格子
    var region: (center: CLLocationCoordinate2D, latDelta: Double, lonDelta: Double)? {
        var lats: [Double] = [], lons: [Double] = []
        for route in routes {
            lats += route.coordinates.map(\.latitude)
            lons += route.coordinates.map(\.longitude)
        }
        for line in track {
            lats += line.map(\.latitude)
            lons += line.map(\.longitude)
        }
        if lats.isEmpty {
            for id in visited {
                let (south, north) = FogCell.bounds(id, factor: 1)
                lats += [south.latitude, north.latitude]
                lons += [south.longitude, north.longitude]
            }
        }
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return (CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                max((maxLat - minLat) * 1.4, 0.006), max((maxLon - minLon) * 1.4, 0.006))
    }
}
