import SwiftUI

/// 健康計算機：BMI、BMR / TDEE、熱量赤字、營養素分配、體脂率
struct CalculatorsView: View {
    @AppStorage(SettingKey.sex) private var sex = AppSettings.Defaults.sex
    @AppStorage(SettingKey.age) private var age = AppSettings.Defaults.age
    @AppStorage(SettingKey.heightCM) private var heightCM = AppSettings.Defaults.heightCM
    @AppStorage(SettingKey.weightKG) private var weightKG = AppSettings.Defaults.weightKG
    @AppStorage(SettingKey.activityLevel) private var activityLevel = AppSettings.Defaults.activityLevel
    @AppStorage(SettingKey.asianAdjust) private var asianAdjust = true
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @AppStorage(SettingKey.proteinGoal) private var proteinGoal = AppSettings.Defaults.proteinGoal
    @AppStorage(SettingKey.carbsGoal) private var carbsGoal = AppSettings.Defaults.carbsGoal
    @AppStorage(SettingKey.fatGoal) private var fatGoal = AppSettings.Defaults.fatGoal

    @State private var targetWeight: Double = AppSettings.targetWeightKG
    @State private var weeklyLoss: Double = 0.5
    @State private var macroPreset = GoalCalculator.MacroStyle.highProtein
    @State private var neck: Double = 34
    @State private var waist: Double = 78
    @State private var hip: Double = 95
    @State private var appliedMessage: String?

    private var isMale: Bool { sex == GoalCalculator.Sex.male.rawValue }

    private var profile: GoalCalculator.Result {
        GoalCalculator.calculate(sex: isMale ? .male : .female, age: age, heightCM: heightCM, weightKG: weightKG,
                                 activityLevel: activityLevel, goal: .maintain, asianAdjust: asianAdjust)
    }

    var body: some View {
        Form {
            Group {
            Section {
                Text("身高 \(heightCM.formatted()) 公分 · 體重 \(weightKG.formatted()) 公斤 · \(age) 歲 · \(isMale ? "男性" : "女性")")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            } footer: {
                Text("這些數值來自「角色 › 個人資料」。").font(.px(12))
            }

            bmiSection
            energySection
            deficitSection
            macroSection
            bodyFatSection
            }
            .pixelRows()
        }
        .pixelForm()
        .navigationTitle("健康計算機")
        .navigationBarTitleDisplayMode(.inline)
        .alert(appliedMessage ?? "", isPresented: Binding(get: { appliedMessage != nil },
                                                          set: { if !$0 { appliedMessage = nil } })) {
            Button("好") { appliedMessage = nil }
        }
    }

    // MARK: - BMI（國民健康署標準）

    private var bmiSection: some View {
        let meters = heightCM / 100
        let bmi = meters > 0 ? weightKG / (meters * meters) : 0
        let (label, color) = Self.bmiCategory(bmi)
        let low = 18.5 * meters * meters
        let high = 24 * meters * meters

        return Section {
            HStack(alignment: .firstTextBaseline) {
                Text(bmi.formatted(.number.precision(.fractionLength(1))))
                    .font(.px(32))
                Text(label).font(.px(16)).foregroundStyle(color)
            }
            Text("你的健康體重範圍：\(low.formatted(.number.precision(.fractionLength(1)))) – \(high.formatted(.number.precision(.fractionLength(1)))) 公斤")
                .font(.px(12))
        } header: {
            Text("BMI 身體質量指數")
        } footer: {
            Text("BMI = 體重(kg) ÷ 身高(m)²。依國民健康署標準：18.5 以下過輕、18.5–24 健康、24–27 過重、27 以上肥胖。")
        }
    }

    private static func bmiCategory(_ bmi: Double) -> (String, Color) {
        switch bmi {
        case ..<18.5: ("體重過輕", Color.water)
        case ..<24: ("健康體位", Color.move)
        case ..<27: ("過重", Color.carbs)
        case ..<30: ("輕度肥胖", Color.calorie)
        case ..<35: ("中度肥胖", Color.red)
        default: ("重度肥胖", Color.red)
        }
    }

    // MARK: - BMR / TDEE

    private var energySection: some View {
        let result = profile
        return Section {
            LabeledContent("基礎代謝 BMR", value: "\(result.bmr.rounded0) kcal")
            ForEach(GoalCalculator.activityTitles.indices, id: \.self) { level in
                let tdee = result.bmr * [1.2, 1.375, 1.55, 1.725][level]
                LabeledContent(GoalCalculator.activityTitles[level], value: "\(tdee.rounded0) kcal")
                    .fontWeight(level == activityLevel ? .bold : .regular)
            }
        } header: {
            Text("BMR 與 TDEE 每日總消耗")
        } footer: {
            Text("BMR 是躺著不動一天所需的熱量；TDEE 再加上日常活動與運動。粗體是你目前的活動量。\(asianAdjust ? "已套用亞洲人代謝校正（× 0.95）。" : "")")
        }
    }

    // MARK: - 熱量赤字

