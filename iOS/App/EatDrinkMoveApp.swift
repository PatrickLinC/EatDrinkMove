import SwiftData
import SwiftUI
import UserNotifications

@main
struct EatDrinkMoveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter.shared
    @StateObject private var health = HealthKitManager.shared

    init() {
        // 從備份還原：要在資料庫和各個存檔打開之前換上去
        BackupService.applyPendingRestore()
        AppSettings.registerDefaults()
        PixelAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(health)
        }
        .modelContainer(AppDatabase.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppSettings.registerDefaults()
        // 必須在啟動時就設定，App 在背景被通知按鈕或手錶喚醒時才接得到
        NotificationManager.shared.setup()
        PhoneConnectivity.shared.activate()
        MainActor.assumeIsolated {
            // 世界迷霧：在背景被位置變動叫醒時也要接著監聽
            WorldFogStore.shared.resumeIfEnabled()
            // 久坐提醒：「健康」在背景送來新步數時重新排提醒
            SedentaryMonitor.startObservingIfNeeded()
        }
        return true
    }
}

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingKey.themeMode) private var themeMode = AppSettings.Defaults.themeMode
    @AppStorage(PixelPalette.storageKey) private var palette = PixelPalette.milkTea.rawValue
    @AppStorage(SettingKey.companionEnabled) private var companionEnabled = true
    @ObservedObject private var spirits = SpiritCollection.shared
    @ObservedObject private var adventure = AdventureStore.shared
    @ObservedObject private var journey = JourneyStore.shared
    @ObservedObject private var stress = StressStore.shared
    @ObservedObject private var weekly = WeeklyStore.shared
    @ObservedObject private var recorder = RouteRecorder.shared
    @State private var dayKey = Date.now.dayKey
    /// 「吃東西」選單關掉之後才打開記錄畫面，避免兩個 sheet 同時切換
    @State private var pendingAddFood: AddFoodRequest?

    private var colorScheme: ColorScheme? {
        if PixelPalette(rawValue: palette)?.forcesDark == true { return .dark }
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        // 分頁和導覽列上下排，內容不會被導覽列蓋住
        VStack(spacing: 0) {
            ZStack {
                page(.today) { TodayView().id(dayKey) } // 過了午夜重新建立，顯示新的一天
                page(.camp) { CampView() }
                page(.footprints) { FootprintView() }
                page(.dex) { DexView() }
                page(.records) { RecordsView() }
                page(.hero) { HeroView() }
            }
            // AI 小夥伴浮在分頁上（不會蓋到導覽列）
            .overlay {
                if companionEnabled { CompanionFloat() }
            }
            PixelTabBar()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color.paper.ignoresSafeArea())
        .id(palette) // 換配色時整個重畫
        .tint(Color.brand)
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .preferredColorScheme(colorScheme)
        // 起床夢境結算、睡前營火（新手導覽完才出現；精靈慶祝畫面會蓋在上面）
        .overlay {
            if hasOnboarded, adventure.showMorning {
                MorningReportView { withAnimation { adventure.showMorning = false } }
                    .transition(.opacity)
            } else if hasOnboarded, adventure.showCampfire {
                CampfireView { withAnimation { adventure.showCampfire = false } }
                    .transition(.opacity)
            }
        }
        // 主線故事（抵達新區域、第一次打開地圖時）
        .overlay {
            if hasOnboarded, let scene = journey.playing {
                StoryView(scene: scene) { withAnimation { journey.finish(scene) } }
                    .id(scene.id)
                    .transition(.opacity)
            }
        }
        // 出發冒險：記錄路線中
        .overlay {
            if recorder.showRecorder {
                RecordingView()
                    .transition(.opacity)
            }
        }
        // 每週回顧
        .overlay {
            if hasOnboarded, weekly.showReview {
                WeeklyReviewView { withAnimation { weekly.showReview = false } }
                    .transition(.opacity)
            }
        }
        // 一分鐘呼吸
        .overlay {
            if hasOnboarded, stress.showBreathing {
                BreathingView { withAnimation { stress.showBreathing = false } }
                    .transition(.opacity)
            }
        }
        // 喚醒新精靈時的慶祝畫面（新手導覽完才出現）
        .overlay {
            if hasOnboarded, let celebration = spirits.celebration {
                SpiritCelebrationView(celebration: celebration) {
                    withAnimation { spirits.dismissCelebration() }
                }
                .id(celebration.id)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $router.showEatMenu, onDismiss: {
            if let pendingAddFood {
                router.addFoodRequest = pendingAddFood
                self.pendingAddFood = nil
            }
        }) {
            EatCommandSheet { start in
                pendingAddFood = AddFoodRequest(meal: .suggested(), start: start)
                router.showEatMenu = false
            }
        }
        .sheet(item: $router.addFoodRequest) { request in
            AddFoodView(request: request)
        }
        .sheet(isPresented: $router.showExercise) {
            AddExerciseView()
        }
        .sheet(isPresented: $router.showWeight) {
            LogWeightView()
        }
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { _ in })) {
            OnboardingView()
        }
        .task { await appBecameActive() }
        #if DEBUG
        // 開發用：模擬器截圖檢查畫面時，用啟動參數直接打開某一頁（例如 -tab dex、-companionSettings）
        .task { openDebugPage() }
        .sheet(isPresented: $debugCompanionSettings) {
            NavigationStack { CompanionSettingsView(showsChatButton: false) }
        }
        .sheet(isPresented: $debugTitles) {
            NavigationStack { TitleView() }
        }
        .sheet(isPresented: $debugBackup) {
            NavigationStack { BackupView() }
        }
        .sheet(isPresented: $debugIcons) {
            NavigationStack { AppIconView() }
        }
        .sheet(isPresented: $debugStress) { StressDetailView() }
        .sheet(isPresented: $debugBoss) { BossView() }
        .sheet(isPresented: $debugChronicle) {
            if let current = weekly.current { ChronicleSheet(chronicle: current) }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WorldFogStore.shared.enterForeground()
                Task { await appBecameActive() }
            } else if phase == .background {
                WorldFogStore.shared.enterBackground()
            }
        }
    }

    /// 每個分頁都留著（切回來時捲動位置還在），只顯示選到的那一頁
    private func page<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = router.selectedTab == tab
        return content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
    }

    #if DEBUG
    @State private var debugCompanionSettings = false
    @State private var debugTitles = false
    @State private var debugBackup = false
    @State private var debugIcons = false
    @State private var debugStress = false
    @State private var debugBoss = false
    @State private var debugChronicle = false

    private func openDebugPage() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "dex": router.selectedTab = .dex
            case "camp": router.selectedTab = .camp
            case "footprints": router.selectedTab = .footprints
            case "records": router.selectedTab = .records
            case "hero": router.selectedTab = .hero
            default: router.selectedTab = .today
            }
        }
        debugCompanionSettings = arguments.contains("-companionSettings")
        debugTitles = arguments.contains("-titles")
        debugBackup = arguments.contains("-backupView")
        debugIcons = arguments.contains("-appIcons")
        debugStress = arguments.contains("-stressDetail")
        debugBoss = arguments.contains("-boss")
        recorder.seedForScreenshots()
        // -backupRoundTrip：匯出備份再放進還原暫存區，重開 App 時檢查還原是否正常
        if arguments.contains("-backupRoundTrip") {
            Task {
                let log = FileManager.default.temporaryDirectory.appending(path: "backup-test.txt")
                do {
                    let url = try await BackupService.makeBackup()
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let date = try await BackupService.stageRestore(from: url)
                    try? "ok size=\(size) date=\(date) pending=\(BackupService.hasPendingRestore)".write(to: log, atomically: true, encoding: .utf8)
                } catch {
                    try? "error \(error)".write(to: log, atomically: true, encoding: .utf8)
                }
            }
        }
        Task {
            // 編年史要等週資料算好
            try? await Task.sleep(for: .seconds(2))
            debugChronicle = arguments.contains("-chronicle")
        }
        // -dexPage map 會直接變成 UserDefaults 的值（啟動參數），DexView 讀得到，不用另外設
    }
    #endif

    private func appBecameActive() async {
        dayKey = Date.now.dayKey
        // 新版本多要了睡眠、心率變異度等權限：之前授權過的人自動再問一次
        await health.requestNewPermissionsIfNeeded()
        await health.refreshToday()
        await LogService.shared.syncPendingToHealth()
        // 已經打開 App 了，通知中心裡之前送出的提醒就不需要了（也避免留著改名前的舊通知）
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        NotificationManager.shared.scheduleRefresh()
        PhoneConnectivity.shared.pushSummary()
        await spirits.evaluate()
        await adventure.refresh()
        await journey.refresh()
        await stress.refresh()
        await weekly.refresh()
        await RouteStore.shared.importFromHealth()
        // 焦慮霧出現的那天，小夥伴提醒一次
        if stress.fogActive, UserDefaults.standard.string(forKey: "fogTipDay") != Date.now.dayKey {
            UserDefaults.standard.set(Date.now.dayKey, forKey: "fogTipDay")
            CompanionStore.shared.show("今天身體有點緊繃……想吃零食的時候，先喝杯水、做一分鐘呼吸吧。")
        } else {
            CompanionStore.shared.maybeShowTip()
        }
    }
}
