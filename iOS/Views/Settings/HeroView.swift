import SwiftUI
import UIKit
import UserNotifications

/// 表單的小標題與說明
private func pxHeader(_ text: String) -> some View {
    Text(text).font(.px(12)).foregroundStyle(Color.soft)
}

// MARK: - 角色

/// 角色：角色卡（頭像、等級、身體數值）＋ 選單
struct HeroView: View {
    @AppStorage(HeroTitle.storageKey) private var heroTitle = ""
    @EnvironmentObject private var router: AppRouter
    @AppStorage(SettingKey.userName) private var userName = AppSettings.Defaults.userName
    @AppStorage(SettingKey.avatar) private var avatar = AppSettings.Defaults.avatar
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @AppStorage(SettingKey.targetWeightKG) private var targetWeightKG = AppSettings.Defaults.targetWeightKG
    @AppStorage(SettingKey.heightCM) private var heightCM = AppSettings.Defaults.heightCM
    @AppStorage(SettingKey.age) private var age = AppSettings.Defaults.age
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @AppStorage(PixelPalette.storageKey) private var palette = PixelPalette.milkTea.rawValue
    @AppStorage(SettingKey.companionName) private var companionName = "小卡"
    @AppStorage(SettingKey.companionStyle) private var companionStyle = CompanionStyle.motivating.rawValue
    @State private var progress: HeroLevel.Progress?
    @State private var showNameEditor = false

    private var bmi: Double {
        let meters = heightCM / 100
        return meters > 0 ? weightKG / (meters * meters) : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "角色", subtitle: "HERO")

                    PixelWindow(title: "角色卡") {
                        HStack(spacing: 14) {
                            Button { showNameEditor = true } label: {
                                StickerView(stickerData: nil, emoji: avatar, size: 64)
                                    .padding(8)
                                    .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("更換頭像")

                            VStack(alignment: .leading, spacing: 5) {
                                Text(userName).font(.px(20)).lineLimit(1)
                                Text("LV.\(progress?.level ?? 1) \(progress?.title ?? "見習冒險者")")
                                    .font(.px(12))
                                    .foregroundStyle(Color.brand)
                                PixelBar(value: Double(progress?.inLevel ?? 0),
                                         total: Double(max(progress?.needed ?? 1, 1)),
                                         color: .carbs, segments: 8, height: 6, overIsBad: false)
                                Text("EXP \(progress?.inLevel ?? 0)/\(progress?.needed ?? 30)　累計 \(progress?.experience ?? 0)")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                        }

                        PixelDivider()

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                stat("身高", "\(heightCM.rounded0) cm")
                                stat("年齡", "\(age) 歲")
                            }
                            GridRow {
                                stat("體重", "\(weightKG.formatted(.number.precision(.fractionLength(1)))) kg")
                                stat("目標", "\(targetWeightKG.formatted(.number.precision(.fractionLength(1)))) kg")
                            }
                            GridRow {
                                stat("BMI", bmi.formatted(.number.precision(.fractionLength(1))))
                                stat("每日", "\(calorieGoal.rounded0) 大卡")
                            }
                        }

                        HStack(spacing: 10) {
                            Button("改名字與頭像") { showNameEditor = true }
                                .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                            Button("量體重") { router.showWeight = true }
                                .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
                        }
                    }

