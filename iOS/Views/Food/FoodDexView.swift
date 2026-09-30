import SwiftData
import SwiftUI

/// 食物圖鑑：每種吃過的食物都有編號和像素圖，還有收集成就
struct FoodDexView: View {
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @State private var order: Order = .number
    @State private var selected: DexEntry?

    enum Order: String, CaseIterable, Identifiable {
        case number = "編號", count = "最常吃", recent = "最近"
        var id: String { rawValue }
    }

    /// 圖鑑裡的一種食物（同名的記錄算同一種）
    struct DexEntry: Identifiable {
        let number: Int
        let name: String
        /// 新到舊
        let entries: [FoodEntry]
        var id: String { name }
        var latest: FoodEntry { entries[0] }
        /// 有照片貼紙就用最近一張照片
        var cover: FoodEntry { entries.first { $0.stickerData != nil } ?? latest }
    }

    private static let milestones = [10, 30, 50, 100, 200, 365, 500, 1000]

    private var dex: [DexEntry] {
        var order: [String] = []
        var groups: [String: [FoodEntry]] = [:]
        for entry in foods {
            if groups[entry.name] == nil { order.append(entry.name) }
            groups[entry.name, default: []].append(entry)
        }
        return order.enumerated().map { index, name in
            DexEntry(number: index + 1, name: name, entries: (groups[name] ?? []).reversed())
        }
    }

    private func sorted(_ list: [DexEntry]) -> [DexEntry] {
        switch order {
        case .number: list
        case .count: list.sorted { $0.entries.count != $1.entries.count ? $0.entries.count > $1.entries.count : $0.number < $1.number }
        case .recent: list.sorted { $0.latest.date > $1.latest.date }
        }
    }

    var body: some View {
        let dex = dex
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelPageHeader(title: "食物圖鑑", subtitle: "FOOD DEX") {
                        PixelChip(text: "\(dex.count) 種", color: .brand)
                    }
                    progressWindow(kinds: dex.count)
                    trophyWindow
                    dexWindow(sorted(dex))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { DexDetailSheet(number: $0.number, name: $0.name) }
        }
    }

    private func progressWindow(kinds: Int) -> some View {
        let count = foods.count
        let days = Set(foods.map { $0.date.startOfDay }).count
        let next = Self.milestones.first { $0 > count } ?? (count + 100)
        let previous = Self.milestones.last { $0 <= count } ?? 0

        return PixelWindow(title: "收集進度") {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                stat("\(kinds)", "種食物")
                stat("\(count)", "筆記錄")
                stat("\(days)", "天")
            }
            PixelBar(value: Double(count - previous), total: Double(max(next - previous, 1)),
                     color: .carbs, overIsBad: false)
            Text("再記 \(next - count) 筆，解鎖「\(next) 筆」獎盃。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.px(24)).foregroundStyle(Color.brand).monospacedDigit()
            Text(label).font(.px(12)).foregroundStyle(Color.soft)
        }
    }

    private var trophyWindow: some View {
        let count = foods.count
        return PixelWindow(title: "獎盃") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(Self.milestones, id: \.self) { milestone in
                    let unlocked = count >= milestone
                    VStack(spacing: 4) {
                        if unlocked {
                            PixelSprite(art: .trophy, size: 32)
                        } else {
                            Text("?")
                                .font(.px(24))
                                .foregroundStyle(Color.soft)
                                .frame(width: 32, height: 32)
                        }
                        Text("\(milestone) 筆")
                            .font(.px(12))
                            .foregroundStyle(unlocked ? Color.ink : Color.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .pixelPanel(fill: unlocked ? .window : .track, shadow: nil, lineWidth: 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(milestone) 筆獎盃，\(unlocked ? "已解鎖" : "未解鎖")")
                }
            }
        }
    }

    private func dexWindow(_ list: [DexEntry]) -> some View {
        PixelWindow(title: "圖鑑") {
            HStack(spacing: 8) {
                ForEach(Order.allCases) { item in
                    Button(item.rawValue) { order = item }
                        .buttonStyle(.pixel(order == item ? .primary : .secondary, fontSize: 12))
                }
            }

            if list.isEmpty {
                Text("還沒有收集到食物。記錄第一餐，圖鑑就會出現 No.001！")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                    .padding(.vertical, 8)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 12) {
                ForEach(list) { entry in
                    Button { selected = entry } label: { tile(entry) }
                        .buttonStyle(.plain)
                }
                // 還沒發現的格子
                ForEach(0..<3, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text("No.\(String(format: "%03d", list.count + index + 1))")
                            .font(.px(12)).foregroundStyle(Color.soft)
                        Text("?").font(.px(32)).foregroundStyle(Color.track).frame(height: 48)
                        Text("？？？").font(.px(12)).foregroundStyle(Color.soft)
                        Text(" ").font(.px(12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private func tile(_ entry: DexEntry) -> some View {
        VStack(spacing: 4) {
            Text("No.\(String(format: "%03d", entry.number))")
                .font(.px(12))
                .foregroundStyle(Color.soft)
            StickerView(entry: entry.cover, size: 48)
            Text(entry.name)
                .font(.px(12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("×\(entry.entries.count)")
                .font(.px(12))
                .foregroundStyle(Color.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .pixelPanel(fill: .window, shadow: nil, lineWidth: 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 圖鑑裡一種食物的詳細資料（直接查資料庫，刪掉記錄後畫面會跟著更新）
struct DexDetailSheet: View {
    let number: Int
    let name: String
    @Query private var entries: [FoodEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FoodEntry?

    init(number: Int, name: String) {
        self.number = number
        self.name = name
        _entries = Query(filter: #Predicate<FoodEntry> { $0.name == name }, sort: \FoodEntry.date, order: .reverse)
    }

    var body: some View {
        let average = entries.sum(\.calories) / Double(max(entries.count, 1))
        let cover = entries.first { $0.stickerData != nil } ?? entries.first
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("No.\(String(format: "%03d", number))").font(.px(16)).foregroundStyle(Color.soft)
                    Spacer()
                    Button("關閉") { dismiss() }
                        .buttonStyle(.pixel(.secondary, fontSize: 12))
                }

                PixelWindow {
                    HStack(spacing: 16) {
                        Group {
                            if let cover {
                                StickerView(entry: cover, size: 96)
                            } else {
                                StickerView(stickerData: nil, emoji: FoodEmoji.guess(name: name), size: 96)
                            }
                        }
                        .padding(6)
                        .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name).font(.px(20))
                            Text("吃過 \(entries.count) 次").font(.px(12)).foregroundStyle(Color.soft)
                            Text("平均 \(average.rounded0) 大卡").font(.px(12)).foregroundStyle(Color.soft)
                            if let first = entries.last {
                                Text("發現於 \(first.date.formatted(.dateTime.year().month().day()))")
                                    .font(.px(12))
                                    .foregroundStyle(Color.soft)
                            }
                        }
                    }
                }

                PixelWindow(title: "記錄", spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, food in
                        if index > 0 { PixelDivider() }
                        Button { editing = food } label: {
                            HStack(spacing: 10) {
                                StickerView(entry: food, size: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(food.date.formatted(.dateTime.month().day().hour().minute()))
                                        .font(.px(12))
                                    Text("\(food.mealType.title) \(food.portion)")
                                        .font(.px(12))
                                        .foregroundStyle(Color.soft)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(food.calories.rounded0) 大卡").font(.px(12))
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.paper.ignoresSafeArea())
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .presentationDetents([.medium, .large])
        .sheet(item: $editing) { EditFoodView(entry: $0) }
    }
}
