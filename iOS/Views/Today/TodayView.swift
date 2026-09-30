import SwiftData
import SwiftUI

/// 今日：日期、狀態、指令、任務、水壺、冒險日誌
struct TodayView: View {
    @Query private var todayFoods: [FoodEntry]
    @State private var selectedDay = Date.now.startOfDay
    @State private var streak = 0

    init() {
        let start = Date.now.startOfDay
        let end = start.adding(days: 1)
        _todayFoods = Query(filter: #Predicate<FoodEntry> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: AppBrand.name, subtitle: AppBrand.subtitle) {
                        PixelChip(text: streak > 0 ? "連續 \(streak) 天" : "今天開始", color: .calorie)
                            .accessibilityLabel("連續記錄 \(streak) 天")
                    }
                    DaySwitcher(day: $selectedDay)
                    DayContent(day: selectedDay)
                        .id(selectedDay)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: todayFoods.count) { streak = LogService.shared.streak() }
            #if DEBUG
            // 開發用：-todayScroll habits 捲到每日任務（截圖檢查）
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-todayScroll"), index + 1 < arguments.count {
                    try? await Task.sleep(for: .seconds(3))
                    reader.scrollTo(arguments[index + 1], anchor: .top)
                }
            }
            #endif
            }
        }
    }
}

// MARK: - 換日期

/// 左右箭頭切換日期，點中間打開紅綠燈月曆
struct DaySwitcher: View {
    @Binding var day: Date
    @State private var showCalendar = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        HStack(spacing: 8) {
            Button { day = day.adding(days: -1) } label: { PixelSprite(art: .arrowLeft, size: 14) }
                .buttonStyle(.pixel(.secondary))
                .accessibilityLabel("前一天")

            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Button { showCalendar = true } label: {
                    HStack(spacing: 6) {
                        PixelSprite(art: .calendar, size: 16)
                        Text(day.formatted(.dateTime.month().day().weekday(.wide)))
                            .font(.px(16))
                            .foregroundStyle(Color.ink)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.formatted(.dateTime.month().day().weekday(.wide)))，打開月曆")
                if isToday {
                    Text("今天").font(.px(12)).foregroundStyle(Color.soft)
                } else {
                    Button("回到今天") { day = Date.now.startOfDay }
                        .font(.px(12))
                        .foregroundStyle(Color.brand)
                }
            }
            Spacer(minLength: 0)

            Button { day = day.adding(days: 1) } label: { PixelSprite(art: .arrowRight, size: 14) }
                .buttonStyle(.pixel(.secondary))
                .disabled(isToday)
                .accessibilityLabel("後一天")
        }
        .padding(8)
        .pixelPanel(shadow: nil, lineWidth: 2)
        .sheet(isPresented: $showCalendar) { CalendarSheet(selected: $day) }
        // 左右滑也能換日期
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40, !isToday {
                    day = day.adding(days: 1)
                } else if value.translation.width > 40 {
                    day = day.adding(days: -1)
                }
            }
        )
    }
}

// MARK: - 某一天的內容

struct DayContent: View {
    let day: Date
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var router: AppRouter
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var exercises: [ExerciseEntry]
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @AppStorage(SettingKey.proteinGoal) private var proteinGoal = AppSettings.Defaults.proteinGoal
    @AppStorage(SettingKey.carbsGoal) private var carbsGoal = AppSettings.Defaults.carbsGoal
    @AppStorage(SettingKey.fatGoal) private var fatGoal = AppSettings.Defaults.fatGoal
    @AppStorage(SettingKey.sodiumGoal) private var sodiumGoal = AppSettings.Defaults.sodiumGoal
    @AppStorage(SettingKey.waterGoal) private var waterGoal = AppSettings.Defaults.waterGoal
    @AppStorage(SettingKey.stepGoal) private var stepGoal = AppSettings.Defaults.stepGoal
    @AppStorage(SettingKey.burnGoal) private var burnGoal = AppSettings.Defaults.burnGoal
    @AppStorage(SettingKey.cupSize) private var cupSize = AppSettings.Defaults.cupSize
    @AppStorage(SettingKey.addBackExercise) private var addBackExercise = true
    /// 讀這個值，讓「這餐沒吃」按下後畫面會更新
    @AppStorage(SettingKey.skippedMeals) private var skippedMeals = ""
    @State private var editingFood: FoodEntry?
    @State private var pastActive: Double = 0
    @State private var pastSteps: Double = 0