                    PixelWindow(title: "選單", spacing: 0) {
                        menu("個人資料", detail: "身高、體重、目標", art: .hero) { ProfileDataView() }
                        PixelDivider()
                        menu("稱號", detail: HeroTitle(rawValue: heroTitle)?.title ?? "依等級", art: .trophy) { TitleView() }
                        PixelDivider()
                        menu("每日目標", detail: "\(calorieGoal.rounded0) 大卡", art: .scale) { PlanView() }
                        PixelDivider()
                        menu("偏好設定", detail: (PixelPalette(rawValue: palette) ?? .milkTea).title, art: .controller) {
                            PreferencesView()
                        }
                        PixelDivider()
                        menu("App 圖示", detail: AppIconChoice.current.title, art: .companion) { AppIconView() }
                        PixelDivider()
                        menu("AI 小夥伴", detail: "\(companionName)・\((CompanionStyle(rawValue: companionStyle) ?? .motivating).title)",
                             art: .companion) { CompanionSettingsView() }
                        PixelDivider()
                        menu("提醒", detail: nil, art: .bell) { RemindersView() }
                        PixelDivider()
                        menu("AI 拍照辨識", detail: FoodAnalyzer.provider.shortName, art: .camera) { AISettingsView() }
                        PixelDivider()
                        menu("健康計算機", detail: "BMI、TDEE", art: .label) { CalculatorsView() }
                        PixelDivider()
                        menu("權限與同步", detail: "通知、Apple 健康", art: .heart) { PermissionsView() }
                        PixelDivider()
                        menu("資料備份", detail: (UserDefaults.standard.object(forKey: BackupService.lastBackupKey) as? Date)
                            .map { $0.formatted(.dateTime.month().day()) } ?? "還沒備份", art: .chest) { BackupView() }
                        PixelDivider()
                        menu("關於", detail: nil, art: .book) { AboutView() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNameEditor) { NameEditorSheet() }
            .task(id: router.selectedTab) { progress = HeroLevel.current() }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.px(12)).foregroundStyle(Color.soft).frame(width: 32, alignment: .leading)
            Text(value).font(.px(16)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menu<Destination: View>(_ title: String, detail: String?, art: PixelArt,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            PixelMenuRow(title: title, detail: detail, art: art)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 個人資料

struct ProfileDataView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @AppStorage(SettingKey.targetWeightKG) private var targetWeightKG = AppSettings.Defaults.targetWeightKG
    @AppStorage(SettingKey.heightCM) private var heightCM = AppSettings.Defaults.heightCM
    @AppStorage(SettingKey.sex) private var sex = AppSettings.Defaults.sex
    @AppStorage(SettingKey.age) private var age = AppSettings.Defaults.age
    @AppStorage(SettingKey.activityLevel) private var activityLevel = AppSettings.Defaults.activityLevel
    @AppStorage(SettingKey.autoGoals) private var autoGoals = true
    @State private var showResetConfirm = false

    /// 個人資料的組合，任一項改變就依「自動計算卡路里」重新算目標
    private var profileSignature: String {
        "\(weightKG)-\(targetWeightKG)-\(heightCM)-\(sex)-\(age)-\(activityLevel)-\(autoGoals)"
    }

    var body: some View {
        Form {
            Group {
                Section {
                    Button { router.showWeight = true } label: {
                        LabeledContent("更新體重", value: "\(weightKG.formatted(.number.precision(.fractionLength(1)))) kg")
                            .foregroundStyle(Color.ink)
                    }
                    NavigationLink {
                        NumberEditView(title: "目標體重", value: $targetWeightKG, unit: "kg", range: 30...200, step: 0.5,
                                       footer: "比目前體重輕就是減脂、重就是增肌，自動計算時會用來決定每天吃多少。")
                    } label: {
                        LabeledContent("目標體重", value: "\(targetWeightKG.formatted(.number.precision(.fractionLength(1)))) kg")
                    }
                    NavigationLink {
                        NumberEditView(title: "身高", value: $heightCM, unit: "cm", range: 120...220, step: 1, footer: nil)
                    } label: {
                        LabeledContent("身高", value: "\(heightCM.rounded0) cm")
                    }
                    Picker("性別", selection: $sex) {
                        ForEach(GoalCalculator.Sex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("年齡", selection: $age) {
                        ForEach(12...100, id: \.self) { Text("\($0) 歲").tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("運動習慣", selection: $activityLevel) {
                        ForEach(GoalCalculator.activityTitles.indices, id: \.self) { index in
                            Text(GoalCalculator.activityTitles[index]).tag(index)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    pxHeader("「自動計算卡路里」開啟時，改這些資料會自動更新每日熱量與三大營養素。")
                }

                Section {
                    Button("依目前資料重新計算目標") { showResetConfirm = true }
                }
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("個人資料")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("依目前的個人資料重新計算每日目標？", isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("重新計算") {
                AppSettings.applyGoals(AppSettings.currentProfileGoals())
                PhoneConnectivity.shared.pushSummary()
            }
        } message: {
            Text("熱量、三大營養素和喝水目標都會換成建議值。")
        }
        .onChange(of: profileSignature) {
            AppSettings.applyAutoGoalsIfNeeded()
            PhoneConnectivity.shared.pushSummary()
        }
    }
}

// MARK: - 偏好設定

struct PreferencesView: View {
    @AppStorage(SettingKey.autoGoals) private var autoGoals = true
    @AppStorage(SettingKey.addBackExercise) private var addBackExercise = true
    @AppStorage(SettingKey.firstWeekday) private var firstWeekday = AppSettings.Defaults.firstWeekday
    @AppStorage(SettingKey.cupSize) private var cupSize = AppSettings.Defaults.cupSize
    @AppStorage(SettingKey.waterGoal) private var waterGoal = AppSettings.Defaults.waterGoal
    @AppStorage(SettingKey.themeMode) private var themeMode = AppSettings.Defaults.themeMode
    @AppStorage(PixelPalette.storageKey) private var palette = PixelPalette.milkTea.rawValue

    var body: some View {
        Form {
            Group {
                Section {
                    ForEach(PixelPalette.allCases) { item in
                        Button { palette = item.rawValue } label: {
                            HStack(spacing: 10) {
                                HStack(spacing: 0) {
                                    ForEach([item.light.paper, item.light.brand, item.light.calorie, item.light.water],
                                            id: \.self) { hex in
                                        Rectangle().fill(Color(hex: hex)).frame(width: 12, height: 20)
                                    }
                                }
                                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                                Text(item.title).foregroundStyle(Color.ink)
                                Spacer()
                                if palette == item.rawValue { Text("使用中").font(.px(12)).foregroundStyle(Color.brand) }
                            }
                        }
                    }
                    Picker("深淺色", selection: $themeMode) {
                        Text("跟隨系統").tag("system")
                        Text("淺色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .disabled(PixelPalette(rawValue: palette)?.forcesDark == true)
                } header: {
                    pxHeader("配色")
                } footer: {
                    pxHeader("「夜間街機」只有深色版。")
                }

                Section {
                    Toggle("自動計算卡路里", isOn: $autoGoals)
                    Toggle("把運動消耗加回可吃熱量", isOn: $addBackExercise)
                    Picker("每週的第一天", selection: $firstWeekday) {
                        Text("週一").tag(2)
                        Text("週日").tag(1)
                    }
                } header: {
                    pxHeader("熱量")
                }

                Section {
                    Picker("水杯容量", selection: $cupSize) {
                        ForEach([150.0, 200, 250, 300, 350, 500], id: \.self) { size in
                            Text("\(size.rounded0) ml").tag(size)
                        }
                    }
                    Stepper(value: $waterGoal, in: 1000...5000, step: 100) {
                        LabeledContent("每日飲水目標", value: "\(waterGoal.rounded0) ml")
                    }
                } header: {
                    pxHeader("喝水")
                }
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("偏好設定")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: waterGoal) { NotificationManager.shared.scheduleRefresh() }
    }
}

// MARK: - 權限與同步

struct PermissionsView: View {
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isSyncing = false

    var body: some View {
        Form {
            Group {
                Section {
                    Button {
                        Task {
                            if notificationStatus == .notDetermined {
                                _ = await NotificationManager.shared.requestAuthorization()
                            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                            notificationStatus = await NotificationManager.shared.authorizationStatus()
                        }
                    } label: {
                        LabeledContent("通知提醒", value: notificationText)
                            .foregroundStyle(Color.ink)
                    }
                }

                if health.isAvailable {
                    Section {
                        Button {
                            Task { await health.requestAuthorization() }
                        } label: {
                            LabeledContent("Apple 健康", value: health.needsAuthorization ? "點這裡連接" : "已連接")
                                .foregroundStyle(Color.ink)
                        }

                        Button {
                            Task {
                                isSyncing = true
                                await health.refreshToday()
                                await LogService.shared.syncPendingToHealth()
                                isSyncing = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("同步 Apple 健康").foregroundStyle(Color.ink)
                                    Text(health.lastSync.map { "上次同步：\($0.formatted(date: .numeric, time: .shortened))" } ?? "尚未同步")
                                        .font(.px(12))
                                        .foregroundStyle(Color.soft)
                                }
                                Spacer()
                                if isSyncing { PixelLoadingDots() }
                            }
                        }
                        .disabled(isSyncing || health.needsAuthorization)
                    } footer: {
                        pxHeader("讀取 Apple Watch 的步數、活動熱量與體重；飲食、喝水、體重會寫回「健康」App。")
                    }
                }
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("權限與同步")
        .navigationBarTitleDisplayMode(.inline)
        .task { notificationStatus = await NotificationManager.shared.authorizationStatus() }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "已開啟"
        case .denied: "已關閉，點這裡到設定開啟"
        default: "點這裡開啟"
        }
    }
}

// MARK: - 關於

struct AboutView: View {
    @AppStorage(SettingKey.hasOnboarded) private var hasOnboarded = true

    var body: some View {
        Form {
            Group {
                Section {
                    LabeledContent("名稱", value: AppBrand.name)
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Button("重新看一次新手導覽") { hasOnboarded = false }
                }
                Section {
                    Text("營養資料：衛生福利部食品藥物管理署「食品營養成分資料集」（政府資料開放授權條款第 1 版）。")
                    Text("條碼資料：Open Food Facts 貢獻者（ODbL 開放資料庫授權），內建台灣商品並可線上查詢。")
                    Text("品牌與常見食品：各品牌官網公開的營養標示、臺北市與新北市食材登錄平台業者登錄的資料，以及營養師與網站整理的熱量表；只存在這支 iPhone，僅供個人參考。")
                    Text("每日目標參考：衛生福利部國民健康署「國人膳食營養素參考攝取量」第八版。")
                    Text("像素字體：俐方體 11 號 Cubic 11（SIL Open Font License 1.1）。")
                } header: {
                    pxHeader("資料來源與授權")
                } footer: {
                    pxHeader("熱量與營養素皆為估算值，僅供參考，不能取代醫師或營養師的專業建議。")
                }
                .font(.px(12))
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("關於")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 名字與頭像

struct NameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.userName) private var userName = AppSettings.Defaults.userName
    @AppStorage(SettingKey.avatar) private var avatar = AppSettings.Defaults.avatar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelWindow(title: "名字") {
                        HStack(spacing: 12) {
                            StickerView(stickerData: nil, emoji: avatar, size: 48)
                                .padding(6)
                                .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                            TextField("你的名字", text: $userName)
                                .pixelField()
                        }
                    }
                    ForEach(AvatarEmoji.groups) { group in
                        PixelWindow(title: group.title) {
                            EmojiGrid(emojis: group.emojis, selected: avatar) { avatar = $0 }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("改名字與頭像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }
}

/// 編輯一個數字（目標體重、身高）
struct NumberEditView: View {
    let title: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let footer: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(.px(32))
                    Text(unit).font(.px(20)).foregroundStyle(Color.soft)
                }
                Stepper("微調", value: $value, in: range, step: step)
            } footer: {
                if let footer { pxHeader(footer) }
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 每日目標

/// 每日目標：1. 選目標 → 2. 選飲食方式 → 3. 自動算出熱量與三大營養素
struct PlanView: View {
    @AppStorage(SettingKey.autoGoals) private var autoGoals = true
    @AppStorage(SettingKey.asianAdjust) private var asianAdjust = true
    @AppStorage(SettingKey.useDRIEnergy) private var useDRIEnergy = false
    @AppStorage(SettingKey.goalMode) private var goalMode = AppSettings.Defaults.goalMode
    @AppStorage(SettingKey.macroStyle) private var macroStyle = AppSettings.Defaults.macroStyle
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @AppStorage(SettingKey.proteinGoal) private var proteinGoal = AppSettings.Defaults.proteinGoal
    @AppStorage(SettingKey.carbsGoal) private var carbsGoal = AppSettings.Defaults.carbsGoal
    @AppStorage(SettingKey.fatGoal) private var fatGoal = AppSettings.Defaults.fatGoal
    @AppStorage(SettingKey.sodiumGoal) private var sodiumGoal = AppSettings.Defaults.sodiumGoal
    @AppStorage(SettingKey.waterGoal) private var waterGoal = AppSettings.Defaults.waterGoal
    @AppStorage(SettingKey.stepGoal) private var stepGoal = AppSettings.Defaults.stepGoal
    @AppStorage(SettingKey.burnGoal) private var burnGoal = AppSettings.Defaults.burnGoal
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @AppStorage(SettingKey.targetWeightKG) private var targetWeightKG = AppSettings.Defaults.targetWeightKG
    @AppStorage(SettingKey.heightCM) private var heightCM = AppSettings.Defaults.heightCM
    @AppStorage(SettingKey.sex) private var sex = AppSettings.Defaults.sex
    @AppStorage(SettingKey.age) private var age = AppSettings.Defaults.age
    @AppStorage(SettingKey.activityLevel) private var activityLevel = AppSettings.Defaults.activityLevel
    @State private var appliedCount = 0

    /// 任一項改變就重新計算（開啟自動時直接套用）
    private var planSignature: String { "\(goalMode)-\(macroStyle)-\(asianAdjust)-\(useDRIEnergy)-\(autoGoals)" }

    var body: some View {
        let result = AppSettings.currentProfileGoals()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                goalWindow
                styleWindow
                resultWindow(result)
                if !autoGoals { manualWindow }
                otherWindow
            }
            .padding(16)
        }
        .background(Color.paper)
        .navigationTitle("每日目標")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: appliedCount)
        .onChange(of: planSignature) {
            AppSettings.applyAutoGoalsIfNeeded()
            PhoneConnectivity.shared.pushSummary()
        }
        .onChange(of: calorieGoal + proteinGoal + stepGoal + waterGoal) { PhoneConnectivity.shared.pushSummary() }
    }

    // MARK: 1. 目標

    private var goalWindow: some View {
        PixelWindow(title: "1. 選目標") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                option(selected: goalMode == "auto", title: "自動",
                       detail: "依目標體重（\(weightKG.formatted()) → \(targetWeightKG.formatted()) kg）判斷：\(AppSettings.derivedGoal.title)") {
                    goalMode = "auto"
                }
                ForEach(GoalCalculator.Goal.allCases) { goal in
                    option(selected: goalMode == goal.rawValue, title: goal.title, detail: goal.detail) {
                        goalMode = goal.rawValue
                    }
                }
            }
        }
    }

    private func option(selected: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.px(16))
                Text(detail).font(.px(12)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? Color.onBrand : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(10)
            .background { PixelPanel(fill: selected ? .brand : .window, shadow: selected ? nil : .pxShadow, lineWidth: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 2. 飲食方式

    private var styleWindow: some View {
        PixelWindow(title: "2. 選飲食方式", spacing: 0) {
            ForEach(Array(GoalCalculator.MacroStyle.allCases.enumerated()), id: \.element.id) { index, style in
                if index > 0 { PixelDivider() }
                let selected = macroStyle == style.rawValue
                let ratio = ratios(for: style)
                Button { macroStyle = style.rawValue } label: {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(selected ? Color.brand : Color.window)
                            .frame(width: 14, height: 14)
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(style.title)
                            Text(style.detail).font(.px(12)).foregroundStyle(Color.soft)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 4) {
                            RatioBar(protein: ratio.protein, carbs: ratio.carbs, fat: ratio.fat)
                            Text("\(percent(ratio.protein))/\(percent(ratio.carbs))/\(percent(ratio.fat))")
                                .font(.px(12))
                                .monospacedDigit()
                                .foregroundStyle(Color.soft)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Text("右邊是 蛋白質／碳水／脂肪 佔熱量的比例。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .padding(.top, 8)
        }
    }

    private func ratios(for style: GoalCalculator.MacroStyle) -> (protein: Double, carbs: Double, fat: Double) {
        if let split = style.split { return split }
        let result = GoalCalculator.calculate(
            sex: GoalCalculator.Sex(rawValue: sex) ?? .female, age: age, heightCM: heightCM, weightKG: weightKG,
            activityLevel: activityLevel, goal: AppSettings.effectiveGoal, asianAdjust: asianAdjust, macroStyle: style,
            useDRIEnergy: useDRIEnergy)
        let total = max(result.protein * 4 + result.carbs * 4 + result.fat * 9, 1)
        return (result.protein * 4 / total, result.carbs * 4 / total, result.fat * 9 / total)
    }

    private func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }

    // MARK: 3. 結果

    private func resultWindow(_ result: GoalCalculator.Result) -> some View {
        let goal = AppSettings.effectiveGoal
        let style = AppSettings.macroStyle
        return PixelWindow(title: "3. 計算結果") {
            Text("\((GoalCalculator.Sex(rawValue: sex) ?? .female).title)・\(age) 歲・\(heightCM.rounded0) cm・\(weightKG.formatted()) kg・\(GoalCalculator.activityTitles[min(max(activityLevel, 0), 3)])")
                .font(.px(12))
                .foregroundStyle(Color.soft)

            HStack(spacing: 16) {
                small(useDRIEnergy ? "國健署建議" : "基礎代謝", useDRIEnergy ? "\(result.tdee.rounded0)" : "\(result.bmr.rounded0)")
                if !useDRIEnergy { small("每日消耗", "\(result.tdee.rounded0)") }
                small("目標", "\(goal.title)・\(style.title)")
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("每天吃").font(.px(12)).foregroundStyle(Color.soft)
                Text("\(result.calories.rounded0)").font(.px(32)).foregroundStyle(Color.calorie).monospacedDigit()
                Text("大卡").font(.px(12)).foregroundStyle(Color.soft)
            }

            HStack(alignment: .top, spacing: 10) {
                macro("蛋白質", result.protein, color: .protein)
                macro("碳水", result.carbs, color: .carbs)
                macro("脂肪", result.fat, color: .fat)
            }

            driReference(result)

            PixelDivider()

            Toggle("自動計算並套用", isOn: $autoGoals)
            Toggle("熱量用國健署標準（依年齡、性別、活動量查表）", isOn: $useDRIEnergy)
            if !useDRIEnergy {
                Toggle("亞洲人代謝校正（× 0.95）", isOn: $asianAdjust)
            }

            if autoGoals {
                Text("已套用。改個人資料、目標或飲食方式，每日目標都會跟著更新。")
                    .font(.px(12))
                    .foregroundStyle(Color.move)
            } else {
                Text("目前設定：\(calorieGoal.rounded0) 大卡，蛋白質 \(proteinGoal.rounded0) g、碳水 \(carbsGoal.rounded0) g、脂肪 \(fatGoal.rounded0) g")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                Button("套用這個結果") {
                    AppSettings.applyGoals(result, includeWater: false)
                    PhoneConnectivity.shared.pushSummary()
                    appliedCount += 1
                }
                .buttonStyle(.pixel(.primary, fullWidth: true))
            }
        }
    }

    /// 國健署「國人膳食營養素參考攝取量」第八版的參考值
    private func driReference(_ result: GoalCalculator.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("國健署參考（第八版 DRIs）").font(.px(12)).foregroundStyle(Color.brand)
            if let energy = result.driEnergy, let activity = result.driActivity {
                Text("熱量 \(energy.rounded0) 大卡（活動強度「\(activity)」）")
            }
            Text("醣類至少 \(TaiwanDRI.carbsMinimum.rounded0) g、佔熱量 50–65%；脂肪佔 20–30%")
            Text("鈉每天不超過 \(TaiwanDRI.sodiumLimit.rounded0) mg" + (result.fiber.map { "；膳食纖維 \($0.rounded0) g" } ?? ""))
        }
        .font(.px(12))
        .foregroundStyle(Color.soft)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func small(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
            Text(value).font(.px(16)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macro(_ title: String, _ grams: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.px(12)).foregroundStyle(Color.soft)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(grams.rounded0)").font(.px(20)).foregroundStyle(color).monospacedDigit()
                Text("g").font(.px(12)).foregroundStyle(Color.soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 手動微調

    private var manualWindow: some View {
        PixelWindow(title: "手動微調") {
            PixelStepperRow(title: "熱量", value: $calorieGoal, range: 1000...5000, step: 50, unit: "大卡")
            PixelStepperRow(title: "蛋白質", value: $proteinGoal, range: 20...300, step: 5, unit: "g")
            PixelStepperRow(title: "碳水", value: $carbsGoal, range: 20...600, step: 5, unit: "g")
            PixelStepperRow(title: "脂肪", value: $fatGoal, range: 10...200, step: 5, unit: "g")
            Text("關掉「自動計算並套用」時才能自己調。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
    }

    // MARK: 其他目標

    private var otherWindow: some View {
        let suggestedBurn = Double((weightKG * 5 / 50).rounded0 * 50)
        return PixelWindow(title: "其他目標") {
            PixelStepperRow(title: "鈉（上限）", value: $sodiumGoal, range: 1000...5000, step: 100, unit: "mg")
            PixelStepperRow(title: "喝水", value: $waterGoal, range: 1000...5000, step: 100, unit: "ml")
            PixelStepperRow(title: "步數", value: $stepGoal, range: 1000...30000, step: 500, unit: "步")
            PixelStepperRow(title: "運動消耗", value: $burnGoal, range: 50...1500, step: 50, unit: "大卡")
            if burnGoal != suggestedBurn {
                Button("運動消耗改成建議值（體重 × 5）：\(suggestedBurn.rounded0) 大卡") { burnGoal = suggestedBurn }
                    .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
            }
            Text("運動消耗 = Apple Watch 的活動熱量＋手動記錄的運動，大約是快走一小時的量；超過目標在首頁會滿格。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
    }
}

/// 三大營養素比例的小色條
struct RatioBar: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    var width: CGFloat = 84

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.protein).frame(width: width * protein)
            Rectangle().fill(Color.carbs).frame(width: width * carbs)
            Rectangle().fill(Color.fat).frame(width: width * fat)
        }
        .frame(width: width, height: 10, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

/// 「熱量 1850 大卡 [－][＋]」
struct PixelStepperRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(value.rounded0.formatted()) \(unit)").monospacedDigit().lineLimit(1)
            Button("－") { value = max(range.lowerBound, value - step) }
                .buttonStyle(.pixel(.secondary, fontSize: 12))
                .disabled(value <= range.lowerBound)
            Button("＋") { value = min(range.upperBound, value + step) }
                .buttonStyle(.pixel(.secondary, fontSize: 12))
                .disabled(value >= range.upperBound)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value.rounded0) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

// MARK: - 提醒

struct RemindersView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingKey.mealReminders) private var mealReminders = true
    @AppStorage(SettingKey.breakfastTime) private var breakfastTime = AppSettings.Defaults.breakfastTime
    @AppStorage(SettingKey.lunchTime) private var lunchTime = AppSettings.Defaults.lunchTime
    @AppStorage(SettingKey.dinnerTime) private var dinnerTime = AppSettings.Defaults.dinnerTime
    @AppStorage(SettingKey.waterReminders) private var waterReminders = true
    @AppStorage(SettingKey.waterInterval) private var waterInterval = AppSettings.Defaults.waterInterval
    @AppStorage(SettingKey.wakeTime) private var wakeTime = AppSettings.Defaults.wakeTime
    @AppStorage(SettingKey.sleepTime) private var sleepTime = AppSettings.Defaults.sleepTime
    @AppStorage(SettingKey.eveningReview) private var eveningReview = true
    @AppStorage(SettingKey.eveningTime) private var eveningTime = AppSettings.Defaults.eveningTime
    @AppStorage(SettingKey.sedentaryReminders) private var sedentaryReminders = false
    @AppStorage(SettingKey.workStart) private var workStart = AppSettings.Defaults.workStart
    @AppStorage(SettingKey.workEnd) private var workEnd = AppSettings.Defaults.workEnd
    @AppStorage(SettingKey.sedentaryWeekdaysOnly) private var weekdaysOnly = true
    @AppStorage(SettingKey.windDownReminder) private var windDownReminder = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// 任一項改變就重新排程
    private var signature: String {
        [mealReminders, waterReminders, eveningReview, sedentaryReminders, weekdaysOnly, windDownReminder].map { $0 ? "1" : "0" }.joined()
            + "\(breakfastTime)-\(lunchTime)-\(dinnerTime)-\(waterInterval)-\(wakeTime)-\(sleepTime)-\(eveningTime)"
            + "-\(workStart)-\(workEnd)"
    }

    var body: some View {
        Form {
            Group {
                if notificationStatus != .authorized && notificationStatus != .provisional {
                    Section {
                        Button {
                            Task {
                                if notificationStatus == .notDetermined {
                                    _ = await NotificationManager.shared.requestAuthorization()
                                } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    openURL(url)
                                }
                                notificationStatus = await NotificationManager.shared.authorizationStatus()
                            }
                        } label: {
                            Text(notificationStatus == .denied ? "通知已關閉，點這裡到設定開啟" : "開啟通知，讓我記得提醒你")
                        }
                    }
                }

                Section {
                    Toggle("三餐提醒", isOn: $mealReminders)
                    if mealReminders {
                        DatePicker("早餐", selection: $breakfastTime.timeOfDay, displayedComponents: .hourAndMinute)
                        DatePicker("午餐", selection: $lunchTime.timeOfDay, displayedComponents: .hourAndMinute)
                        DatePicker("晚餐", selection: $dinnerTime.timeOfDay, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    pxHeader("已記錄或標記「沒吃」的餐不會再提醒。")
                }

                Section {
                    Toggle("喝水提醒", isOn: $waterReminders)
                    if waterReminders {
                        Picker("提醒間隔", selection: $waterInterval) {
                            Text("每 1 小時").tag(60)
                            Text("每 1.5 小時").tag(90)
                            Text("每 2 小時").tag(120)
                            Text("每 3 小時").tag(180)
                        }
                        DatePicker("起床時間", selection: $wakeTime.timeOfDay, displayedComponents: .hourAndMinute)
                        DatePicker("睡覺時間", selection: $sleepTime.timeOfDay, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    pxHeader("剛喝過水會跳過下一次提醒，喝到目標就停止。手機上鎖時通知會出現在 Apple Watch，可以直接按「喝了 250 ml」。")
                }

                Section {
                    Toggle("睡前營火", isOn: $eveningReview)
                    if eveningReview {
                        DatePicker("時間", selection: $eveningTime.timeOfDay, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    pxHeader("睡前升起營火：收下今天的元氣幣、設定明天的小目標，也提醒還漏了哪一餐、還差多少水。")
                }

                Section {
                    Toggle("睡前放鬆", isOn: $windDownReminder)
                    if windDownReminder {
                        DatePicker("睡覺時間", selection: $sleepTime.timeOfDay, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    pxHeader("在睡覺時間前 30 分鐘提醒放下手機、調暗燈光。")
                }

                Section {
                    Toggle("久坐提醒", isOn: $sedentaryReminders)
                    if sedentaryReminders {
                        DatePicker("上班時間", selection: $workStart.timeOfDay, displayedComponents: .hourAndMinute)
                        DatePicker("下班時間", selection: $workEnd.timeOfDay, displayedComponents: .hourAndMinute)
                        Toggle("只有平日提醒", isOn: $weekdaysOnly)
                    }
                } footer: {
                    pxHeader("上班時間每個整點提醒起來動 5 分鐘。最近一小時已經走了 250 步以上，下一次就不吵你。")
                }
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: signature) {
            NotificationManager.shared.scheduleRefresh()
            SedentaryMonitor.startObservingIfNeeded()
        }
        .task { notificationStatus = await NotificationManager.shared.authorizationStatus() }
    }
}

// MARK: - AI

struct AISettingsView: View {
    @AppStorage(SettingKey.aiProvider) private var aiProvider = AppSettings.Defaults.aiProvider
    @AppStorage(SettingKey.geminiModel) private var geminiModel = AppSettings.Defaults.geminiModel
    @AppStorage(SettingKey.claudeModel) private var claudeModel = AppSettings.Defaults.claudeModel
    @State private var apiKeyInput = ""
    /// 已經存了金鑰的 AI 服務
    @State private var savedKeys: Set<String> = []

    var body: some View {
        let provider = AIProvider(rawValue: aiProvider) ?? .apple
        // Apple AI 不用金鑰，這裡設定的是它的備援 Gemini
        let keyProvider = provider == .apple ? AIProvider.gemini : provider
        let trimmedInput = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        Form {
            Group {
                Section {
                    Picker("使用", selection: $aiProvider) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    if provider == .apple {
                        LabeledContent("這支 iPhone", value: OnDeviceFoodAnalyzer.statusText)
                    }
                } footer: {
                    switch provider {
                    case .apple:
                        pxHeader("用 iPhone 內建的 Apple Intelligence 在手機上辨識：免費、不用網路、照片不會離開手機，營養數值會盡量對照台灣食品營養資料庫。Apple AI 不能用或辨識失敗時，會自動改用 Gemini（需要金鑰）；辨識完也可以按「用 Gemini 再算一次」。")
                    case .gemini:
                        pxHeader("Gemini 有免費額度，但每分鐘、每天有次數限制。注意：免費方案送出的照片與文字，Google 可能用來改進產品；介意的話可以在 AI Studio 開啟付費方案。")
                    case .claude:
                        pxHeader("Claude 依用量計費，可在 Console 設定每月花費上限。")
                    }
                }

                Section {
                    if savedKeys.contains(keyProvider.rawValue) {
                        Text("已設定 \(keyProvider.shortName) 金鑰").foregroundStyle(Color.move)
                        Button("移除金鑰", role: .destructive) {
                            Keychain.set("", for: keyProvider.keychainKey)
                            savedKeys.remove(keyProvider.rawValue)
                        }
                    } else if keyProvider.builtInKey != nil {
                        Text("使用程式內建的 \(keyProvider.shortName) 金鑰").foregroundStyle(Color.move)
                    } else {
                        SecureField(provider == .apple ? "Gemini 備援金鑰（選填）" : keyProvider.keyPlaceholder,
                                    text: $apiKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("儲存金鑰") {
                            Keychain.set(trimmedInput, for: keyProvider.keychainKey)
                            savedKeys.insert(keyProvider.rawValue)
                            apiKeyInput = ""
                        }
                        .disabled(trimmedInput.isEmpty)
                    }

                    Picker("\(keyProvider.shortName) 模型", selection: keyProvider == .gemini ? $geminiModel : $claudeModel) {
                        ForEach(keyProvider.models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    Link(keyProvider == .gemini ? "到 Google AI Studio 建立金鑰" : "到 Anthropic Console 建立金鑰",
                         destination: keyProvider.keyURL)
                } header: {
                    pxHeader(provider == .apple ? "Gemini 備援" : "\(keyProvider.shortName) 金鑰")
                } footer: {
                    pxHeader("金鑰只存在這支 iPhone 的鑰匙圈；也可以寫在程式的 Secrets.swift。")
                }
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("AI 拍照辨識")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            savedKeys = Set(AIProvider.allCases
                .filter { $0 != .apple && !(Keychain.get($0.keychainKey) ?? "").isEmpty }
                .map(\.rawValue))
        }
    }
}
