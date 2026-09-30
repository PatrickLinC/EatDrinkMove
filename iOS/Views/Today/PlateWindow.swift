import SwiftUI

/// 今日頁「我的餐盤」：蔬菜、水果、豆魚蛋肉、乳品、堅果吃了幾份（國健署每日飲食指南）
struct PlateWindow: View {
    let foods: [FoodEntry]
    var day: Date = .now
    @AppStorage(SettingKey.calorieGoal) private var calorieGoal = AppSettings.Defaults.calorieGoal
    @State private var refresh = 0
    @State private var showInfo = false

    var body: some View {
        let summary = PlateLog.summary(foods: foods, day: day)
        PixelWindow(title: "我的餐盤", tint: .move) {
            ForEach(PlateGroup.allCases) { group in
                let value = summary[group]?.servings ?? 0
                let target = group.target(calories: calorieGoal)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        PixelSprite(art: group.art, size: 20)
                        Text(group.title)
                        Spacer(minLength: 4)
                        Text("\(Self.number(value))／\(Self.number(target)) \(group.unit)")
                            .font(.px(12))
                            .foregroundStyle(value >= target ? group.color : Color.soft)
                            .monospacedDigit()
                        if group.isManual {
                            if PlateLog.manual(group, on: day) > 0 {
                                stepButton("−", group: group, amount: group == .dairy ? -0.5 : -1)
                            }
                            stepButton("＋", group: group, amount: group == .dairy ? 0.5 : 1)
                        }
                    }
                    PixelBar(value: value, total: target, color: group.color, segments: 10, height: 6, overIsBad: false)
                    if let sources = summary[group]?.sources, !sources.isEmpty {
                        Text("算進去：" + sources.prefix(4).joined(separator: "、") + (sources.count > 4 ? "…" : ""))
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                            .lineLimit(1)
                    }
                }
            }
            Button {
                showInfo.toggle()
            } label: {
                Text(showInfo ? "收起說明" : "怎麼算的？").font(.px(12)).foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
            if showInfo {
                Text("參考國健署「每日飲食指南」，依你每天 \(calorieGoal.rounded0) 大卡的目標建議份數。記錄的食物名稱有青菜、水果、鮮奶、堅果等會自動算一份（便當算一份蔬菜）；沒算到的按「＋」補上。豆魚蛋肉由蛋白質推算，每 7 公克約一份。")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(PlateGroup.allCases) { group in
                    Text("・\(group.title)：\(group.hint)").font(.px(12)).foregroundStyle(Color.soft)
                }
            }
        }
        .id(refresh)
    }

    private func stepButton(_ title: String, group: PlateGroup, amount: Double) -> some View {
        Button(title) {
            PlateLog.add(amount, to: group, on: day)
            refresh += 1
        }
        .buttonStyle(.pixel(.secondary, fontSize: 12))
        .accessibilityLabel(amount > 0 ? "\(group.title)加一份" : "\(group.title)減一份")
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }
}