    init(day: Date) {
        self.day = day
        let start = day.startOfDay
        let end = start.adding(days: 1)
        _foods = Query(filter: #Predicate<FoodEntry> { $0.date >= start && $0.date < end }, sort: \FoodEntry.date)
        _waters = Query(filter: #Predicate<WaterEntry> { $0.date >= start && $0.date < end }, sort: \WaterEntry.date)
        _exercises = Query(filter: #Predicate<ExerciseEntry> { $0.date >= start && $0.date < end },
                           sort: \ExerciseEntry.date)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var waterTotal: Double { waters.sum(\.amount) }
    /// 燃燒 = Apple Watch 的活動熱量 + 手動記錄的運動
    private var burned: Double { (isToday ? health.activeCalories : pastActive) + exercises.sum(\.calories) }
    private var steps: Double { isToday ? health.steps : pastSteps }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatusWindow(
                eaten: foods.sum(\.calories), goal: calorieGoal, burned: burned, burnGoal: burnGoal,
                addBack: addBackExercise,
                water: waterTotal, waterGoal: waterGoal, steps: steps, stepGoal: stepGoal,
                protein: foods.sum(\.protein), proteinGoal: proteinGoal,
                carbs: foods.sum(\.carbs), carbsGoal: carbsGoal,
                fat: foods.sum(\.fat), fatGoal: fatGoal,
                sodium: foods.sum(\.sodium), sodiumGoal: sodiumGoal, sugar: foods.sum(\.sugar),
                experienceTrigger: foods.count + waters.count + exercises.count,
                showsMind: isToday
            )

            if isToday {
                AdventureWindow(refreshKey: foods.count + waters.count + exercises.count)
                if let festival = Festival.active() { FestivalWindow(festival: festival).id("festival") }
                HabitWindow(refreshKey: foods.count + waters.count + exercises.count)
                    .id("habits")
                PlateWindow(foods: foods)
                    .id("plate")
                CommandWindow(cupSize: cupSize)
                QuestWindow(nudges: NudgeEngine.nudges(foods: foods, waterTotal: waterTotal,
                                                       waterGoal: waterGoal, skippedMeals: skippedMeals))
            } else {
                PixelWindow(title: "補記") {
                    Text("忘了記錄？可以補記這一天。").font(.px(12)).foregroundStyle(Color.soft)
                    Button("補記這天的飲食") {
                        router.openAddFood(date: Date.at(minutes: AppSettings.mealTime(.lunch), on: day))
                    }
                    .buttonStyle(.pixel(.primary, fullWidth: true))
                }
            }

            WaterWindow(total: waterTotal, goal: waterGoal, cupSize: cupSize,
                        lastEntry: waters.last, canAdd: isToday)

            AdventureLog(day: day, foods: foods, exercises: exercises, skippedMeals: skippedMeals) {
                editingFood = $0
            }
        }
        .sheet(item: $editingFood) { EditFoodView(entry: $0) }
        .task {
            guard !isToday else { return }
            let next = day.startOfDay.adding(days: 1)
            pastActive = await health.dailyActiveCalories(from: day.startOfDay, to: next)[day.startOfDay] ?? 0
            pastSteps = await health.dailySteps(from: day.startOfDay, to: next)[day.startOfDay] ?? 0
        }
    }
}

// MARK: - 等級

/// 記錄越多經驗值越高：飲食 10、喝水 3、運動 15、體重 5
enum HeroLevel {
    struct Progress {
        let level: Int
        let experience: Int
        let inLevel: Int
        let needed: Int
        var title: String { HeroLevel.title(for: level) }
    }

    /// 第 n 級需要 30 × (n-1)² 經驗值
    private static func threshold(_ level: Int) -> Int { 30 * (level - 1) * (level - 1) }

