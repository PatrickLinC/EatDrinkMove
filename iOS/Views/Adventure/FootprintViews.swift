import MapKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 足跡（真實地圖、開拓地圖）

struct FootprintView: View {
    @ObservedObject private var routes = RouteStore.shared
    @ObservedObject private var recorder = RouteRecorder.shared
    @ObservedObject private var diary = FootprintDiary.shared
    @State private var selected: SavedRoute?
    @State private var sharing: SavedRoute?
    @State private var today: FootprintDaySummary?
    @State private var showCalendar = false
    @State private var openedDay: Date?

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "足跡", subtitle: "FOOTPRINTS") {
                        PixelChip(text: "開拓 \(routes.cellCount) 格", color: .move)
                    }

                    if let recap = diary.pendingRecap {
                        FootprintRecapWindow(date: recap) { openedDay = $0 }
                    }
                    todayWindow
                    startWindow.id("start")
                    AdventureStatsWindow { selected = $0 }.id("stats")
                    routesWindow
                    statsWindow

                    PixelWindow(title: "世界迷霧", tint: .move) {
                        FogMapView(highlight: routes.routes(on: .now))
                            .frame(height: 360)
                            .clipShape(Rectangle())
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                        Text("去過的地方，像素霧就會散開。放大看得到約 44 公尺一格的細節。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    .id("fogMap")
                    WorldFogWindow().id("fog")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .task {
                FootprintDiary.shared.backfillIfNeeded()
                today = await FootprintDaySummary.load(.now)
                #if DEBUG
                // 開發用：-scrollTo start／stats／fogMap／fog 捲到某個位置截圖
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-scrollTo"), index + 1 < arguments.count {
                    try? await Task.sleep(for: .milliseconds(300))
                    reader.scrollTo(arguments[index + 1], anchor: .top)
                }
                // -routeDetail 打開第一條路線，-routeShare 直接打開分享路線圖
                if arguments.contains("-routeDetail") { selected = routes.routes.first }
                if arguments.contains("-routeShare") { sharing = routes.routes.first }
                // -footprintCalendar 打開足跡月曆，-footprintDay 打開昨天的足跡
                showCalendar = arguments.contains("-footprintCalendar")
                if arguments.contains("-footprintDay") { openedDay = Date.now.adding(days: -1) }
                #endif
                await routes.importFromHealth()
            }
            .sheet(item: $selected) { RouteDetailSheet(route: $0) }
            .sheet(isPresented: $showCalendar) { FootprintCalendarSheet() }
            .background {
                Color.clear.sheet(item: Binding(get: { openedDay.map(OpenedDay.init) }, set: { openedDay = $0?.date })) {
                    FootprintDaySheet(date: $0.date)
                }
            }
            .background { Color.clear.sheet(item: $sharing) { RouteShareSheet(route: $0) } }
            .alert("沒有定位權限", isPresented: $recorder.locationDenied) {
                Button("好") {}
            } message: {
                Text("請到「設定 → 隱私權與安全性 → 定位服務 → 卡路里大作戰」打開「使用 App 期間」。")
            }
        }
    }

    /// 今天的足跡：走過的格子、路線、步數，下面可以打開足跡月曆看以前
    private var todayWindow: some View {
        PixelWindow(title: "今日足跡", tint: .brand) {
            if let today, today.hasLines {
                DayFootprintMap(summary: today)
                    .frame(height: 220)
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
            } else {
                FogMapView(highlight: routes.routes(on: .now), showsFog: false)
                    .frame(height: 220)
                    .clipShape(Rectangle())
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                Text("今天還沒有畫出路線。打開最下面「世界迷霧」的自動解除，平常走路就會畫線；或按下面的「散步」出發冒險。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
            if let today { FootprintStats(summary: today) }
            Button("足跡月曆・看以前的足跡") { showCalendar = true }
                .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
        }
    }

    private var statsWindow: some View {
        PixelWindow(title: "開拓紀錄（出發冒險）") {
            HStack(spacing: 16) {
                stat("\(routes.cellCount)", "格")
                stat(routes.exploredArea.formatted(.number.precision(.fractionLength(1))), "平方公里")
                stat("\(routes.newCells(since: AppSettings.startOfWeek(.now)))", "本週新開拓")
            }
            Text("用「出發冒險」或手錶記錄的路線才算開拓（約 170 公尺一格），每 10 個新格子 1 枚元氣幣（一天最多 \(RouteStore.dailyExploreCoinCap) 枚）。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.px(20)).foregroundStyle(Color.move).monospacedDigit()
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startWindow: some View {
        PixelWindow(title: "出發冒險", tint: .brand) {
            HStack(spacing: 8) {
                ForEach(RouteKind.allCases) { kind in
                    Button {
                        recorder.start(kind)
                    } label: {
                        VStack(spacing: 6) {
                            PixelSprite(art: kind.art, size: 28)
                            Text(kind.title)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .pixelPanel(fill: .window, shadow: .pxShadow, lineWidth: 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("記錄 GPS 路線、距離與配速，結束後存進「健康」。用手錶「體能訓練」記的路線也會自動出現在這裡。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var routesWindow: some View {
        PixelWindow(title: "最近的路線", spacing: 0) {
            if routes.routes.isEmpty {
                Text("還沒有路線，按上面的「散步」出發吧！").font(.px(12)).foregroundStyle(Color.soft)
            }
            ForEach(Array(routes.routes.prefix(15).enumerated()), id: \.element.id) { index, route in
                if index > 0 { PixelDivider() }
                Button { selected = route } label: {
                    HStack(spacing: 10) {
                        PixelSprite(art: route.kind.art, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(route.kind.title)・\((route.distance / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                            Text("\(route.start.formatted(.dateTime.month().day().hour().minute()))・\(RouteStore.clock(route.activeTime))・配速 \(route.pace)")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                        }
                        Spacer(minLength: 4)
                        PixelChip(text: route.source == .app ? "App" : "手錶", color: route.source == .app ? .brand : .water)
                        PixelSprite(art: .cursor, size: 12)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 世界迷霧地圖：整張地圖蓋上像素霧，解除過的格子挖空；highlight 的路線畫成主色的粗線
struct FogMapView: View {
    @ObservedObject private var fog = WorldFogStore.shared
    @ObservedObject private var routes = RouteStore.shared
    var highlight: [SavedRoute] = []
    /// 關掉時只看路線（今日足跡、路線詳細）
    var showsFog = true
    /// 路線上拍的照片（有拍攝地點的才會出現在地圖上）
    var photos: [RoutePhoto] = []
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var region: MKCoordinateRegion?

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(highlight) { route in
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(Color.brand, style: StrokeStyle(lineWidth: 5, lineCap: .square, lineJoin: .miter))
                }
                ForEach(photos.filter { $0.coordinate != nil }) { photo in
                    Annotation("", coordinate: photo.coordinate!) {
                        Image(uiImage: photo.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipped()
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .continuous) { context in region = context.region }
            .overlay {
                Canvas { context, size in
                    guard showsFog, let region else { return }
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.track.opacity(0.82)))
                    context.blendMode = .destinationOut
                    let (factor, ids) = fog.drawCells(in: region)
                    for id in ids {
                        let (south, north) = FogCell.bounds(id, factor: factor)
                        guard let a = proxy.convert(south, to: .local), let b = proxy.convert(north, to: .local) else { continue }
                        // 多挖半點，格子之間不會留細縫
                        let rect = CGRect(x: min(a.x, b.x) - 0.5, y: min(a.y, b.y) - 0.5,
                                          width: abs(b.x - a.x) + 1, height: abs(b.y - a.y) + 1)
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if let route = highlight.first ?? routes.routes.first, let region = Self.region(for: route.coordinates) {
                position = .region(region)
            }
        }
    }

    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for point in coordinates {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
                                                         longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)))
    }
}

// MARK: - 記錄中的畫面

struct RecordingView: View {
    @ObservedObject private var recorder = RouteRecorder.shared
    @State private var confirmStop = false
    @State private var sharing: SavedRoute?
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    PixelTag(text: recorder.phase == .finished ? "\(recorder.kind.title)完成" : "\(recorder.kind.title)中",
                             fill: recorder.phase == .finished ? .move : .brand)
                    Spacer()
                    if recorder.phase == .paused { PixelChip(text: "暫停", color: .soft) }
                }

                Map(position: $position) {
                    if recorder.locations.count > 1 {
                        MapPolyline(coordinates: recorder.locations.map(\.coordinate))
                            .stroke(Color.brand, style: StrokeStyle(lineWidth: 6, lineCap: .square, lineJoin: .miter))
                    }
                    if let last = recorder.locations.last {
                        Annotation("", coordinate: last.coordinate) {
                            CompanionAvatar(size: 36)
                        }
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(maxHeight: .infinity)
                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 3))

                if let result = recorder.result {
                    resultWindow(result)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 12) {
                            stat((recorder.distance / 1000).formatted(.number.precision(.fractionLength(2))), "公里")
                            stat(RouteStore.clock(recorder.elapsed), "時間")
                            stat(RouteStore.pace(seconds: recorder.elapsed, meters: recorder.distance), "配速")
                        }
                        .padding(12)
                        .pixelPanel()
                    }
                    Text("螢幕關掉也會繼續記錄。").font(.px(12)).foregroundStyle(Color.soft)
                    HStack(spacing: 10) {
                        if recorder.phase == .paused {
                            Button("繼續") { recorder.resume() }
                                .buttonStyle(.pixel(.primary, fullWidth: true))
                        } else {
                            Button("暫停") { recorder.pause() }
                                .buttonStyle(.pixel(.secondary, fullWidth: true))
                        }
                        Button("結束") { confirmStop = true }
                            .buttonStyle(.pixel(.primary, fullWidth: true))
                    }
                }
            }
            .padding(16)
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .confirmationDialog("要結束這次冒險嗎？", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("結束並儲存") { Task { await recorder.finish() } }
            Button("不存，直接放棄", role: .destructive) { recorder.discard() }
            Button("繼續走", role: .cancel) {}
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.px(24)).foregroundStyle(Color.brand).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity)
    }

    private func resultWindow(_ result: (route: SavedRoute, newCells: Int, coins: Int)) -> some View {
        VStack(spacing: 12) {
            PixelWindow(title: "冒險完成！", tint: .move) {
                HStack(spacing: 12) {
                    stat((result.route.distance / 1000).formatted(.number.precision(.fractionLength(2))), "公里")
                    stat(RouteStore.clock(result.route.activeTime), "時間")
                    stat(result.route.pace, "配速")
                }
                if result.newCells > 0 {
                    Text("新開拓了 \(result.newCells) 格！").foregroundStyle(Color.move)
                }
                // 常走路線：跟上次比
                let runs = RouteMatcher.runs(of: result.route, in: RouteStore.shared.routes)
                if runs.count >= 2, let index = runs.firstIndex(where: { $0.id == result.route.id }), index > 0,
                   let comparison = RouteMatcher.comparison(result.route, previous: runs[index - 1]) {
                    Text("這條路線第 \(index + 1) 次，\(comparison.text)！")
                        .foregroundStyle(comparison.faster ? Color.move : Color.soft)
                }
                if result.coins > 0 {
                    HStack(spacing: 6) {
                        PixelSprite(art: .coin, size: 16)
                        Text("+\(result.coins) 元氣幣").foregroundStyle(Color.carbs)
                    }
                }
                Text("已經存到「健康」的體能訓練。").font(.px(12)).foregroundStyle(Color.soft)
            }
            HStack(spacing: 10) {
                Button("分享路線圖") { sharing = result.route }
                    .buttonStyle(.pixel(.primary, fullWidth: true))
                Button("完成") { recorder.close() }
                    .buttonStyle(.pixel(.secondary, fullWidth: true))
            }
        }
        .sheet(item: $sharing) { RouteShareSheet(route: $0) }
    }
}

// MARK: - 世界迷霧設定

struct WorldFogWindow: View {
    @ObservedObject private var fog = WorldFogStore.shared
    @State private var importingGPX = false

    var body: some View {
        PixelWindow(title: "解除迷霧", tint: .fat) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fog.clearedArea.formatted(.number.precision(.fractionLength(2))))
                        .font(.px(20)).foregroundStyle(Color.fat).monospacedDigit()
                    Text("平方公里已解除").font(.px(12)).foregroundStyle(Color.soft)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(fog.cells.count)").font(.px(20)).foregroundStyle(Color.fat).monospacedDigit()
                    Text("格").font(.px(12)).foregroundStyle(Color.soft)
                }
                Spacer(minLength: 0)
            }
            PixelDivider()
            Toggle("自動解除迷霧", isOn: Binding(get: { fog.enabled }, set: { fog.setEnabled($0) }))
            Text(statusText)
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
            PixelDivider()
            Text("補回過去的足跡").font(.px(12)).foregroundStyle(Color.soft)
            HStack(spacing: 8) {
                Button {
                    Task { await fog.importPhotos() }
                } label: {
                    Text(fog.photoProgress.map { "讀取中 \(Int($0 * 100))%" } ?? "用照片解除")
                }
                .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                .disabled(fog.photoProgress != nil)
                Button("匯入 GPX") { importingGPX = true }
                    .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
            }
            if let message = fog.importMessage {
                Text(message).font(.px(12)).foregroundStyle(Color.move).fixedSize(horizontal: false, vertical: true)
            }
            Text("照片只讀拍攝地點，不會離開這支 iPhone。「出發冒險」和手錶記錄的路線會沿著實際走的路精準解除。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(isPresented: $importingGPX,
                      allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(fog.importGPX) }
        }
    }

    private var statusText: String {
        guard fog.enabled else {
            return "打開後，平常帶著手機走動就會解除迷霧，不用按出發。用省電的大範圍定位（基地台、Wi-Fi），大約每移動 500 公尺更新一次。"
        }
        switch fog.authorization {
        case .authorizedAlways: return "背景也會自動解除。定位比較粗略，想要精準就用「出發冒險」。"
        case .authorizedWhenInUse: return "目前只在打開 App 時解除。想在背景也解除，請到「設定 → 卡路里大作戰 → 位置」改成「永遠」。"
        case .denied, .restricted: return "沒有定位權限。請到「設定 → 卡路里大作戰 → 位置」打開。"
        default: return "等待定位權限…"
        }
    }
}

private struct OpenedDay: Identifiable {
    let date: Date
    var id: Date { date }
}
