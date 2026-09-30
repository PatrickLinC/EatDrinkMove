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
    var steps: Double = 0
    var meters: Double = 0

    var area: Double { Double(visited.count) * FogCell.area }
    var isEmpty: Bool { visited.isEmpty && routes.isEmpty && steps == 0 }

    @MainActor
    static func load(_ date: Date) async -> FootprintDaySummary {
        let day = date.startOfDay
        let record = FootprintDiary.shared.day(day)
        var summary = FootprintDaySummary(date: day, visited: record?.visited ?? [], newCells: record?.newCells ?? 0,
                                          routes: RouteStore.shared.routes(on: day))
        let health = HealthKitManager.shared
        summary.steps = await health.sum(.stepCount, unit: .count(), from: day, to: day.adding(days: 1))
        summary.meters = await health.sum(.distanceWalkingRunning, unit: .meter(), from: day, to: day.adding(days: 1))
        return summary
    }

    /// 地圖要框住的範圍（格子加路線）
    var region: (center: CLLocationCoordinate2D, latDelta: Double, lonDelta: Double)? {
        var lats: [Double] = [], lons: [Double] = []
        for id in visited {
            let (south, north) = FogCell.bounds(id, factor: 1)
            lats += [south.latitude, north.latitude]
            lons += [south.longitude, north.longitude]
        }
        for route in routes {
            lats += route.coordinates.map(\.latitude)
            lons += route.coordinates.map(\.longitude)
        }
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return (CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                max((maxLat - minLat) * 1.4, 0.006), max((maxLon - minLon) * 1.4, 0.006))
    }
}