    @MainActor
    static func current() -> Progress {
        let context = AppDatabase.context
        let foods = (try? context.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0
        let waters = (try? context.fetchCount(FetchDescriptor<WaterEntry>())) ?? 0
        let exercises = (try? context.fetchCount(FetchDescriptor<ExerciseEntry>())) ?? 0
        let weights = (try? context.fetchCount(FetchDescriptor<WeightEntry>())) ?? 0
        let experience = foods * 10 + waters * 3 + exercises * 15 + weights * 5
        var level = 1
        while threshold(level + 1) <= experience { level += 1 }
        return Progress(level: level, experience: experience,
                        inLevel: experience - threshold(level),
                        needed: threshold(level + 1) - threshold(level))
    }

    static func title(for level: Int) -> String {
        switch level {
        case ..<3: "見習冒險者"
        case 3..<5: "白飯騎士"
        case 5..<8: "青菜劍士"
        case 8..<12: "蛋白質法師"
        case 12..<17: "營養賢者"
        default: "傳說勇者"
        }
    }
}

// MARK: - 狀態

struct StatusWindow: View {
    let eaten: Double
    let goal: Double
    let burned: Double
    let burnGoal: Double
    let addBack: Bool
    let water: Double
    let waterGoal: Double
    let steps: Double
    let stepGoal: Double
    let protein: Double
    let proteinGoal: Double
    let carbs: Double
    let carbsGoal: Double
    let fat: Double
    let fatGoal: Double
    let sodium: Double
    let sodiumGoal: Double
    let sugar: Double
    /// 記錄數量改變時重新計算經驗值
    let experienceTrigger: Int
    /// 今天才顯示精神力（HRV）
    var showsMind = false
    @ObservedObject private var stress = StressStore.shared
    @State private var showStress = false
    @AppStorage(SettingKey.userName) private var userName = AppSettings.Defaults.userName
    @AppStorage(SettingKey.avatar) private var avatar = AppSettings.Defaults.avatar
    @State private var progress: HeroLevel.Progress?
    /// 自己選的稱號（沒選就用等級稱號）
    @AppStorage(HeroTitle.storageKey) private var heroTitle = ""
    @State private var showInfo = false

