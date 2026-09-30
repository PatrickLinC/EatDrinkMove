import HealthKit
import SwiftData
import SwiftUI

/// 運動紀錄（從首頁的運動卡片點進來）：Apple Watch 的體能訓練 + 手動記錄
struct ExerciseView: View {
    @EnvironmentObject private var health: HealthKitManager
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var manualEntries: [ExerciseEntry]
    @AppStorage(SettingKey.stepGoal) private var stepGoal = AppSettings.Defaults.stepGoal
    @State private var showAdd = false

    var body: some View {
            List {
                Group {
                Section {
                    if health.needsAuthorization {
                        Button("連接 Apple 健康，自動讀取 Apple Watch 的運動") {
                            Task { await health.requestAuthorization() }
                        }
                    } else {
                        LabeledContent("步數", value: "\(health.steps.rounded0.formatted()) / \(stepGoal.rounded0.formatted()) 步")
                        LabeledContent("活動消耗", value: "\(health.activeCalories.rounded0) kcal")
                        LabeledContent("運動時間", value: "\(health.exerciseMinutes.rounded0) 分鐘")
                    }
                } header: {
                    Text("今天").font(.px(12))
                }

                Section {
                    if health.recentWorkouts.isEmpty {
                        Text("最近 7 天沒有 Apple Watch 的體能訓練紀錄。")
                            .foregroundStyle(Color.soft)
                    }
                    ForEach(health.recentWorkouts, id: \.uuid) { workout in
                        HStack(spacing: 12) {
                            PixelSprite(art: .dumbbell, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.workoutActivityType.displayName)
                                Text(workout.startDate.formatted(.dateTime.month().day().hour().minute()))
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\((workout.duration / 60).rounded0) 分鐘")
                                Text("\(workout.activeKcal.rounded0) kcal")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                        }
                    }
                } header: {
                    Text("Apple Watch 運動紀錄（近 7 天）").font(.px(12))
                } footer: {
                    Text("在手錶上用「體能訓練」App 開始運動，結束後會自動出現在這裡。").font(.px(12))
                }

                Section {
                    if manualEntries.isEmpty {
                        Text("沒戴手錶的運動可以在這裡手動記錄。")
                            .foregroundStyle(Color.soft)
                    }
                    ForEach(manualEntries) { entry in
                        HStack {
                            Text(ExerciseKind.icon(for: entry.name))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                Text(entry.date.formatted(.dateTime.month().day().hour().minute()))
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(entry.minutes.rounded0) 分鐘")
                                Text("約 \(entry.calories.rounded0) kcal")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { LogService.shared.delete(manualEntries[index]) }
                    }
                } header: {
                    Text("手動記錄").font(.px(12))
                }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("運動紀錄")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("＋ 記錄") { showAdd = true }
                }
            }
            .refreshable { await health.refreshToday() }
            .task { await health.refreshToday() }
            .sheet(isPresented: $showAdd) { AddExerciseView() }
    }
}

/// 常見運動與 MET 值（依 2011 Compendium of Physical Activities）
struct ExerciseKind: Identifiable, Hashable {
    let name: String
    let met: Double
    let icon: String
    var id: String { name }

    static let all: [ExerciseKind] = [
        ExerciseKind(name: "散步", met: 3.0, icon: "🚶"),
        ExerciseKind(name: "快走", met: 4.3, icon: "🚶‍♀️"),
        ExerciseKind(name: "慢跑", met: 7.0, icon: "🏃"),
        ExerciseKind(name: "跑步（時速 10 公里）", met: 9.8, icon: "🏃‍♀️"),
        ExerciseKind(name: "騎腳踏車", met: 6.8, icon: "🚴"),
        ExerciseKind(name: "游泳", met: 7.0, icon: "🏊"),
        ExerciseKind(name: "重量訓練", met: 5.0, icon: "🏋️"),
        ExerciseKind(name: "瑜珈", met: 2.5, icon: "🧘"),
        ExerciseKind(name: "皮拉提斯", met: 3.0, icon: "🤸"),
        ExerciseKind(name: "爬樓梯", met: 8.8, icon: "🪜"),
        ExerciseKind(name: "跳繩", met: 11.0, icon: "🪢"),
        ExerciseKind(name: "有氧舞蹈", met: 7.3, icon: "💃"),
        ExerciseKind(name: "羽球", met: 5.5, icon: "🏸"),
        ExerciseKind(name: "籃球", met: 6.5, icon: "🏀"),
        ExerciseKind(name: "爬山", met: 6.0, icon: "⛰️"),
        ExerciseKind(name: "做家事", met: 3.3, icon: "🧹"),
    ]

    static func icon(for name: String) -> String {
        all.first { $0.name == name }?.icon ?? "💪"
    }
}

struct AddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @State private var kind = ExerciseKind.all[1]
    @State private var minutes: Double = 30
    @State private var date = Date.now

    /// 消耗熱量 = MET × 體重(kg) × 時間(小時)
    private var calories: Double { kind.met * weightKG * minutes / 60 }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Picker("運動", selection: $kind) {
                    ForEach(ExerciseKind.all) { item in
                        Text("\(item.icon) \(item.name)").tag(item)
                    }
                }
                Stepper("時間：\(minutes.rounded0) 分鐘", value: $minutes, in: 5...300, step: 5)
                DatePicker("時間", selection: $date)
                Section {
                    LabeledContent("估計消耗", value: "約 \(calories.rounded0) kcal")
                } footer: {
                    Text("依你的體重 \(weightKG.formatted()) 公斤與運動強度（MET \(kind.met.formatted())）估算。").font(.px(12))
                }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("記錄運動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        LogService.shared.logExercise(name: kind.name, minutes: minutes, calories: calories, date: date)
                        dismiss()
                    }
                }
            }
        }
    }
}
