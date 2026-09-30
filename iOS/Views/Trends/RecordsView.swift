import SwiftData
import SwiftUI

/// 戰績：每日目標、AI 軍師、每週週報
struct RecordsView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @AppStorage(SettingKey.waterGoal) private var waterGoal = AppSettings.Defaults.waterGoal
    @AppStorage(SettingKey.stepGoal) private var stepGoal = AppSettings.Defaults.stepGoal
    @AppStorage(SettingKey.burnGoal) private var burnGoal = AppSettings.Defaults.burnGoal
    @State private var refresh = UUID()
    @State private var insightMode: InsightView.Mode?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "戰績", subtitle: "RECORDS")

                    PixelWindow(title: "每日目標", spacing: 0) {
                        HStack(spacing: 16) {
                            goal("\(calorieGoal.rounded0)", "大卡", color: .calorie)
                            goal("\(waterGoal.rounded0)", "ml 水", color: .water)
                            goal(stepGoal.rounded0.formatted(), "步", color: .move)
                            goal("\(burnGoal.rounded0)", "燃燒", color: .protein)
                        }
                        .padding(.bottom, 4)
                        PixelDivider()
                        NavigationLink { PlanView() } label: {
                            PixelMenuRow(title: "調整目標", art: .scale)
                        }
                        .buttonStyle(.plain)
                    }

                    PixelWindow(title: "AI 軍師") {
                        HStack(spacing: 12) {
                            PixelSprite(art: .star, size: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("分析最近的戰況")
                                Text("飲食給 3 個明天就做得到的建議；冒險週報找出睡眠、步數、精神力之間的關聯")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 8) {
                            Button("飲食分析") { insightMode = .food }
                                .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
                            Button("冒險週報") { insightMode = .adventure }
                                .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
                        }
                    }

                    WeeklyReportWindow(refresh: refresh)
                    ChronicleWindow()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: router.selectedTab) { _, tab in
                if tab == .records { refresh = UUID() }
            }
            .sheet(item: $insightMode) { InsightView(mode: $0) }
        }
    }

    private func goal(_ value: String, _ unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.px(20)).foregroundStyle(color).monospacedDigit()
            Text(unit).font(.px(12)).foregroundStyle(Color.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 週報

enum WeeklyMetric: String, CaseIterable, Identifiable {
    case calories, water, steps, burned, sodium, weight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: "熱量"
        case .water: "喝水"
        case .steps: "步數"
        case .burned: "運動"
        case .sodium: "鈉"
        case .weight: "體重"
        }
    }

    var unit: String {
        switch self {
        case .calories, .burned: "大卡"
        case .steps: "步"
        case .water: "ml"
        case .sodium: "mg"
        case .weight: "kg"
        }
    }

    var color: Color {
        switch self {
        case .calories: .calorie
        case .water: .water
        case .steps: .move
        case .burned: .protein
        case .sodium: .sodium
        case .weight: .brand
        }
    }

    /// 超過目標是壞事（熱量、鈉）
    var overIsBad: Bool { self == .calories || self == .sodium }
}

struct WeeklyReportWindow: View {
    let refresh: UUID
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @AppStorage(SettingKey.waterGoal) private var waterGoal = AppSettings.Defaults.waterGoal
    @AppStorage(SettingKey.sodiumGoal) private var sodiumGoal = AppSettings.Defaults.sodiumGoal
    @AppStorage(SettingKey.stepGoal) private var stepGoal = AppSettings.Defaults.stepGoal
    @AppStorage(SettingKey.burnGoal) private var burnGoal = AppSettings.Defaults.burnGoal
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @AppStorage(SettingKey.targetWeightKG) private var targetWeightKG = AppSettings.Defaults.targetWeightKG
    @State private var metric: WeeklyMetric = .calories
    @State private var weekStart = AppSettings.startOfWeek(.now)
    @State private var values: [Double?] = Array(repeating: nil, count: 7)
    @State private var selectedIndex: Int?

    private var days: [Date] { (0..<7).map { weekStart.adding(days: $0) } }

    private var goal: Double? {
        switch metric {
        case .calories: calorieGoal
        case .water: waterGoal
        case .sodium: sodiumGoal
        case .steps: stepGoal
        case .weight: targetWeightKG
        case .burned: burnGoal
        }
    }

    var body: some View {
        PixelWindow(title: "週報") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(WeeklyMetric.allCases) { item in
                    Button(item.title) {
                        metric = item
                        selectedIndex = nil
                    }
                    .buttonStyle(.pixel(metric == item ? .primary : .secondary, fullWidth: true, fontSize: 12))
                }
            }

