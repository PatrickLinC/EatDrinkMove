import AppIntents

/// 「嘿 Siri，用卡路里大作戰記錄喝水」
/// 也可以放進「捷徑」App、設定成 iPhone 動作按鈕，或加到鎖定畫面
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "記錄喝水"

    @Parameter(title: "水量（毫升）", default: 250)
    var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("記錄喝了 \(\.$amount) 毫升水")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        LogService.shared.logWater(Double(amount), source: .siri)
        let total = LogService.shared.waters(on: .now).sum(\.amount)
        return .result(dialog: "已記錄 \(amount) 毫升，今天共喝了 \(total.rounded0) 毫升。")
    }
}

/// 直接打開相機拍這一餐
struct LogMealPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "拍照記錄飲食"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openAddFood(meal: .suggested(), start: .camera)
        return .result()
    }
}

struct EatDrinkMoveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: ["用\(.applicationName)記錄喝水", "在\(.applicationName)記錄喝水"],
            shortTitle: "記錄喝水",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogMealPhotoIntent(),
            phrases: ["用\(.applicationName)拍照記錄", "用\(.applicationName)記錄這一餐"],
            shortTitle: "拍照記錄",
            systemImageName: "camera.fill"
        )
    }
}