    var body: some View {
        let budget = goal + (addBack ? burned : 0)
        let remaining = budget - eaten

        PixelWindow(title: "狀態") {
            HStack(spacing: 12) {
                StickerView(stickerData: nil, emoji: avatar, size: 44)
                    .padding(6)
                    .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("LV.\(progress?.level ?? 1)").font(.px(20)).foregroundStyle(Color.brand)
                        Text(userName).font(.px(16)).lineLimit(1)
                    }
                    PixelBar(value: Double(progress?.inLevel ?? 0), total: Double(max(progress?.needed ?? 1, 1)),
                             color: .carbs, segments: 8, height: 6, overIsBad: false)
                    Text("\(HeroTitle(rawValue: heroTitle)?.title ?? progress?.title ?? "見習冒險者")　EXP \(progress?.inLevel ?? 0)/\(progress?.needed ?? 30)")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
            }

            VStack(spacing: 8) {
                statRow("熱量", value: eaten, total: budget, color: .calorie, overIsBad: true,
                        trailing: "\(eaten.rounded0)/\(budget.rounded0)")
                statRow("喝水", value: water, total: waterGoal, color: .water, overIsBad: false,
                        trailing: "\(water.rounded0)/\(waterGoal.rounded0)")
                statRow("步數", value: steps, total: stepGoal, color: .move, overIsBad: false,
                        trailing: steps.rounded0.formatted())
                // 超過建議量就滿格，數字繼續往上跑
                statRow("燃燒", value: burned, total: burnGoal, color: .protein, overIsBad: false,
                        trailing: "\(burned.rounded0)/\(burnGoal.rounded0)")
                if showsMind {
                    Button { showStress = true } label: {
                        if let reading = stress.reading {
                            statRow("精神", value: Double(reading.mp), total: 100, color: .fat, overIsBad: false,
                                    trailing: "\(reading.mp) \(reading.level.title)")
                        } else {
                            statRow("精神", value: 0, total: 100, color: .fat, overIsBad: false, trailing: "建立基準中")
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showStress) { StressDetailView() }
                }
            }
            .padding(.top, 4)

            HStack(spacing: 6) {
                Text(remaining >= 0 ? "還可以吃 \(remaining.rounded0) 大卡" : "超過 \((-remaining).rounded0) 大卡")
                    .font(.px(16))
                    .foregroundStyle(remaining >= 0 ? Color.ink : Color.danger)
                Button { showInfo = true } label: {
                    Text("?").font(.px(12)).foregroundStyle(Color.brand)
                        .frame(width: 20, height: 20)
                        .overlay(Rectangle().strokeBorder(Color.brand, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("怎麼算的")
                Spacer(minLength: 4)
                if burned >= burnGoal, burnGoal > 0 {
                    Text("運動達標！").font(.px(12)).foregroundStyle(Color.protein)
                }
            }

            PixelDivider()

            HStack(alignment: .top, spacing: 10) {
                macro("蛋白質", value: protein, goal: proteinGoal, color: .protein)
                macro("碳水", value: carbs, goal: carbsGoal, color: .carbs)
                macro("脂肪", value: fat, goal: fatGoal, color: .fat)
            }

            HStack {
                Text("鈉 \(sodium.rounded0)/\(sodiumGoal.rounded0) mg")
                    .foregroundStyle(sodium > sodiumGoal ? Color.danger : Color.soft)
                Spacer()
                Text("糖 \(sugar.rounded0) g").foregroundStyle(Color.soft)
            }
            .font(.px(12))
        }
        .task(id: experienceTrigger) { progress = HeroLevel.current() }
        .alert("剩餘熱量怎麼算？", isPresented: $showInfo) {
            Button("好") {}
        } message: {
            Text(addBack
                 ? "剩餘 = 每日目標 \(goal.rounded0) − 攝取 \(eaten.rounded0) + 運動燃燒 \(burned.rounded0)。\n可以在「角色 › 偏好設定」關掉「把運動消耗加回來」。"
                 : "剩餘 = 每日目標 \(goal.rounded0) − 攝取 \(eaten.rounded0)。")
        }
    }

    private func statRow(_ title: String, value: Double, total: Double, color: Color, overIsBad: Bool,
                         trailing: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.px(16)).frame(width: 36, alignment: .leading)
            PixelBar(value: value, total: total, color: color, overIsBad: overIsBad)
            Text(trailing)
                .font(.px(12))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 78, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func macro(_ title: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.px(12))
            PixelBar(value: value, total: goal, color: color, segments: 5, height: 8)
            Text("\(value.rounded0)/\(goal.rounded0) g")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 指令

struct CommandWindow: View {
    let cupSize: Double
    @EnvironmentObject private var router: AppRouter
    @State private var waterCount = 0
    @State private var showWaterToast = false

    var body: some View {
        PixelWindow(title: "指令") {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    command("吃東西", art: .bowl) { router.showEatMenu = true }
                    command("喝水 +\(cupSize.rounded0)", art: .drop) {
                        LogService.shared.logWater(cupSize)
                        waterCount += 1
                        withAnimation(.easeOut(duration: 0.15)) { showWaterToast = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation { showWaterToast = false }
                        }
                    }
                }
                GridRow {
                    command("運動", art: .dumbbell) { router.showExercise = true }
                    command("量體重", art: .scale) { router.showWeight = true }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showWaterToast {
                PixelTag(text: "喝了 \(cupSize.rounded0) ml！EXP +3", fill: .water, foreground: .onBrand, size: 12)
                    .offset(x: -8, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: waterCount)
    }

    private func command(_ title: String, art: PixelArt, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PixelSprite(art: art, size: 28)
                Text(title).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.pixel(.secondary, fullWidth: true))
    }
}

// MARK: - 任務（主動提示）

struct QuestWindow: View {
    let nudges: [Nudge]
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var health: HealthKitManager
    @AppStorage(SettingKey.cupSize) private var cupSize = AppSettings.Defaults.cupSize

    private var needsHealth: Bool { health.isAvailable && health.needsAuthorization }

    var body: some View {
        if !nudges.isEmpty || needsHealth {
            PixelWindow(title: "任務", tint: .calorie) {
                ForEach(Array(nudges.enumerated()), id: \.element.id) { index, nudge in
                    if index > 0 { PixelDivider() }
                    switch nudge.kind {
                    case .meal(let meal): mealQuest(meal)
                    case .water(let behind): waterQuest(behind)
                    }
                }
                if needsHealth {
                    if !nudges.isEmpty { PixelDivider() }
                    quest("連接 Apple 健康", detail: "自動帶入 Apple Watch 的步數與運動。") {
                        Button("連接") { Task { await health.requestAuthorization() } }
                            .buttonStyle(.pixel(.primary, fontSize: 12))
                    }
                }
            }
        }
    }

    private func quest<Buttons: View>(_ title: String, detail: String,
                                      @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("！").font(.px(16)).foregroundStyle(Color.calorie)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.px(16))
                    Text(detail).font(.px(12)).foregroundStyle(Color.soft)
                }
            }
            HStack(spacing: 8) { buttons() }
        }
    }

    private func mealQuest(_ meal: MealType) -> some View {
        let hasYesterday = LogService.shared.foods(on: Date.now.adding(days: -1)).contains { $0.mealType == meal }
        return quest("\(meal.title)還沒記錄", detail: "花 5 秒記下來，晚點就不用回想。") {
            Button("拍照") { router.openAddFood(meal: meal, start: .camera) }
                .buttonStyle(.pixel(.primary, fontSize: 12))
            if hasYesterday {
                Button("同昨天") { LogService.shared.repeatMeal(meal, from: Date.now.adding(days: -1)) }
                    .buttonStyle(.pixel(.secondary, fontSize: 12))
            }
            Button("沒吃") { LogService.shared.skipMeal(meal) }
                .buttonStyle(.pixel(.secondary, fontSize: 12))
        }
    }

    private func waterQuest(_ behind: Double) -> some View {
        quest("喝水進度落後", detail: "比預計少了約 \((behind / 50).rounded0 * 50) ml。") {
            Button("喝一杯") { LogService.shared.logWater(cupSize) }
                .buttonStyle(.pixel(.tinted(.water), fontSize: 12))
        }
    }
}

// MARK: - 水壺

struct WaterWindow: View {
    let total: Double
    let goal: Double
    let cupSize: Double
    let lastEntry: WaterEntry?
    let canAdd: Bool
    @State private var tapCount = 0