            HStack(spacing: 8) {
                Button { weekStart = weekStart.adding(days: -7) } label: { PixelSprite(art: .arrowLeft, size: 14) }
                    .buttonStyle(.pixel(.secondary))
                    .accessibilityLabel("上一週")
                Spacer(minLength: 0)
                Text("\(weekStart.formatted(.dateTime.month().day())) - \(weekStart.adding(days: 6).formatted(.dateTime.month().day()))")
                    .font(.px(16))
                Spacer(minLength: 0)
                Button { weekStart = weekStart.adding(days: 7) } label: { PixelSprite(art: .arrowRight, size: 14) }
                    .buttonStyle(.pixel(.secondary))
                    .disabled(weekStart.adding(days: 7) > Date.now)
                    .accessibilityLabel("下一週")
            }

            summary

            if metric == .weight {
                PixelWeightChart(days: days, values: values, target: targetWeightKG, fallback: weightKG,
                                 selectedIndex: $selectedIndex)
            } else {
                PixelBarChart(days: days, values: values.map { $0 ?? 0 }, goal: goal, color: metric.color,
                              overIsBad: metric.overIsBad, selectedIndex: $selectedIndex)
            }

            if let index = selectedIndex {
                let value = values[index]
                Text("\(days[index].formatted(.dateTime.month().day().weekday()))：\(value.map { format($0) } ?? "沒有資料") \(value == nil ? "" : metric.unit)")
                    .font(.px(12))
                    .foregroundStyle(Color.brand)
            } else {
                Text("點長條可以看當天的數字。").font(.px(12)).foregroundStyle(Color.soft)
            }

            if metric == .weight {
                Button("記錄體重") { router.showWeight = true }
                    .buttonStyle(.pixel(.secondary, fullWidth: true))
            }
        }
        .task(id: "\(metric.rawValue)-\(weekStart.timeIntervalSince1970)-\(refresh)") { await load() }
    }

    private func format(_ value: Double) -> String {
        metric == .weight ? value.formatted(.number.precision(.fractionLength(1))) : value.rounded0.formatted()
    }

    @ViewBuilder private var summary: some View {
        let known = values.compactMap { $0 }.filter { $0 > 0 }
        let average = known.isEmpty ? 0 : known.sum { $0 } / Double(known.count)
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric == .weight ? "目前" : "每日平均").font(.px(12)).foregroundStyle(Color.soft)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric == .weight ? format(weightKG) : format(average))
                        .font(.px(24)).foregroundStyle(metric.color).monospacedDigit()
                    Text(metric.unit).font(.px(12)).foregroundStyle(Color.soft)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(metric == .weight ? "距離目標" : "達標").font(.px(12)).foregroundStyle(Color.soft)
                Text(rightStat).font(.px(16)).monospacedDigit()
            }
        }
    }

    private var rightStat: String {
        let known = values.compactMap { $0 }.filter { $0 > 0 }
        switch metric {
        case .weight:
            return "\(abs(weightKG - targetWeightKG).formatted(.number.precision(.fractionLength(1)))) kg"
        case .calories, .sodium:
            guard let goal else { return "-" }
            return "\(known.filter { $0 <= goal }.count)/7 天"
        case .water, .steps, .burned:
            guard let goal else { return "-" }
            return "\(known.filter { $0 >= goal }.count)/7 天"
        }
    }

    private func load() async {
        let end = min(weekStart.adding(days: 7), Date.now)
        var byDay: [Date: Double] = [:]
        switch metric {
        case .calories:
            byDay = LogService.shared.dayTotals(from: weekStart, days: 7).mapValues(\.calories)
        case .water:
            byDay = LogService.shared.dayTotals(from: weekStart, days: 7).mapValues(\.water)
        case .sodium:
            byDay = LogService.shared.dayTotals(from: weekStart, days: 7).mapValues(\.sodium)
        case .steps:
            byDay = await health.dailySteps(from: weekStart, to: end)
        case .burned:
            let totals = LogService.shared.dayTotals(from: weekStart, days: 7)
            let active = await health.dailyActiveCalories(from: weekStart, to: end)
            byDay = totals.mapValues(\.manualExercise).merging(active, uniquingKeysWith: +)
        case .weight:
            byDay = LogService.shared.dailyWeights(from: weekStart, days: 7)
        }
        values = days.map { byDay[$0] }
    }
}

// MARK: - 像素長條圖

/// 用方塊堆起來的長條圖，虛線是目標
struct PixelBarChart: View {
    let days: [Date]
    let values: [Double]
    let goal: Double?
    let color: Color
    let overIsBad: Bool
    @Binding var selectedIndex: Int?

    private let blocks = 12
    private let chartHeight: CGFloat = 156

