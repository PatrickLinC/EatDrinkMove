import SwiftData
import SwiftUI

@MainActor
enum AppDatabase {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: FoodEntry.self, WaterEntry.self, ExerciseEntry.self, WeightEntry.self)
        } catch {
            fatalError("無法建立資料庫：\(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}

/// 底部導覽列的分頁：今日、營地、足跡、圖鑑、戰績、角色
enum AppTab: Hashable, CaseIterable {
    case today, camp, footprints, dex, records, hero
}

/// 要打開「記錄飲食」畫面時帶的參數
struct AddFoodRequest: Identifiable {
    /// 打開後直接做的事
    enum Start {
        case none, camera, library, label, describe
    }

    let id = UUID()
    var meal: MealType?
    var date: Date?
    var start: Start = .none
}

/// 集中管理畫面切換，讓通知、Siri 捷徑、首頁指令都能把使用者帶到對的地方
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .today
    @Published var addFoodRequest: AddFoodRequest?
    /// 首頁「吃東西」指令的選單
    @Published var showEatMenu = false
    @Published var showExercise = false
    @Published var showWeight = false

    func openAddFood(meal: MealType? = nil, date: Date? = nil, start: AddFoodRequest.Start = .none) {
        showEatMenu = false
        addFoodRequest = AddFoodRequest(meal: meal, date: date, start: start)
    }
}