    var body: some View {
        let cups = max(1, min(10, Int((goal / cupSize).rounded(.up))))
        let filled = Int(total / cupSize)

        PixelWindow(title: "水壺", tint: .water) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(total.rounded0)").font(.px(20)).monospacedDigit()
                Text("/ \(goal.rounded0) ml").font(.px(12)).foregroundStyle(Color.soft)
                Spacer()
                Text("一杯 \(cupSize.rounded0) ml").font(.px(12)).foregroundStyle(Color.soft)
            }

            // 一格一杯：點下一個空杯喝一杯，點最後一個滿杯可以復原
            HStack(spacing: 4) {
                ForEach(0..<cups, id: \.self) { index in
                    let isNext = index == min(filled, cups)
                    let isLastFilled = index == min(filled, cups) - 1
                    Button {
                        if isNext {
                            LogService.shared.logWater(cupSize)
                            tapCount += 1
                        } else if isLastFilled, let lastEntry {
                            LogService.shared.delete(lastEntry)
                        }
                    } label: {
                        PixelSprite(art: index < filled ? .cupFull : .cupEmpty, size: 28)
                            .opacity(index < filled || (canAdd && isNext) ? 1 : 0.4)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd || !(isNext || isLastFilled))
                    .accessibilityLabel(index < filled ? "第 \(index + 1) 杯，已喝" : "第 \(index + 1) 杯")
                }
            }

