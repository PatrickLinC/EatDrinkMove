import HealthKit
import MapKit
import Photos
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 一條路線的完整數據

/// 路線本身以外，從「健康」讀這段時間的步數、熱量、心率
struct RouteExtras {
    var steps: Double?
    var calories: Double?
    var heartRate: Double?

    static func load(_ route: SavedRoute) async -> RouteExtras {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedRoutes") {
            return RouteExtras(steps: route.distance * 1.3, calories: route.distance * 0.06, heartRate: 118)
        }
        #endif
        let health = HealthKitManager.shared
        let steps = await health.sum(.stepCount, unit: .count(), from: route.start, to: route.end)
        let calories = await health.sum(.activeEnergyBurned, unit: .kilocalorie(), from: route.start, to: route.end)
        let heartRate = await health.average(.heartRate, unit: .count().unitDivided(by: .minute()), from: route.start, to: route.end)
        return RouteExtras(steps: steps > 0 ? steps : nil, calories: calories > 0 ? calories : nil, heartRate: heartRate)
    }
}

extension HealthKitManager {
    /// 一段時間的平均值（例如心率）；沒有資料回傳 nil
    func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .discreteAverage
        )
        return try? await descriptor.result(for: store)?.averageQuantity()?.doubleValue(for: unit)
    }
}

extension SavedRoute {
    /// 公里（兩位小數）
    var kilometers: String { (distance / 1000).formatted(.number.precision(.fractionLength(2))) }

    /// 「晚間散步」「清晨跑步」這種標題
    var title: String {
        let hour = Calendar.current.component(.hour, from: start)
        let part = switch hour {
        case 5..<8: "清晨"
        case 8..<11: "上午"
        case 11..<14: "中午"
        case 14..<17: "午後"
        case 17..<19: "傍晚"
        case 19..<23: "晚間"
        default: "深夜"
        }
        return part + kind.title
    }

    var dateText: String { start.formatted(.dateTime.year().month().day().hour().minute()) }

