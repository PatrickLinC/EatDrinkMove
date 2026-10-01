import CoreLocation
import Foundation
import MapKit
import Photos

// MARK: - 迷霧格子

/// 世界迷霧的細格子：約 44 公尺一格（比開拓地圖的 170 公尺細很多）
enum FogCell {
    static let latStep = 0.0004
    static let lonStep = 0.00044
    /// 一格大約幾平方公里
    static let area = 0.0445 * 0.0445

    static func id(lat: Int64, lon: Int64) -> Int64 { (lat << 32) | (lon & 0xFFFF_FFFF) }

    static func id(_ coordinate: CLLocationCoordinate2D) -> Int64 {
        id(lat: Int64((coordinate.latitude / latStep).rounded(.down)),
           lon: Int64((coordinate.longitude / lonStep).rounded(.down)))
    }

    static func indices(_ id: Int64) -> (lat: Int64, lon: Int64) {
        (id >> 32, Int64(Int32(truncatingIfNeeded: id)))
    }

    /// 合併成大塊（縮小地圖時用）：factor 格 × factor 格變一塊
    static func block(_ id: Int64, factor: Int64) -> Int64 {
        let (lat, lon) = indices(id)
        return Self.id(lat: floorDiv(lat, factor), lon: floorDiv(lon, factor))
    }

    /// 某一層的格子（或大塊）的西南角與東北角
    static func bounds(_ id: Int64, factor: Int64) -> (CLLocationCoordinate2D, CLLocationCoordinate2D) {
        let (lat, lon) = indices(id)
        let south = Double(lat * factor) * latStep, west = Double(lon * factor) * lonStep
        return (CLLocationCoordinate2D(latitude: south, longitude: west),
                CLLocationCoordinate2D(latitude: south + Double(factor) * latStep, longitude: west + Double(factor) * lonStep))
    }

    private static func floorDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
        value >= 0 ? value / divisor : (value - divisor + 1) / divisor
    }
}

// MARK: - 世界迷霧

/// 走過的地方就解除迷霧：背景省電定位（粗略）、出發冒險與手錶路線（精準）、照片與 GPX（補回過去）
@MainActor
final class WorldFogStore: NSObject, ObservableObject {
    static let shared = WorldFogStore()

    static let enabledKey = "worldFogEnabled"
    private static let backfilledKey = "worldFogBackfilled"

