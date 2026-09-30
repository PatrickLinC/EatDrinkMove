import SwiftUI

@main
struct EatDrinkMoveWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(store)
        }
    }
}

/// 上下滑動切換五頁：夥伴、今日狀態、喝水、常吃食物、冒險；記錄散步跑步時直接顯示記錄畫面
struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchStore
    @ObservedObject private var workout = WorkoutManager.shared

    var body: some View {
        NavigationStack {
            if workout.phase != .idle {
                WorkoutSessionView()
                    .containerBackground(Color.paper, for: .navigation)
            } else {
            TabView {
                CompanionPage()
                    .navigationTitle("夥伴")
                    .containerBackground(Color.paper, for: .tabView)
                SummaryPage()
                    .navigationTitle("狀態")
                    .containerBackground(Color.paper, for: .tabView)
                WaterPage()
                    .navigationTitle("水壺")
                    .containerBackground(Color.paper, for: .tabView)
                QuickFoodPage()
                    .navigationTitle("常吃")
                    .containerBackground(Color.paper, for: .tabView)
                AdventurePage()
                    .navigationTitle("冒險")
                    .containerBackground(Color.paper, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
            }
        }
        .font(.px(12))
        .foregroundStyle(Color.ink)
        .tint(Color.brand)
        .onAppear {
            store.requestRefresh()
            #if DEBUG
            workout.seedForScreenshots()
            #endif
        }
    }
}

struct SummaryPage: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let s = store.today
        let remaining = s.calorieGoal - s.calories
        VStack(alignment: .leading, spacing: 6) {
            Text(remaining >= 0 ? "還可以吃" : "超過").font(.px(12)).foregroundStyle(Color.soft)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(abs(remaining).rounded0)")
                    .font(.px(32))
                    .foregroundStyle(remaining >= 0 ? Color.ink : Color.danger)
                Text("大卡").font(.px(12)).foregroundStyle(Color.soft)
            }
            PixelBar(value: s.calories, total: max(s.calorieGoal, 1), color: .calorie, segments: 8, height: 8)
            HStack {
                Text("水 \(s.waterML.rounded0)")
                Spacer()
                Text("步 \(s.steps.rounded0)")
            }
            .font(.px(12))
            PixelBar(value: s.waterML, total: max(s.waterGoalML, 1), color: .water, segments: 8, height: 8,
                     overIsBad: false)
            if !s.loggedMeals.isEmpty {
                Text("已記錄：" + MealType.allCases.filter { s.loggedMeals.contains($0) }.map(\.title).joined(separator: "、"))
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WaterPage: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let s = store.today
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.waterML.rounded0)").font(.px(32))
                Text("ml").font(.px(12)).foregroundStyle(Color.soft)
            }
            Text("目標 \(s.waterGoalML.rounded0) ml").font(.px(12)).foregroundStyle(Color.soft)
            PixelBar(value: s.waterML, total: max(s.waterGoalML, 1), color: .water, segments: 8, height: 8,
                     overIsBad: false)
            HStack {
                waterButton(150)
                waterButton(250)
                waterButton(500)
            }
        }
    }

    private func waterButton(_ ml: Int) -> some View {
        Button("+\(ml)") { store.logWater(Double(ml)) }
            .font(.px(12))
            .tint(Color.water)
    }
}

struct QuickFoodPage: View {
    @EnvironmentObject private var store: WatchStore
    @State private var confirming: QuickFood?

    var body: some View {
        let foods = store.today.quickFoods
        Group {
            if foods.isEmpty {
                Text("在 iPhone 記錄幾次後，常吃的食物會出現在這裡，點一下就能記錄。")
                    .font(.px(12))
                    .multilineTextAlignment(.center)
            } else {
                List(foods) { food in
                    Button {
                        confirming = food
                    } label: {
                        HStack {
                            Text(food.emoji.isEmpty ? "🍽️" : food.emoji).font(.system(size: 20))
                            VStack(alignment: .leading) {
                                Text(food.name).lineLimit(1)
                                Text("\(food.calories.rounded0) kcal").font(.px(12)).foregroundStyle(Color.soft)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("記錄「\(confirming?.name ?? "")」？",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            Button("記錄") {
                if let confirming { store.logFood(confirming) }
                confirming = nil
            }
            Button("取消", role: .cancel) { confirming = nil }
        }
    }
}

// MARK: - 冒險（在手錶上記錄散步、跑步）

struct AdventurePage: View {
    @ObservedObject private var workout = WorkoutManager.shared

    var body: some View {
        VStack(spacing: 6) {
            Text("出發冒險").font(.px(12)).foregroundStyle(Color.soft)
            ForEach(WatchRouteKind.allCases) { kind in
                Button {
                    Task { await workout.start(kind) }
                } label: {
                    HStack(spacing: 6) {
                        PixelSprite(art: kind.art, size: 16)
                        Text(kind.title)
                        Spacer(minLength: 0)
                    }
                }
                .font(.px(12))
                .tint(Color.brand)
            }
            if let error = workout.errorMessage {
                Text(error).font(.px(12)).foregroundStyle(Color.danger).lineLimit(2)
            }
        }
    }
}