    var body: some View {
        let top = Self.niceTop(max(values.max() ?? 0, goal ?? 0))
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    let value = values[index]
                    let filled = value <= 0 ? 0 : min(blocks, max(1, Int((value / top * Double(blocks)).rounded())))
                    let over = overIsBad && goal != nil && value > (goal ?? 0)
                    Button {
                        selectedIndex = selectedIndex == index ? nil : index
                    } label: {
                        VStack(spacing: 2) {
                            ForEach((0..<blocks).reversed(), id: \.self) { block in
                                Rectangle()
                                    .fill(block < filled ? (over ? Color.danger : color) : Color.clear)
                            }
                        }
                        .padding(2)
                        .background(Rectangle().fill(selectedIndex == index ? Color.track : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(days[index].formatted(.dateTime.month().day()))，\(value.rounded0)")
                }
            }
            .frame(height: chartHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ink).frame(height: 2).offset(y: 2)
            }
            .overlay(alignment: .topLeading) {
                if let goal, goal > 0 {
                    GeometryReader { geometry in
                        let y = geometry.size.height * (1 - min(goal / top, 1))
                        DashLine()
                            .stroke(Color.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .frame(height: 2)
                            .offset(y: y - 1)
                        Text("目標 \(goal.rounded0.formatted())")
                            .font(.px(12))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 4)
                            .background(Color.window)
                            .offset(x: geometry.size.width - 110, y: max(y - 18, 0))
                    }
                    .allowsHitTesting(false)
                }
            }

            DayLabels(days: days)
        }
    }

    /// 取整齊的上限，讓刻度是 0、500、1000… 這種好讀的數字
    static func niceTop(_ value: Double) -> Double {
        guard value > 0 else { return 100 }
        let raw = value * 1.1 / 4
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let step: Double
        switch normalized {
        case ...1: step = 1
        case ...2: step = 2
        case ...2.5: step = 2.5
        case ...5: step = 5
        default: step = 10
        }
        return step * magnitude * 4
    }
}

/// 體重：每天一個方塊，用直角線連起來
struct PixelWeightChart: View {
    let days: [Date]
    let values: [Double?]
    let target: Double
    let fallback: Double
    @Binding var selectedIndex: Int?

    private let chartHeight: CGFloat = 156

    var body: some View {
        let known = values.compactMap { $0 } + [target]
        let lower = ((known.min() ?? fallback) - 1).rounded(.down)
        let upper = ((known.max() ?? fallback) + 1).rounded(.up)

        VStack(spacing: 6) {
            GeometryReader { geometry in
                let size = geometry.size
                let column = size.width / 7
                let y: (Double) -> CGFloat = { kg in
                    size.height * (1 - (upper > lower ? (kg - lower) / (upper - lower) : 0.5))
                }
                let points: [(Int, CGPoint)] = values.enumerated().compactMap { index, kg in
                    guard let kg else { return nil }
                    return (index, CGPoint(x: column * (CGFloat(index) + 0.5), y: y(kg)))
                }

                ZStack(alignment: .topLeading) {
                    // 目標體重
                    DashLine()
                        .stroke(Color.soft, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: size.width, height: 2)
                        .offset(y: y(target) - 1)
                    Text("目標 \(target.formatted(.number.precision(.fractionLength(1))))")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .offset(x: size.width - 96, y: max(y(target) - 18, 0))

                    // 直角折線
                    Path { path in
                        guard let first = points.first?.1 else { return }
                        path.move(to: first)
                        for (_, point) in points.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x, y: path.currentPoint?.y ?? point.y))
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter))

                    ForEach(points, id: \.0) { index, point in
                        Rectangle()
                            .fill(selectedIndex == index ? Color.carbs : Color.brand)
                            .frame(width: 12, height: 12)
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                            .position(point)
                    }

                    // 點每一欄選日期
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { index in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { selectedIndex = selectedIndex == index ? nil : index }
                        }
                    }
                }
            }
            .frame(height: chartHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ink).frame(height: 2).offset(y: 2)
            }

            DayLabels(days: days)
        }
    }
}

/// 圖表下方的「一 9/21」
struct DayLabels: View {
    let days: [Date]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                    Text("\(Calendar.current.component(.day, from: day))")
                }
                .font(.px(12))
                .foregroundStyle(isToday ? Color.onBrand : Color.soft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(Rectangle().fill(isToday ? Color.brand : Color.clear))
            }
        }
    }
}

// MARK: - AI 軍師

struct InsightView: View {
    enum Mode: String, Identifiable {
        case food, adventure
        var id: String { rawValue }
        var title: String { self == .food ? "AI 軍師" : "冒險週報" }
        var loading: String { self == .food ? "正在分析最近 7 天的紀錄…" : "正在整理最近兩週的睡眠、步數和冒險…" }
    }