    private var deficitSection: some View {
        let tdee = profile.tdee
        let dailyDeficit = weeklyLoss * 7700 / 7
        let floor: Double = isMale ? 1500 : 1200
        let intake = max(tdee - dailyDeficit, floor)
        let toLose = max(weightKG - targetWeight, 0)
        let weeks = weeklyLoss > 0 ? toLose / weeklyLoss : 0
        let arrival = Date.now.adding(days: Int((weeks * 7).rounded()))

        return Section {
            HStack {
                Text("目標體重")
                Spacer()
                TextField("目標", value: $targetWeight, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("公斤").foregroundStyle(Color.soft)
            }
            Picker("每週減重", selection: $weeklyLoss) {
                Text("0.25 公斤（輕鬆）").tag(0.25)
                Text("0.5 公斤（建議）").tag(0.5)
                Text("0.75 公斤（積極）").tag(0.75)
                Text("1 公斤（很辛苦）").tag(1.0)
            }
            LabeledContent("每日赤字", value: "約 \(dailyDeficit.rounded0) kcal")
            LabeledContent("建議每日攝取", value: "\(intake.rounded0) kcal")
            if toLose > 0 {
                LabeledContent("預計需要", value: "約 \(weeks.rounded0) 週")
                LabeledContent("預計達成", value: arrival.formatted(date: .long, time: .omitted))
            }
            if tdee - dailyDeficit < floor {
                Text("⚠️ 這個速度會讓攝取低於 \(floor.rounded0) kcal，已自動調高。建議選慢一點的速度，比較能保住肌肉。")
                    .font(.px(12))
                    .foregroundStyle(.orange)
            }
            Button("把 \(intake.rounded0) kcal 設為每日熱量目標") {
                calorieGoal = (intake / 50).rounded() * 50
                appliedMessage = "已把每日熱量目標設為 \(calorieGoal.rounded0) kcal"
            }
        } header: {
            Text("熱量赤字")
        } footer: {
            Text("每減少約 7,700 kcal ≈ 減 1 公斤體重。一般建議每天赤字 300–500 kcal，每週減重不超過 0.5–1 公斤。")
        }
    }

    // MARK: - 營養素分配

    private var macroSection: some View {
        let split = macroPreset.split ?? (0.20, 0.50, 0.30)
        let protein = (calorieGoal * split.protein / 4).rounded()
        let carbs = (calorieGoal * split.carbs / 4).rounded()
        let fat = (calorieGoal * split.fat / 9).rounded()

        return Section {
            Picker("飲食方式", selection: $macroPreset) {
                ForEach(GoalCalculator.MacroStyle.allCases.filter { $0.split != nil }) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent(macroLabel("蛋白質", split.protein), value: "\(protein.rounded0) g")
            LabeledContent(macroLabel("碳水化合物", split.carbs), value: "\(carbs.rounded0) g")
            LabeledContent(macroLabel("脂肪", split.fat), value: "\(fat.rounded0) g")
            Button("設為每日目標的飲食方式") {
                UserDefaults.standard.set(macroPreset.rawValue, forKey: SettingKey.macroStyle)
                if UserDefaults.standard.bool(forKey: SettingKey.autoGoals) {
                    AppSettings.applyAutoGoalsIfNeeded()
                } else {
                    proteinGoal = protein
                    carbsGoal = carbs
                    fatGoal = fat
                }
                PhoneConnectivity.shared.pushSummary()
                appliedMessage = "已把飲食方式設為「\(macroPreset.title)」"
            }
        } header: {
            Text("三大營養素分配（依每日 \(calorieGoal.rounded0) kcal）")
        } footer: {
            Text("每克蛋白質和碳水化合物約 4 kcal，每克脂肪約 9 kcal。")
        }
    }

    private func macroLabel(_ name: String, _ ratio: Double) -> String {
        "\(name) \(Int((ratio * 100).rounded()))%"
    }

    // MARK: - 體脂率（美國海軍公式）

    private var bodyFatSection: some View {
        let bodyFat: Double? = {
            guard heightCM > 0 else { return nil }
            if isMale {
                guard waist > neck else { return nil }
                return 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(heightCM)) - 450
            } else {
                guard waist + hip > neck else { return nil }
                return 495 / (1.29579 - 0.35004 * log10(waist + hip - neck) + 0.22100 * log10(heightCM)) - 450
            }
        }()

        return Section {
            measurement("頸圍", value: $neck)
            measurement("腰圍", value: $waist)
            if !isMale { measurement("臀圍", value: $hip) }
            if let bodyFat, bodyFat.isFinite, bodyFat > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(bodyFat.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.px(32))
                    Text(bodyFatCategory(bodyFat)).font(.px(16)).foregroundStyle(Color.brand)
                }
            } else {
                Text("請確認量測數值").foregroundStyle(Color.soft)
            }
        } header: {
            Text("體脂率估算")
        } footer: {
            Text("""
            美國海軍公式，用皮尺量：頸圍量喉結正下方，腰圍\(isMale ? "量肚臍高度" : "量腰部最細處")\(isMale ? "" : "，臀圍量最寬處")。
            男性：運動員 6–13%、健康 14–17%、一般 18–24%、偏高 25% 以上。
            女性：運動員 14–20%、健康 21–24%、一般 25–31%、偏高 32% 以上。
            """)
        }
    }

    private func bodyFatCategory(_ value: Double) -> String {
        let limits: [Double] = isMale ? [14, 18, 25] : [21, 25, 32]
        if value < limits[0] { return "運動員" }
        if value < limits[1] { return "健康" }
        if value < limits[2] { return "一般" }
        return "偏高"
    }

    private func measurement(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("公分").foregroundStyle(Color.soft)
        }
    }
}