    /// 已解除的細格子
    @Published private(set) var cells = Set<Int64>()
    /// 縮小地圖時用的大塊（16 格一塊、256 格一塊）
    private(set) var blocks16 = Set<Int64>()
    private(set) var blocks256 = Set<Int64>()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: WorldFogStore.enabledKey)
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// 用照片解除時的進度（0–1）與結果
    @Published private(set) var photoProgress: Double?
    @Published var importMessage: String?

    private let manager = CLLocationManager()
    private var foreground = true
    private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "worldfog.bin")
    }

    private override init() {
        super.init()
        if let data = try? Data(contentsOf: Self.fileURL) {
            let ids = data.withUnsafeBytes { Array($0.bindMemory(to: Int64.self)) }
            insert(ids)
        }
        manager.delegate = self
        authorization = manager.authorizationStatus
        // 第一次：把已經記錄的路線補進迷霧（也記進那天的足跡日記）
        if !UserDefaults.standard.bool(forKey: Self.backfilledKey) {
            for route in RouteStore.shared.routes { clear(along: route.coordinates, save: false, day: route.start) }
            UserDefaults.standard.set(true, forKey: Self.backfilledKey)
            scheduleSave()
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedFog") { seedForScreenshots() }
        #endif
    }

    var clearedArea: Double { Double(cells.count) * FogCell.area }

    // MARK: 開關與定位

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            manager.requestAlwaysAuthorization()
            startMonitoring()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
            manager.stopUpdatingLocation()
        }
    }

    /// App 啟動時（包含在背景被位置變動叫醒）：開著的話繼續監聽
    func resumeIfEnabled() {
        if enabled { startMonitoring() }
    }

    private func startMonitoring() {
        // 大範圍位置變動與造訪地點：靠基地台、Wi-Fi，很省電，背景也收得到
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
        if foreground { startForegroundUpdates() }
    }

    /// App 開著的時候用比較準的定位
    private func startForegroundUpdates() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 30
        manager.startUpdatingLocation()
    }

    func enterForeground() {
        foreground = true
        authorization = manager.authorizationStatus
        if enabled { startForegroundUpdates() }
    }

    func enterBackground() {
        foreground = false
        // 背景只留省電的大範圍定位
        manager.stopUpdatingLocation()
        saveNow()
    }

    fileprivate func receive(_ location: CLLocation) {
        let accuracy = location.horizontalAccuracy
        // 太粗略的定位（200 公尺以上）不解除，免得沒去過的地方也開了一大圈
        guard accuracy >= 0, accuracy <= 200 else { return }
        let radius = accuracy <= 50 ? 60 : max(accuracy, 80)
        clear(around: location.coordinate, radius: radius, day: location.timestamp)
        // 夠準的點也記進足跡日記，畫成那天的路線
        FootprintDiary.shared.addTrack(location)
    }

    // MARK: 解除

    /// 沿著路線精準解除（每 20 公尺取一點，連同上下左右一格）；有 day 就記進那天的足跡日記
    func clear(along coordinates: [CLLocationCoordinate2D], save: Bool = true, day: Date? = nil) {
        var ids: [Int64] = []
        func mark(_ point: CLLocationCoordinate2D) {
            let (lat, lon) = FogCell.indices(FogCell.id(point))
            ids.append(FogCell.id(lat: lat, lon: lon))
            ids.append(FogCell.id(lat: lat + 1, lon: lon))
            ids.append(FogCell.id(lat: lat - 1, lon: lon))
            ids.append(FogCell.id(lat: lat, lon: lon + 1))
            ids.append(FogCell.id(lat: lat, lon: lon - 1))
        }
        for (index, point) in coordinates.enumerated() {
            mark(point)
            guard index > 0 else { continue }
            let previous = coordinates[index - 1]
            let meters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            let steps = Int(meters / 20)
            guard steps > 1, steps < 2000 else { continue }
            for step in 1..<steps {
                let t = Double(step) / Double(steps)
                mark(CLLocationCoordinate2D(latitude: previous.latitude + (point.latitude - previous.latitude) * t,
                                            longitude: previous.longitude + (point.longitude - previous.longitude) * t))
            }
        }
        let new = insert(ids)
        if let day { FootprintDiary.shared.record(visited: ids, newCells: new, on: day) }
        if save { scheduleSave() }
    }

    /// 解除某個點周圍一圈；有 day 就記進那天的足跡日記
    func clear(around center: CLLocationCoordinate2D, radius: Double, save: Bool = true, day: Date? = nil) {
        let latCells = Int64(radius / 44.5) + 1
        // 經度一格的寬度會隨緯度變窄：0.00044° × 111.32 公里 × cos(緯度)
        let lonCells = Int64(radius / (FogCell.lonStep * 111_320 * max(cos(center.latitude * .pi / 180), 0.1))) + 1
        let (lat0, lon0) = FogCell.indices(FogCell.id(center))
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var ids: [Int64] = []
        for dLat in -latCells...latCells {
            for dLon in -lonCells...lonCells {
                let id = FogCell.id(lat: lat0 + dLat, lon: lon0 + dLon)
                let (south, north) = FogCell.bounds(id, factor: 1)
                let middle = CLLocation(latitude: (south.latitude + north.latitude) / 2, longitude: (south.longitude + north.longitude) / 2)
                if middle.distance(from: origin) <= radius { ids.append(id) }
            }
        }
        let new = insert(ids)
        if let day { FootprintDiary.shared.record(visited: ids, newCells: new, on: day) }
        if save { scheduleSave() }
    }

    /// 回傳新解除的格子數
    @discardableResult
    private func insert(_ ids: [Int64]) -> Int {
        var new = 0
        for id in ids where cells.insert(id).inserted {
            new += 1
            blocks16.insert(FogCell.block(id, factor: 16))
            blocks256.insert(FogCell.block(id, factor: 256))
        }
        if new > 0 { objectWillChange.send() }
        return new
    }

    // MARK: 用照片、GPX 補回過去的足跡

    /// 讀相簿裡有拍攝地點的照片，解除拍照地點周圍的迷霧（照片不會離開手機）
    func importPhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            importMessage = "沒有照片權限。可以到「設定 → 隱私權與安全性 → 照片」打開。"
            return
        }
        photoProgress = 0
        let spots = await Task.detached(priority: .userInitiated) { () -> [(coordinate: CLLocationCoordinate2D, date: Date?)] in
            let assets = PHAsset.fetchAssets(with: nil)
            var seen = Set<String>()
            var result: [(CLLocationCoordinate2D, Date?)] = []
            assets.enumerateObjects { asset, _, _ in
                guard let location = asset.location else { return }
                // 同一天、同一格只要一張
                let key = "\(FogCell.id(location.coordinate))-\(asset.creationDate?.dayKey ?? "")"
                if seen.insert(key).inserted { result.append((location.coordinate, asset.creationDate)) }
            }
            return result
        }.value
        let before = cells.count
        for (index, spot) in spots.enumerated() {
            // 拍照那天的足跡日記也會記下這個地方
            clear(around: spot.coordinate, radius: 120, save: false, day: spot.date)
            if index % 200 == 0 {
                photoProgress = Double(index) / Double(max(spots.count, 1))
                await Task.yield()
            }
        }
        photoProgress = nil
        scheduleSave()
        FootprintDiary.shared.saveNow()
        importMessage = "從 \(spots.count) 個拍照地點解除了 \(cells.count - before) 格迷霧，也補進了那幾天的足跡日記。"
    }

    /// 匯入 GPX 路線檔（其他 App 匯出的軌跡），沿著路線精準解除
    func importGPX(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importMessage = "讀不到這個檔案。"
            return
        }
        let parser = GPXPointParser(data: data)
        let before = cells.count
        clear(along: parser.trackPoints, save: false)
        for point in parser.waypoints { clear(around: point, radius: 100, save: false) }
        scheduleSave()
        importMessage = parser.trackPoints.isEmpty && parser.waypoints.isEmpty
            ? "這個檔案裡沒有路線。"
            : "匯入 \(parser.trackPoints.count + parser.waypoints.count) 個點，解除了 \(cells.count - before) 格迷霧。"
    }

    // MARK: 畫圖用

    /// 地圖目前範圍裡要挖空的格子：放大時用細格，縮小時用大塊
    func drawCells(in region: MKCoordinateRegion) -> (factor: Int64, ids: [Int64]) {
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        let factor: Int64 = span <= 0.06 ? 1 : span <= 1.2 ? 16 : 256
        let source: Set<Int64> = factor == 1 ? cells : factor == 16 ? blocks16 : blocks256
        let minLat = Int64(((region.center.latitude - region.span.latitudeDelta) / FogCell.latStep / Double(factor)).rounded(.down))
        let maxLat = Int64(((region.center.latitude + region.span.latitudeDelta) / FogCell.latStep / Double(factor)).rounded(.up))
        let minLon = Int64(((region.center.longitude - region.span.longitudeDelta) / FogCell.lonStep / Double(factor)).rounded(.down))
        let maxLon = Int64(((region.center.longitude + region.span.longitudeDelta) / FogCell.lonStep / Double(factor)).rounded(.up))
        let ids = source.filter { id in
            let (lat, lon) = FogCell.indices(id)
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
        return (factor, Array(ids.prefix(8000)))
    }

    // MARK: 存檔

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let ids = Array(cells)
        let data = ids.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    #if DEBUG
    /// 開發用：-seedFog 在台北解除幾塊迷霧（配合 -seedRoutes）
    private func seedForScreenshots() {
        // 足跡日記：路線記在出發那天，其他的分給昨天和今天
        let yesterday = Date.now.adding(days: -1)
        for route in RouteStore.shared.routes { clear(along: route.coordinates, save: false, day: route.start) }
        clear(around: CLLocationCoordinate2D(latitude: 25.0478, longitude: 121.5170), radius: 350, save: false, day: yesterday)
        clear(around: CLLocationCoordinate2D(latitude: 25.0263, longitude: 121.5436), radius: 250, save: false, day: .now)
        clear(along: (0...40).map { CLLocationCoordinate2D(latitude: 25.0478 - Double($0) * 0.0005, longitude: 121.5170 + Double($0) * 0.0012) },
              save: false, day: yesterday)
        // 昨天平常走動的軌跡（畫成綠色的線）
        for index in 0...60 {
            let t = Double(index)
            let coordinate = CLLocationCoordinate2D(latitude: 25.0478 - t * 0.0003 + sin(t / 6) * 0.0006, longitude: 121.5170 + t * 0.0007)
            FootprintDiary.shared.addTrack(CLLocation(coordinate: coordinate, altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 10,
                                                      timestamp: yesterday.startOfDay.addingTimeInterval(9 * 3600 + t * 40)))
        }
    }
    #endif
}

extension WorldFogStore: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in locations.forEach(self.receive) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard visit.horizontalAccuracy >= 0, visit.horizontalAccuracy <= 200 else { return }
        let coordinate = visit.coordinate
        let day = visit.arrivalDate == .distantPast ? Date.now : visit.arrivalDate
        Task { @MainActor in self.clear(around: coordinate, radius: 150, day: day) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}

/// 讀 GPX 檔裡的軌跡點（trkpt、rtept）和地標（wpt）
final class GPXPointParser: NSObject, XMLParserDelegate {
    private(set) var trackPoints: [CLLocationCoordinate2D] = []
    private(set) var waypoints: [CLLocationCoordinate2D] = []

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard let lat = attributeDict["lat"].flatMap(Double.init), let lon = attributeDict["lon"].flatMap(Double.init),
              abs(lat) <= 90, abs(lon) <= 180 else { return }
        let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        switch elementName.lowercased() {
        case "trkpt", "rtept": trackPoints.append(point)
        case "wpt": waypoints.append(point)
        default: break
        }
    }
}