    var mode: Mode = .food
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager
    @State private var text: String?
    @State private var provider: AIProvider?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        PixelWindow(title: "軍師思考中") {
                            HStack(spacing: 12) {
                                PixelLoadingDots()
                                Text(mode.loading).foregroundStyle(Color.soft)
                            }
                        }
                    }
                    if let errorMessage {
                        PixelWindow(title: "出錯了", tint: .danger) {
                            Text(errorMessage).foregroundStyle(Color.danger)
                        }
                    }
                    if let text {
                        PixelWindow(title: mode == .food ? "軍師的建議" : "本週冒險週報") {
                            Text(Self.render(text))
                                .lineSpacing(6)
                                .textSelection(.enabled)
                            if let provider {
                                Text("由 \(provider.shortName) 分析，僅供參考，不能取代專業建議。")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await run() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(isLoading)
                        .accessibilityLabel("重新分析")
                }
            }
            .task { await run() }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }

    /// AI 常用 **粗體**，轉成 AttributedString 顯示，保留換行
    private static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func run() async {
        guard FoodAnalyzer.isReady else {
            let error: FoodAnalyzerError = FoodAnalyzer.provider == .apple ? .appleAIUnavailable : .missingKey
            errorMessage = error.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (result, usedProvider) = mode == .food
                ? try await FoodAnalyzer().insight(summary: await buildSummary())
                : try await FoodAnalyzer().adventureReport(summary: await AdventureReport.summary())
            text = result
            provider = usedProvider
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 把最近 7 天的數字整理成文字給 AI
    private func buildSummary() async -> String {
        let start = Date.now.startOfDay.adding(days: -6)
        let totals = LogService.shared.dayTotals(from: start, days: 7)
        let steps = await health.dailySteps(from: start, to: .now)
        let active = await health.dailyActiveCalories(from: start, to: .now)
        let weights = LogService.shared.dailyWeights(from: start, days: 7)

        var lines = [
            "每日目標：熱量 \(AppSettings.calorieGoal.rounded0) kcal、蛋白質 \(AppSettings.proteinGoal.rounded0) g、鈉上限 \(AppSettings.sodiumGoal.rounded0) mg、喝水 \(AppSettings.waterGoal.rounded0) ml、步數 \(AppSettings.stepGoal.rounded0)。",
            "每日運動消耗目標 \(AppSettings.burnGoal.rounded0) kcal。",
            "目前體重 \(AppSettings.weightKG.formatted()) kg，目標體重 \(AppSettings.targetWeightKG.formatted()) kg。",
            "",
            "最近 7 天：",
        ]
        for offset in 0..<7 {
            let day = start.adding(days: offset)
            let t = totals[day] ?? DayTotals()
            var parts = [
                "攝取 \(t.calories.rounded0) kcal",
                "蛋白質 \(t.protein.rounded0) g",
                "碳水 \(t.carbs.rounded0) g",
                "脂肪 \(t.fat.rounded0) g",
                "鈉 \(t.sodium.rounded0) mg",
                "喝水 \(t.water.rounded0) ml",
                "步數 \((steps[day] ?? 0).rounded0)",
                "運動消耗 \(((active[day] ?? 0) + t.manualExercise).rounded0) kcal",
            ]
            if let kg = weights[day] { parts.append("體重 \(kg.formatted()) kg") }
            let label = day.formatted(.dateTime.month().day().weekday())
            lines.append("\(label)：" + parts.joined(separator: "、"))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 記錄體重

/// 記錄體重（同步寫入 Apple 健康）
struct LogWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @State private var kg: Double = AppSettings.weightKG
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        HStack {
                            TextField("體重", value: $kg, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .font(.px(32))
                            Text("公斤").foregroundStyle(Color.soft)
                        }
                        DatePicker("時間", selection: $date)
                        if let latest = health.latestWeight {
                            Button("使用「健康」裡最新的體重：\(latest.formatted(.number.precision(.fractionLength(1)))) kg") {
                                kg = (latest * 10).rounded() / 10
                            }
                        }
                    } footer: {
                        Text("建議每天同一時間（例如早上起床、上完廁所後）量，比較看得出趨勢。").font(.px(12))
                    }

                    if !entries.isEmpty {
                        Section {
                            ForEach(entries.prefix(20)) { entry in
                                LabeledContent(entry.date.formatted(date: .abbreviated, time: .shortened),
                                               value: "\(entry.kg.formatted()) kg")
                            }
                            .onDelete { offsets in
                                let recent = Array(entries.prefix(20))
                                for index in offsets { LogService.shared.delete(recent[index]) }
                            }
                        } header: {
                            Text("最近的紀錄").font(.px(12))
                        }
                    }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("量體重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        LogService.shared.logWeight(kg, date: date)
                        AppSettings.applyAutoGoalsIfNeeded()
                        dismiss()
                    }
                    .disabled(kg < 20 || kg > 300)
                }
            }
        }
    }
}