    /// 匯出成 GPX 暫存檔（其他地圖、運動 App 都讀得懂）
    func gpxFile() -> URL? {
        let iso = ISO8601DateFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(AppBrand.name)" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><name>\(title)</name><time>\(iso.string(from: start))</time></metadata>
        <trk><name>\(title)</name><type>\(kind == .run ? "running" : "walking")</type><trkseg>

        """
        for point in points where point.count >= 2 {
            xml += "<trkpt lat=\"\(point[0])\" lon=\"\(point[1])\"></trkpt>\n"
        }
        xml += "</trkseg></trk></gpx>\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory.appending(path: "\(title)-\(formatter.string(from: start)).gpx")
        return (try? xml.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}

/// 卡片和詳細頁共用的一格數據
struct RouteMetric: Identifiable {
    let label: String
    let value: String
    let unit: String
    var id: String { label }

    /// 依序：距離、時間、配速、步數、熱量、爬升、心率（沒有資料的不列）
    static func all(_ route: SavedRoute, _ extras: RouteExtras) -> [RouteMetric] {
        var result = [
            RouteMetric(label: "距離", value: route.kilometers, unit: "公里"),
            RouteMetric(label: "移動時間", value: RouteStore.clock(route.activeTime), unit: ""),
            RouteMetric(label: "配速", value: RouteStore.pace(seconds: route.activeTime, meters: route.distance), unit: "／公里"),
        ]
        if let steps = extras.steps { result.append(RouteMetric(label: "步數", value: Int(steps).formatted(), unit: "步")) }
        if let calories = extras.calories { result.append(RouteMetric(label: "熱量", value: "\(Int(calories.rounded()))", unit: "大卡")) }
        if let climb = route.climb { result.append(RouteMetric(label: "爬升", value: "\(Int(climb.rounded()))", unit: "公尺")) }
        if let heartRate = extras.heartRate {
            result.append(RouteMetric(label: "平均心率", value: "\(Int(heartRate.rounded()))", unit: "下／分"))
        }
        return result
    }
}

// MARK: - 路線詳細

struct RouteDetailSheet: View {
    let route: SavedRoute
    @Environment(\.dismiss) private var dismiss
    @State private var extras = RouteExtras()
    @State private var sharing = false
    @State private var gpx: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FogMapView(highlight: [route], showsFog: false)
                        .frame(height: 320)
                        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            PixelSprite(art: route.kind.art, size: 20)
                            Text(route.dateText).font(.px(12)).foregroundStyle(Color.soft)
                            Spacer(minLength: 4)
                            PixelChip(text: route.source == .app ? "App" : "手錶", color: route.source == .app ? .brand : .water)
                        }
                        Text(route.title).font(.px(28))
                    }
                    PixelWindow(title: "冒險數據", tint: .brand) {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                  alignment: .leading, spacing: 14) {
                            ForEach(RouteMetric.all(route, extras)) { metric in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric.label).font(.px(12)).foregroundStyle(Color.soft)
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text(metric.value).font(.px(22)).foregroundStyle(Color.brand).monospacedDigit()
                                        Text(metric.unit).font(.px(12)).foregroundStyle(Color.soft)
                                    }
                                }
                            }
                        }
                        Text(route.source == .app ? "用卡路里大作戰記錄，已存到「健康」。" : "從「健康」讀進來的手錶體能訓練。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    HStack(spacing: 10) {
                        Button("分享路線圖") { sharing = true }
                            .buttonStyle(.pixel(.primary, fullWidth: true))
                        if let gpx {
                            ShareLink(item: gpx) { Text("匯出 GPX") }
                                .buttonStyle(.pixel(.secondary, fullWidth: true))
                        }
                    }
                    Text("路線圖存成圖片；GPX 是路線檔，可以匯入其他地圖或運動 App。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("路線")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(isPresented: $sharing) { RouteShareSheet(route: route) }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task {
            gpx = route.gpxFile()
            extras = await RouteExtras.load(route)
        }
    }
}

// MARK: - 路線圖樣式

/// 都是 9:16（直接可以放限時動態）；透明的可以疊在自己拍的照片上
enum RouteCardStyle: String, CaseIterable, Identifiable {
    case mapCard, fullMap, night, routeStats, routeOnly, statsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mapCard: "地圖卡"
        case .fullMap: "滿版地圖"
        case .night: "夜間卡"
        case .routeStats: "路線＋數據"
        case .routeOnly: "只有路線"
        case .statsOnly: "數據直排"
        }
    }

    var isTransparent: Bool { [.routeStats, .routeOnly, .statsOnly].contains(self) }

    static let size = CGSize(width: 360, height: 640)
}

/// 產生路線圖：地圖截圖只拍一次，縮圖和存檔都用同一份
@MainActor
final class RouteCardModel: ObservableObject {
    let route: SavedRoute
    @Published private(set) var extras = RouteExtras()
    @Published private(set) var thumbnails: [RouteCardStyle: UIImage] = [:]
    private var squareMap: UIImage?
    private var tallMap: UIImage?

    init(route: SavedRoute) { self.route = route }

    func load() async {
        guard thumbnails.isEmpty else { return }
        extras = await RouteExtras.load(route)
        squareMap = await Self.snapshot(route, size: CGSize(width: 324, height: 324), shiftUp: false)
        tallMap = await Self.snapshot(route, size: RouteCardStyle.size, shiftUp: true)
        for style in RouteCardStyle.allCases {
            thumbnails[style] = render(style, scale: 1.5)
        }
        #if DEBUG
        // 開發用：-routeShareDump 把六張大圖存到暫存資料夾檢查
        if ProcessInfo.processInfo.arguments.contains("-routeShareDump") {
            for style in RouteCardStyle.allCases {
                try? png(style)?.write(to: FileManager.default.temporaryDirectory.appending(path: "card-\(style.rawValue).png"))
            }
        }
        #endif
    }

    func render(_ style: RouteCardStyle, scale: CGFloat) -> UIImage? {
        let card = RouteCard(style: style, route: route, extras: extras, squareMap: squareMap, tallMap: tallMap)
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light))
        renderer.scale = scale
        renderer.isOpaque = !style.isTransparent
        return renderer.uiImage
    }

    /// 存檔用的大圖：1080 × 1920 的 PNG
    func png(_ style: RouteCardStyle) -> Data? { render(style, scale: 3)?.pngData() }

    /// 地圖截圖，再畫上路線（墨色外框＋橘色線、方頭方角，起點綠格、終點紅格）
    /// shiftUp：滿版地圖下面要放數據，路線放在上半部
    static func snapshot(_ route: SavedRoute, size: CGSize, shiftUp: Bool) async -> UIImage? {
        let coordinates = route.coordinates
        guard var region = FogMapView.region(for: coordinates) else { return nil }
        if shiftUp {
            region.span.latitudeDelta *= 1.6
            region.center.latitude -= region.span.latitudeDelta * 0.18
        }
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        let options = MKMapSnapshotter.Options()
        options.preferredConfiguration = configuration
        options.region = region
        options.size = size
        options.scale = 3
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let light = UITraitCollection(userInterfaceStyle: .light)
        func ui(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: light) }
        let points = coordinates.map { snapshot.point(for: $0) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            if points.count > 1 {
                let path = UIBezierPath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.lineCapStyle = .square
                path.lineJoinStyle = .miter
                ui(.ink).setStroke()
                path.lineWidth = 10
                path.stroke()
                ui(.calorie).setStroke()
                path.lineWidth = 5
                path.stroke()
            }
            let cg = context.cgContext
            for (point, color) in [(points.first, Color.move), (points.last, Color.protein)] {
                guard let point else { continue }
                let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                cg.setFillColor(ui(.ink).cgColor)
                cg.fill(rect)
                cg.setFillColor(ui(color).cgColor)
                cg.fill(rect.insetBy(dx: 3, dy: 3))
            }
        }
    }
}

// MARK: - 選樣式、存檔的畫面

struct RouteShareSheet: View {
    @StateObject private var model: RouteCardModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RouteCardStyle
    @State private var shareFile: URL?
    @State private var message: String?
    @State private var busy = false
    @State private var done = 0

    init(route: SavedRoute, style: RouteCardStyle = .mapCard) {
        _model = StateObject(wrappedValue: RouteCardModel(route: route))
        _selected = State(initialValue: style)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(RouteCardStyle.allCases) { style in
                        thumbnail(style)
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("分享路線圖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .sensoryFeedback(.success, trigger: done)
        .task { await model.load() }
        .onChange(of: selected) { _, _ in
            shareFile = nil
            message = nil
        }
    }

    private func thumbnail(_ style: RouteCardStyle) -> some View {
        let isSelected = selected == style
        return Button {
            selected = style
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if style.isTransparent { CheckerBackground() }
                    if let image = model.thumbnails[style] {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Text("畫圖中…").font(.px(12)).foregroundStyle(Color.soft)
                    }
                }
                .aspectRatio(RouteCardStyle.size.width / RouteCardStyle.size.height, contentMode: .fit)
                .clipped()
                .overlay(Rectangle().strokeBorder(isSelected ? Color.brand : Color.ink, lineWidth: isSelected ? 4 : 2))
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(isSelected ? Color.brand : Color.window)
                        .frame(width: 12, height: 12)
                        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                    Text(style.title).font(.px(12)).foregroundStyle(isSelected ? Color.brand : Color.soft)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if let message {
                Text(message)
                    .font(.px(12))
                    .foregroundStyle(Color.move)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("存到相簿") { Task { await save() } }
                    .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
                Button("複製") { copy() }
                    .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                if let shareFile {
                    ShareLink(item: shareFile) { Text("分享") }
                        .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                } else {
                    Button("分享") { prepareShare() }
                        .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                }
            }
            .disabled(model.thumbnails.isEmpty || busy)
            Text(selected.isTransparent ? "透明背景的 PNG，可以疊在自己拍的照片或限時動態上。" : "1080 × 1920，剛好是限時動態的大小。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.window.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.ink).frame(height: 3) }
    }

    private func save() async {
        guard let data = model.png(selected) else { return }
        busy = true
        defer { busy = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = "沒辦法存到相簿。請到「設定 → 隱私權與安全性 → 照片 → 卡路里大作戰」允許加入照片。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            done += 1
            message = "「\(selected.title)」存到相簿了！"
        } catch {
            message = "存檔失敗，再試一次看看。"
        }
    }

    /// 用 PNG 放進剪貼簿，透明背景才留得住
    private func copy() {
        guard let data = model.png(selected) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
        done += 1
        message = "複製好了，可以直接貼到聊天或限時動態。"
    }

    /// 先把大圖寫成暫存檔，按鈕就會變成系統的分享選單
    private func prepareShare() {
        guard let data = model.png(selected) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "\(model.route.title)-\(formatter.string(from: model.route.start))-\(selected.title).png"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        guard (try? data.write(to: url)) != nil else { return }
        shareFile = url
        message = "準備好了，再按一次「分享」。"
    }
}

/// 透明圖預覽時的棋盤格
private struct CheckerBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.soft))
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(Color.ink.opacity(0.3)))
                }
            }
        }
    }
}

// MARK: - 六種卡片

struct RouteCard: View {
    let style: RouteCardStyle
    let route: SavedRoute
    let extras: RouteExtras
    let squareMap: UIImage?
    let tallMap: UIImage?

    private var metrics: [RouteMetric] { RouteMetric.all(route, extras) }

    var body: some View {
        Group {
            switch style {
            case .mapCard: mapCard
            case .fullMap: fullMap
            case .night: night
            case .routeStats: routeStats
            case .routeOnly: routeOnly
            case .statsOnly: statsOnly
            }
        }
        .frame(width: RouteCardStyle.size.width, height: RouteCardStyle.size.height)
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }

    // 地圖卡：紙色底、像素視窗、方形地圖＋數據
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(tag: .brand, date: .soft)
            mapImage(squareMap).frame(width: 324, height: 324)
                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 3))
            metricGrid(Array(metrics.prefix(6)), value: .brand, label: .soft)
            Spacer(minLength: 0)
            PixelDivider()
            brandFooter(text: .ink, sub: .soft)
        }
        .padding(18)
        .background { PixelPanel(fill: .window, shadow: nil, lineWidth: 3) }
        .padding(8)
        .background(Color.paper)
    }

    // 滿版地圖：整張都是地圖，下面一個像素視窗放數據
    private var fullMap: some View {
        ZStack(alignment: .bottom) {
            mapImage(tallMap)
            VStack(alignment: .leading, spacing: 10) {
                header(tag: .brand, date: .soft)
                metricGrid(Array(metrics.prefix(3)), value: .brand, label: .soft)
                brandFooter(text: .ink, sub: .soft)
            }
            .padding(14)
            .background { PixelPanel(fill: .window, shadow: .pxShadow, lineWidth: 3) }
            .padding(14)
        }
        .overlay(alignment: .topLeading) {
            PixelTag(text: AppBrand.name, fill: .ink, size: 12).padding(14)
        }
    }

    // 夜間卡：墨色底，路線和字都用亮色
    private var night: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(tag: .calorie, date: .track)
            RouteLine(coordinates: route.coordinates, color: .calorie, outline: .window)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
            metricGrid(Array(metrics.prefix(6)), value: .window, label: .track)
            Spacer(minLength: 0)
            brandFooter(text: .window, sub: .track)
        }
        .padding(22)
        .background(Color.ink)
        .overlay(Rectangle().strokeBorder(Color.calorie, lineWidth: 4).padding(8))
        .environment(\.colorScheme, .light)
    }

    // 透明：路線＋數據
    private var routeStats: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            RouteLine(coordinates: route.coordinates, color: .calorie, outline: .ink)
                .frame(width: 300, height: 320)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(metrics.prefix(3))) { metric in
                    outlinedMetric(metric, valueSize: 22)
                }
            }
            outlinedBrand
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // 透明：只有路線
    private var routeOnly: some View {
        VStack(spacing: 16) {
            RouteLine(coordinates: route.coordinates, color: .calorie, outline: .ink)
                .frame(width: 320, height: 520)
            outlinedBrand
        }
        .padding(20)
    }

    // 透明：數據直排（大字）＋小路線
    private var statsOnly: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            ForEach(Array(metrics.prefix(4))) { metric in
                outlinedMetric(metric, valueSize: 40)
            }
            HStack(alignment: .bottom, spacing: 12) {
                RouteLine(coordinates: route.coordinates, color: .calorie, outline: .ink, lineWidth: 4)
                    .frame(width: 110, height: 110)
                outlinedBrand
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
    }

    // MARK: 零件

    private func header(tag: Color, date: Color) -> some View {
        HStack(spacing: 8) {
            PixelTag(text: route.title, fill: tag)
            Spacer(minLength: 4)
            Text(route.dateText).font(.px(12)).foregroundStyle(date)
        }
    }

    @ViewBuilder private func mapImage(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image).resizable()
        } else {
            Color.track
        }
    }

    private func metricGrid(_ items: [RouteMetric], value: Color, label: Color) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
            ForEach(items) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label).font(.px(12)).foregroundStyle(label)
                    Text(metric.value).font(.px(20)).foregroundStyle(value).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !metric.unit.isEmpty {
                        Text(metric.unit).font(.px(12)).foregroundStyle(label)
                    }
                }
            }
        }
    }

    private func brandFooter(text: Color, sub: Color) -> some View {
        HStack(spacing: 10) {
            CompanionAvatar(size: 32, animated: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppBrand.name).font(.px(12)).foregroundStyle(text)
                Text("元氣大陸冒險紀錄").font(.px(12)).foregroundStyle(sub)
            }
            Spacer(minLength: 4)
            PixelSprite(art: route.kind.art, size: 24)
        }
    }

    private func outlinedMetric(_ metric: RouteMetric, valueSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label).font(.px(12))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value).font(.px(valueSize)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                if !metric.unit.isEmpty { Text(metric.unit).font(.px(12)) }
            }
        }
        .foregroundStyle(Color.window)
        .modifier(InkOutline())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outlinedBrand: some View {
        HStack(spacing: 8) {
            CompanionAvatar(size: 28, animated: false)
            Text("\(AppBrand.name)・\(route.title)")
                .font(.px(12))
                .foregroundStyle(Color.window)
                .modifier(InkOutline())
        }
    }
}

/// 透明背景上的字加墨色外框，疊在任何照片上都看得清楚
private struct InkOutline: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .ink, radius: 0, x: 2, y: 0)
            .shadow(color: .ink, radius: 0, x: -2, y: 0)
            .shadow(color: .ink, radius: 0, x: 0, y: 2)
            .shadow(color: .ink, radius: 0, x: 0, y: -2)
    }
}

/// 只有路線形狀的圖（北方朝上、等比例縮放），外框＋主線，起點綠格、終點紅格
struct RouteLine: View {
    let coordinates: [CLLocationCoordinate2D]
    var color: Color
    var outline: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            RouteShape(coordinates: coordinates)
                .stroke(outline, style: StrokeStyle(lineWidth: lineWidth * 2, lineCap: .square, lineJoin: .miter))
            RouteShape(coordinates: coordinates)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
            marker(.start, fill: .move)
            marker(.end, fill: .protein)
        }
    }

    private func marker(_ marker: RouteShape.Marker, fill: Color) -> some View {
        RouteShape(coordinates: coordinates, marker: marker, markerSize: lineWidth * 2.4)
            .fill(fill)
            .overlay(RouteShape(coordinates: coordinates, marker: marker, markerSize: lineWidth * 2.4).stroke(outline, lineWidth: 3))
    }
}

struct RouteShape: Shape {
    enum Marker { case start, end }

    let coordinates: [CLLocationCoordinate2D]
    /// 指定時只畫起點或終點的小方塊
    var marker: Marker?
    var markerSize: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let points = coordinates.map(MKMapPoint.init)
        guard let first = points.first else { return Path() }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        // 留一點邊，線的外框和端點方塊才不會被切掉
        let inner = rect.insetBy(dx: 14, dy: 14)
        let width = max(maxX - minX, 1), height = max(maxY - minY, 1)
        let scale = min(inner.width / width, inner.height / height)
        let originX = inner.minX + (inner.width - width * scale) / 2
        let originY = inner.minY + (inner.height - height * scale) / 2
        let mapped = points.map { CGPoint(x: originX + ($0.x - minX) * scale, y: originY + ($0.y - minY) * scale) }

        var path = Path()
        switch marker {
        case .start?:
            path.addRect(CGRect(x: mapped[0].x - markerSize / 2, y: mapped[0].y - markerSize / 2, width: markerSize, height: markerSize))
        case .end?:
            if let last = mapped.last {
                path.addRect(CGRect(x: last.x - markerSize / 2, y: last.y - markerSize / 2, width: markerSize, height: markerSize))
            }
        case nil:
            path.addLines(mapped)
        }
        return path
    }
}
