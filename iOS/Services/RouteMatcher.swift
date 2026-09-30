import CoreLocation
import Foundation

// MARK: - 常走路線

/// 同一種冒險、走過的格子重疊七成以上、距離差不多、起點相近，就算同一條路線
@MainActor
enum RouteMatcher {
    private static var cellCache: [UUID: Set<Int64>] = [:]

    private static func cells(_ route: SavedRoute) -> Set<Int64> {
        if let cached = cellCache[route.id] { return cached }
        let cells = ExploreCell.cells(along: route.coordinates)
        cellCache[route.id] = cells
        return cells
    }

    static func isSame(_ a: SavedRoute, _ b: SavedRoute) -> Bool {
        guard a.kind == b.kind, a.distance > 300, b.distance > 300 else { return false }
        let ratio = a.distance / b.distance
        guard ratio > 0.8, ratio < 1.25 else { return false }
        guard let startA = a.coordinates.first, let startB = b.coordinates.first,
              CLLocation(latitude: startA.latitude, longitude: startA.longitude)
                .distance(from: CLLocation(latitude: startB.latitude, longitude: startB.longitude)) < 400 else { return false }
        let cellsA = cells(a), cellsB = cells(b)
        let union = cellsA.union(cellsB).count
        return union > 0 && Double(cellsA.intersection(cellsB).count) / Double(union) >= 0.7
    }

    /// 跟這條一樣的路線（含自己），從舊到新
    static func runs(of route: SavedRoute, in routes: [SavedRoute]) -> [SavedRoute] {
        routes.filter { $0.id == route.id || isSame($0, route) }.sorted { $0.start < $1.start }
    }

    /// 走過 3 次以上的路線，次數多的在前
    static func frequent(in routes: [SavedRoute], minimum: Int = 3) -> [[SavedRoute]] {
        var groups: [[SavedRoute]] = []
        for route in routes.sorted(by: { $0.start > $1.start }) {
            if let index = groups.firstIndex(where: { isSame($0[0], route) }) {
                groups[index].append(route)
            } else {
                groups.append([route])
            }
        }
        return groups.filter { $0.count >= minimum }
            .map { $0.sorted { $0.start < $1.start } }
            .sorted { $0.count > $1.count }
    }

    /// 「3.4 公里環狀散步」
    static func name(_ route: SavedRoute) -> String {
        let loop: Bool = {
            guard let first = route.coordinates.first, let last = route.coordinates.last else { return false }
            return CLLocation(latitude: first.latitude, longitude: first.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) < 250
        }()
        return "\((route.distance / 1000).formatted(.number.precision(.fractionLength(1)))) 公里\(loop ? "環狀" : "")\(route.kind.title)"
    }

    /// 跟上一次比：「比上次快 42 秒」
    static func comparison(_ route: SavedRoute, previous: SavedRoute) -> (text: String, faster: Bool)? {
        let diff = previous.activeTime - route.activeTime
        guard abs(diff) >= 1 else { return ("跟上次一樣快", true) }
        let seconds = Int(abs(diff).rounded())
        let amount = seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds) 秒"
        return (diff > 0 ? "比上次快 \(amount)" : "比上次慢 \(amount)", diff > 0)
    }
}
