import SwiftUI

// MARK: - 節慶活動（今日頁）

/// 節慶期間才出現：節慶精靈的進度、剩幾天、營地的限定裝飾
struct FestivalWindow: View {
    let festival: Festival
    @ObservedObject private var spirits = SpiritCollection.shared
    @ObservedObject private var camp = CampStore.shared
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        let skin = festival.spirit
        let unlocked = spirits.unlockedDate(skin) != nil
        let shiny = spirits.unlockedDate(skin, shiny: true) != nil
        let requirement = unlocked ? skin.shinyRequirement : skin.requirement
        PixelWindow(title: "\(festival.title)活動", tint: .calorie) {
            HStack(alignment: .top, spacing: 12) {
                if unlocked {
                    PixelSprite(art: skin.art(shiny: shiny), size: 48)
                } else {
                    PixelSprite(art: skin.art, size: 48, tint: .track)
                        .overlay { Text("？").font(.px(16)).foregroundStyle(Color.soft) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(festival.greeting).fixedSize(horizontal: false, vertical: true)
                    if let window = festival.upcoming() {
                        Text("活動到 \(window.end.adding(days: -1).formatted(.dateTime.month().day()))，還剩 \(Self.daysLeft(window)) 天")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                }
            }
            PixelDivider()
            if shiny {
                Text("閃光\(skin.title)已經到手了，節慶快樂！").font(.px(12)).foregroundStyle(Color.carbs)
            } else {
                Text(unlocked ? "閃光版：\(requirement.text)" : "喚醒\(skin.title)：\(requirement.text)")
                    .font(.px(12))
                    .fixedSize(horizontal: false, vertical: true)
                let value = spirits.progress(skin, shiny: unlocked)
                PixelBar(value: value, total: requirement.target, color: unlocked ? .carbs : .calorie,
                         segments: Int(requirement.target), height: 8, overIsBad: false)
                Text("已經做到 \(SpiritDetailSheet.number(value))／\(SpiritDetailSheet.number(requirement.target)) \(requirement.unit)")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
            if !camp.hasDecoration(festival) {
                PixelDivider()
                HStack(spacing: 10) {
                    PixelSprite(art: festival.decorationArt, size: 28)
                    Text("營地可以蓋限定的\(festival.decorationTitle)").font(.px(12))
                    Spacer(minLength: 4)
                    Button("去營地") { router.selectedTab = .camp }
                        .buttonStyle(.pixel(.secondary, fontSize: 12))
                }
            }
        }
    }

    static func daysLeft(_ window: DateInterval) -> Int {
        max(Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: window.end).day ?? 0, 1)
    }
}

/// 圖鑑的節慶精靈：活動期間或下一次的日期
struct FestivalScheduleText: View {
    let festival: Festival

    var body: some View {
        if let window = festival.upcoming() {
            let last = window.end.adding(days: -1)
            Text(festival.isActive() ? "活動進行中！到 \(Self.short(last))" : "下一次：\(Self.range(window.start, last))")
                .font(.px(12))
                .foregroundStyle(festival.isActive() ? Color.calorie : Color.soft)
        }
    }

    /// 2026/10/25–10/31
    static func range(_ start: Date, _ end: Date) -> String {
        "\(Calendar.current.component(.year, from: start))/\(short(start))–\(short(end))"
    }

    static func short(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}
