import SwiftUI

/// 第一次開啟的新手導覽
struct OnboardingView: View {
    @EnvironmentObject private var health: HealthKitManager
    @AppStorage(SettingKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingKey.sex) private var sex = AppSettings.Defaults.sex
    @AppStorage(SettingKey.age) private var age = AppSettings.Defaults.age
    @AppStorage(SettingKey.heightCM) private var heightCM = AppSettings.Defaults.heightCM
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @AppStorage(SettingKey.activityLevel) private var activityLevel = AppSettings.Defaults.activityLevel
    @AppStorage(SettingKey.targetWeightKG) private var targetWeightKG = AppSettings.Defaults.targetWeightKG
    @AppStorage(SettingKey.userName) private var userName = AppSettings.Defaults.userName
    @AppStorage(SettingKey.asianAdjust) private var asianAdjust = true

    @State private var page = 0
    @State private var notificationsOn = false
    @State private var apiKey = ""

    /// 目標（減脂／維持／增肌）由目標體重自動判斷
    private var result: GoalCalculator.Result {
        GoalCalculator.calculate(
            sex: GoalCalculator.Sex(rawValue: sex) ?? .female, age: age, heightCM: heightCM,
            weightKG: weightKG, activityLevel: activityLevel,
            goal: AppSettings.effectiveGoal, asianAdjust: asianAdjust, macroStyle: AppSettings.macroStyle
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                profile.tag(1)
                permissions.tag(2)
                aiKey.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < 3 ? "下一步" : "開始冒險！")
            }
            .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 20))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.paper.ignoresSafeArea())
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .tint(Color.brand)
    }

    private func finish() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { Keychain.set(key, for: Keychain.geminiAPIKey) }
        AppSettings.applyGoals(result)
        hasOnboarded = true
        NotificationManager.shared.scheduleRefresh()
    }

    // MARK: - 頁面

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            HStack(spacing: 20) {
                PixelSprite(art: .bowl, size: 64)
                PixelSprite(art: .drop, size: 64)
                PixelSprite(art: .dumbbell, size: 64)
            }
            VStack(spacing: 6) {
                Text(AppBrand.name).font(.px(32))
                Text(AppBrand.subtitle).font(.px(12)).foregroundStyle(Color.soft)
            }
            Text("吃、喝、動，都是你的冒險。\n每一餐都會收進食物圖鑑，記錄越多角色越強。")
                .font(.px(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.soft)
            PixelWindow(spacing: 12) {
                feature(.camera, "拍照再補一句說明，AI 幫你算熱量")
                feature(.bell, "三餐、喝水會記得提醒你")
                feature(.heart, "串接 Apple Watch 與「健康」")
                feature(.book, "收集食物圖鑑、升級角色")
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func feature(_ art: PixelArt, _ text: String) -> some View {
        HStack(spacing: 10) {
            PixelSprite(art: art, size: 24)
            Text(text).font(.px(16))
        }
    }

    private var profile: some View {
        Form {
            Group {
            Section {
                TextField("你的名字", text: $userName)
                Picker("性別", selection: $sex) {
                    ForEach(GoalCalculator.Sex.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Stepper("年齡：\(age) 歲", value: $age, in: 12...100)
                Stepper("身高：\(heightCM.rounded0) 公分", value: $heightCM, in: 120...220, step: 1)
                Stepper("體重：\(weightKG.formatted(.number.precision(.fractionLength(0...1)))) 公斤",
                        value: $weightKG, in: 30...200, step: 0.5)
                Picker("活動量", selection: $activityLevel) {
                    ForEach(GoalCalculator.activityTitles.indices, id: \.self) { index in
                        Text(GoalCalculator.activityTitles[index]).tag(index)
                    }
                }
                Stepper("目標體重：\(targetWeightKG.formatted(.number.precision(.fractionLength(0...1)))) 公斤",
                        value: $targetWeightKG, in: 30...200, step: 0.5)
            } header: {
                Text("建立你的角色").font(.px(24)).foregroundStyle(Color.ink).textCase(nil)
            }

            Section {
                LabeledContent("熱量", value: "\(result.calories.rounded0) kcal")
                LabeledContent("蛋白質", value: "\(result.protein.rounded0) g")
                LabeledContent("喝水", value: "\(result.water.rounded0) ml")
                Text("之後隨時可以在「角色」調整。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            } header: {
                Text("幫你算好的每日目標（\(AppSettings.effectiveGoal.title)，之後可以在「角色 › 每日目標」改）").font(.px(12))
            }
            }
            .pixelRows()
        }
        .pixelForm()
    }

    private var permissions: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("讓我幫你記得")
                .font(.px(24))
            Text("這兩個權限讓記錄變得很輕鬆，之後也可以在「角色 › 權限與同步」更改。")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.soft)

            permissionCard(
                art: .heart, title: "連接 Apple 健康",
                detail: "自動帶入 Apple Watch 的步數、運動與消耗熱量，並把飲食和喝水存進「健康」。",
                done: health.isAvailable && !health.needsAuthorization
            ) {
                Task { await health.requestAuthorization() }
            }

            permissionCard(
                art: .bell, title: "開啟提醒",
                detail: "吃飯、喝水時間提醒你；已經記錄的就不會再吵你。手錶上也能直接按「喝了 250 ml」。",
                done: notificationsOn
            ) {
                Task { notificationsOn = await NotificationManager.shared.requestAuthorization() }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func permissionCard(art: PixelArt, title: String, detail: String, done: Bool,
                                action: @escaping () -> Void) -> some View {
        PixelWindow {
            HStack(alignment: .top, spacing: 12) {
                PixelSprite(art: art, size: 32)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.px(16))
                    Text(detail).font(.px(12)).foregroundStyle(Color.soft)
                    Button(done ? "已開啟" : "開啟", action: action)
                        .buttonStyle(.pixel(.primary, fontSize: 12))
                        .disabled(done)
                }
            }
        }
    }

    private var aiKey: some View {
        VStack(spacing: 18) {
            Spacer()
            PixelSprite(art: .camera, size: 72)
            Text("拍照 AI 辨識")
                .font(.px(24))
            Text("拍照辨識會用 iPhone 內建的 Apple AI，在手機上完成：免費、不用網路。拍完可以打字或用說的補充份量，會算得更準。\n想要更準時，可以貼上 Gemini 金鑰當備援（可略過）。")
                .font(.px(12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.soft)
            Text("這支 iPhone：\(OnDeviceFoodAnalyzer.statusText)")
                .font(.px(12))
                .foregroundStyle(OnDeviceFoodAnalyzer.isAvailable ? Color.move : Color.soft)
            SecureField("Gemini 金鑰 AQ.…（可略過）", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .pixelField()
            Link("前往 Google AI Studio 建立金鑰", destination: AIProvider.gemini.keyURL)
                .font(.px(12))
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