            if total >= goal {
                Text("水分補滿了！身體 HP 回復中。").font(.px(12)).foregroundStyle(Color.water)
            } else if canAdd {
                Text("點空杯喝一杯，點最後一杯可以復原。").font(.px(12)).foregroundStyle(Color.soft)
            }
        }
        .sensoryFeedback(.increase, trigger: tapCount)
    }
}

// MARK: - 冒險日誌

extension MealType {
    var shortTitle: String {
        switch self {
        case .breakfast: "早"
        case .lunch: "午"
        case .snack: "點"
        case .dinner: "晚"
        case .lateNight: "宵"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: .carbs
        case .lunch: .calorie
        case .snack: .fat
        case .dinner: .brand
        case .lateNight: .sodium
        }
    }
}

/// 這一天的飲食（依早餐、午餐、點心、晚餐、宵夜分段）與運動
struct AdventureLog: View {
    let day: Date
    let foods: [FoodEntry]
    let exercises: [ExerciseEntry]
    let skippedMeals: String
    var onSelect: (FoodEntry) -> Void
    @EnvironmentObject private var router: AppRouter

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        PixelWindow(title: "冒險日誌", spacing: 0) {
            ForEach(Array(MealType.allCases.enumerated()), id: \.element.id) { index, meal in
                if index > 0 { PixelDivider().padding(.vertical, 4) }
                mealSection(meal)
            }

            PixelDivider().padding(.vertical, 4)
            exerciseSection

            PixelDivider()
            NavigationLink {
                ExerciseView()
            } label: {
                PixelMenuRow(title: "運動與步數紀錄", art: .dumbbell)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 一餐

    private func mealSection(_ meal: MealType) -> some View {
        let items = foods.filter { $0.mealType == meal }
        let skipped = skippedMeals.contains("\(day.dayKey)-\(meal.rawValue)")

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PixelChip(text: meal.shortTitle, color: meal.color)
                Text(meal.title).font(.px(16))
                if items.isEmpty {
                    Text(skipped ? "沒吃" : "還沒記錄").font(.px(12)).foregroundStyle(Color.soft)
                }
                Spacer(minLength: 6)
                if !items.isEmpty {
                    Text("\(items.sum(\.calories).rounded0) 大卡").font(.px(12)).monospacedDigit()
                }
                Button("＋") {
                    router.openAddFood(meal: meal,
                                       date: isToday ? nil : Date.at(minutes: AppSettings.mealTime(meal), on: day))
                }
                .buttonStyle(.pixel(.secondary, fontSize: 12))
                .accessibilityLabel("新增\(meal.title)")
            }
            .padding(.vertical, 4)

            ForEach(items) { entry in
                Button { onSelect(entry) } label: { foodRow(entry) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: 運動

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PixelChip(text: "動", color: .move)
                Text("運動").font(.px(16))
                if exercises.isEmpty {
                    Text("手動記錄的運動會在這裡").font(.px(12)).foregroundStyle(Color.soft)
                }
                Spacer(minLength: 6)
                if !exercises.isEmpty {
                    Text("-\(exercises.sum(\.calories).rounded0) 大卡").font(.px(12)).foregroundStyle(Color.move)
                }
                if isToday {
                    Button("＋") { router.showExercise = true }
                        .buttonStyle(.pixel(.secondary, fontSize: 12))
                        .accessibilityLabel("記錄運動")
                }
            }
            .padding(.vertical, 4)

            ForEach(exercises) { entry in
                exerciseRow(entry)
            }
        }
    }

    private func time(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
            .font(.px(12))
            .monospacedDigit()
            .foregroundStyle(Color.soft)
            .frame(width: 40, alignment: .leading)
    }

    private func foodRow(_ entry: FoodEntry) -> some View {
        HStack(spacing: 10) {
            time(entry.date)
            StickerView(entry: entry, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).lineLimit(1)
                HStack(spacing: 6) {
                    if entry.isHighProtein {
                        PixelChip(text: "高蛋白", color: .protein, filled: false)
                    }
                    if !entry.portion.isEmpty {
                        Text(entry.portion).font(.px(12)).foregroundStyle(Color.soft).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.calories.rounded0)").font(.px(16)).monospacedDigit()
                Text("大卡").font(.px(12)).foregroundStyle(Color.soft)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("點一下可以修改")
    }

    private func exerciseRow(_ entry: ExerciseEntry) -> some View {
        HStack(spacing: 10) {
            time(entry.date)
            PixelSprite(art: .dumbbell, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).lineLimit(1)
                Text("\(entry.minutes.rounded0) 分鐘").font(.px(12)).foregroundStyle(Color.soft)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("-\(entry.calories.rounded0)").font(.px(16)).monospacedDigit().foregroundStyle(Color.move)
                Text("大卡").font(.px(12)).foregroundStyle(Color.soft)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 主動提示

struct Nudge: Identifiable {
    enum Kind {
        case meal(MealType)
        case water(Double)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .meal(let meal): "meal-\(meal.rawValue)"
        case .water: "water"
        }
    }
}

/// 依時間與目前紀錄，判斷該提醒什麼
@MainActor
enum NudgeEngine {
    static func nudges(foods: [FoodEntry], waterTotal: Double, waterGoal: Double,
                       skippedMeals: String, now: Date = .now) -> [Nudge] {
        var result: [Nudge] = []
        let minutes = now.minutesSinceMidnight
        let logged = Set(foods.map(\.mealType))

        // 最近一餐過了 30 分鐘還沒記錄就提醒（只提醒一餐，5 小時內有效）
        for meal in [MealType.dinner, .lunch, .breakfast] {
            let time = AppSettings.mealTime(meal)
            guard minutes >= time + 30, minutes - time <= 300 else { continue }
            if !logged.contains(meal) && !skippedMeals.contains("\(now.dayKey)-\(meal.rawValue)") {
                result.append(Nudge(kind: .meal(meal)))
            }
            break
        }

        // 依起床到睡覺的時間比例，看喝水有沒有落後
        let wake = AppSettings.wakeTime
        let sleep = AppSettings.sleepTime
        if sleep > wake, minutes > wake {
            let expected = waterGoal * min(1, Double(minutes - wake) / Double(sleep - wake))
            let behind = expected - waterTotal
            if behind >= 300 { result.append(Nudge(kind: .water(behind))) }
        }
        return result
    }
}
