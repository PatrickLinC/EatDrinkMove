import MapKit
import SwiftUI

// MARK: - 某一天的足跡地圖

/// 那天走過的路線：平常走動的軌跡（綠色）、出發冒險的路線（咖啡色），再加上照片
struct DayFootprintMap: View {
    let summary: FootprintDaySummary
    var photos: [RoutePhoto] = []
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            ForEach(Array(summary.track.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line)
                    .stroke(Color.move, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(summary.routes) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 5, lineCap: .square, lineJoin: .miter))
            }
            if let start = summary.track.first?.first ?? summary.routes.first?.coordinates.first {
                Annotation("", coordinate: start) { marker(Color.move) }
            }
            if let end = summary.track.last?.last ?? summary.routes.last?.coordinates.last {
                Annotation("", coordinate: end) { marker(Color.protein) }
            }
            ForEach(photos.filter { $0.coordinate != nil }) { photo in
                Annotation("", coordinate: photo.coordinate!) {
                    Image(uiImage: photo.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipped()
                        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onAppear { fit() }
        .onChange(of: summary.date) { fit() }
    }

    /// 起點、終點的小方塊
    private func marker(_ color: Color) -> some View {
        Rectangle().fill(color).frame(width: 12, height: 12).overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
    }

    private func fit() {
        guard let box = summary.region else { return }
        position = .region(MKCoordinateRegion(center: box.center,
                                              span: MKCoordinateSpan(latitudeDelta: box.latDelta, longitudeDelta: box.lonDelta)))
    }
}

/// 步數、距離、探索、新迷霧
struct FootprintStats: View {
    let summary: FootprintDaySummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stat(summary.steps.rounded0.formatted(), "步")
            stat((summary.meters / 1000).formatted(.number.precision(.fractionLength(1))), "公里")
            stat("\(summary.visited.count)", "格足跡")
            stat("\(summary.newCells)", "格新迷霧")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.px(18)).foregroundStyle(Color.move).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 昨天的結算

/// 每天第一次打開足跡時：昨天走了多少、去了哪些地方
struct FootprintRecapWindow: View {
    let date: Date
    var onOpen: (Date) -> Void
    @ObservedObject private var diary = FootprintDiary.shared
    @State private var summary: FootprintDaySummary?

    var body: some View {
        // 讀資料前先放一個看不見的佔位，.task 才會執行
        VStack(spacing: 0) {
            if let summary, !summary.isEmpty {
                PixelWindow(title: "昨天的足跡", tint: .calorie) {
                    HStack(spacing: 10) {
                        CompanionAvatar(size: 36)
                        Text(Self.line(summary)).fixedSize(horizontal: false, vertical: true)
                    }
                    if summary.hasLines {
                        DayFootprintMap(summary: summary)
                            .frame(height: 180)
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                            .allowsHitTesting(false)
                    }
                    FootprintStats(summary: summary)
                    HStack(spacing: 10) {
                        Button("看這天的足跡") { onOpen(date) }
                            .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
                        Button("收下") { withAnimation { diary.dismissRecap() } }
                            .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                    }
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task { summary = await FootprintDaySummary.load(date) }
    }

    static func line(_ summary: FootprintDaySummary) -> String {
        var parts: [String] = []
        if summary.steps > 0 { parts.append("走了 \(summary.steps.rounded0.formatted()) 步") }
        if !summary.visited.isEmpty { parts.append("在 \(summary.visited.count) 格留下腳印") }
        if summary.newCells > 0 { parts.append("解除了 \(summary.newCells) 格新迷霧") }
        if !summary.routes.isEmpty { parts.append("出發冒險 \(summary.routes.count) 次") }
        return "昨天" + parts.joined(separator: "，") + "！"
    }
}

// MARK: - 足跡月曆

struct FootprintCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var diary = FootprintDiary.shared
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var steps: [Date: Double] = [:]
    @State private var selected: Date?

    private var days: [Date?] {
        let calendar = AppSettings.calendar
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (0..<count).map { month.adding(days: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button { shift(-1) } label: { PixelSprite(art: .arrowLeft, size: 14) }
                            .buttonStyle(.pixel(.secondary))
                            .accessibilityLabel("上個月")
                        Spacer()
                        Text(month.formatted(.dateTime.year().month(.wide))).font(.px(18))
                        Spacer()
                        Button { shift(1) } label: { PixelSprite(art: .arrowRight, size: 14) }
                            .buttonStyle(.pixel(.secondary))
                            .disabled(month.adding(days: 32) > Date.now.adding(days: 31))
                            .accessibilityLabel("下個月")
                    }
                    PixelWindow(title: "足跡月曆", tint: .move) {
                        let symbols = Self.weekdaySymbols
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                            ForEach(symbols, id: \.self) { Text($0).font(.px(12)).foregroundStyle(Color.soft) }
                            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                            }
                        }
                        HStack(spacing: 10) {
                            legend(Color.move, "有腳印")
                            legend(Color.move.opacity(0.35), "只有步數")
                        }
                        Text("打開「世界迷霧」的自動解除後，每天走過的地方都會記下來；出發冒險和用照片解除的地點也會記進那一天。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("足跡日記")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(item: Binding(get: { selected.map(DayChoice.init) }, set: { selected = $0?.date })) { choice in
                FootprintDaySheet(date: choice.date)
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task(id: month) {
            let end = min(month.adding(days: 32), Date.now)
            steps = await HealthKitManager.shared.dailySteps(from: month, to: end)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let footprints = diary.day(day)?.visited.count ?? 0
        let walked = steps[day] ?? 0
        let future = day > Date.now
        return Button { selected = day } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.px(12))
                    .foregroundStyle(future ? Color.track : Calendar.current.isDateInToday(day) ? Color.brand : Color.ink)
                Rectangle()
                    .fill(footprints > 0 ? Color.move : walked >= 1000 ? Color.move.opacity(0.35) : Color.track)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if footprints > 0 { PixelSprite(art: .footprint, size: 12, tint: .window) }
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(day.formatted(.dateTime.month().day()))，\(walked.rounded0) 步\(footprints > 0 ? "，有足跡" : "")")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.px(12)).foregroundStyle(Color.soft)
        }
    }

    private func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }

    private static var weekdaySymbols: [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let first = AppSettings.calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

private struct DayChoice: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - 某一天的足跡

struct FootprintDaySheet: View {
    @State var date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var summary: FootprintDaySummary?
    @State private var photos: [RoutePhoto] = []
    @State private var selectedRoute: SavedRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button { date = date.adding(days: -1) } label: { PixelSprite(art: .arrowLeft, size: 14) }
                            .buttonStyle(.pixel(.secondary))
                            .accessibilityLabel("前一天")
                        Spacer()
                        Text(date.formatted(.dateTime.month().day().weekday())).font(.px(18))
                        Spacer()
                        Button { date = date.adding(days: 1) } label: { PixelSprite(art: .arrowRight, size: 14) }
                            .buttonStyle(.pixel(.secondary))
                            .disabled(date.adding(days: 1) > Date.now)
                            .accessibilityLabel("後一天")
                    }
                    if let summary {
                        if !summary.hasLines {
                            Text("這天沒有畫出路線。打開足跡頁最下面「世界迷霧」的自動解除後，平常走路的路線也會記下來。")
                                .font(.px(12))
                                .foregroundStyle(Color.soft)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .pixelPanel(fill: .window, shadow: nil, lineWidth: 2)
                        } else {
                            DayFootprintMap(summary: summary, photos: photos)
                                .frame(height: 340)
                                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                                .id(summary.date)
                        }
                        PixelWindow(title: "這天的足跡", tint: .move) {
                            FootprintStats(summary: summary)
                            if !summary.visited.isEmpty {
                                Text("走過約 \(summary.area.formatted(.number.precision(.fractionLength(2)))) 平方公里。")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                        }
                        if !summary.routes.isEmpty {
                            PixelWindow(title: "出發冒險", tint: .brand, spacing: 0) {
                                ForEach(Array(summary.routes.enumerated()), id: \.element.id) { index, route in
                                    if index > 0 { PixelDivider() }
                                    Button { selectedRoute = route } label: {
                                        HStack(spacing: 10) {
                                            PixelSprite(art: route.kind.art, size: 20)
                                            Text("\(route.title)・\(route.kilometers) km")
                                            Spacer(minLength: 4)
                                            PixelSprite(art: .cursor, size: 12)
                                        }
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !photos.isEmpty {
                            PixelWindow(title: "這天的照片", tint: .water) {
                                RoutePhotoStrip(photos: photos) { _ in }
                                Text("有拍攝地點的照片會出現在地圖上。").font(.px(12)).foregroundStyle(Color.soft)
                            }
                        }
                    } else {
                        Text("讀取中…").font(.px(12)).foregroundStyle(Color.soft)
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("足跡日記")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(item: $selectedRoute) { RouteDetailSheet(route: $0) }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task(id: date) {
            summary = await FootprintDaySummary.load(date)
            photos = await RoutePhotoLibrary.photos(from: date.startOfDay, to: date.startOfDay.adding(days: 1), limit: 30, locatedOnly: true)
        }
    }
}
