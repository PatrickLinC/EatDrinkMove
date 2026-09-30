import SwiftUI
import UIKit

/// 編輯或刪除已記錄的食物
struct EditFoodView: View {
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FoodDraft
    @State private var meal: MealType
    @State private var date: Date
    @State private var confirmDelete = false
    // 圖示
    @State private var icon: LogService.IconChoice = .auto
    @State private var iconEmoji: String
    @State private var iconSticker: Data?
    @State private var showIconPicker = false

    init(entry: FoodEntry) {
        self.entry = entry
        _draft = State(initialValue: FoodDraft(entry: entry))
        _meal = State(initialValue: entry.mealType)
        _date = State(initialValue: entry.date)
        _iconEmoji = State(initialValue: entry.emoji)
        _iconSticker = State(initialValue: entry.stickerData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button { showIconPicker = true } label: {
                            StickerView(stickerData: iconSticker, emoji: iconEmoji, size: 96)
                                .padding(6)
                                .pixelPanel(fill: .window, shadow: nil, lineWidth: 2)
                                .overlay(alignment: .bottomTrailing) {
                                    PixelTag(text: "換", fill: .brand, foreground: .onBrand, size: 12)
                                        .offset(x: 6, y: 6)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("換圖示")
                        if let data = entry.photoData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 108, height: 108)
                                .clipped()
                                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Group {
                Section {
                    TextField("名稱", text: $draft.name)
                    TextField("份量", text: $draft.portion)
                    Picker("餐別", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("時間", selection: $date)
                } footer: {
                    Text("點左上的圖示可以換成任何食物 emoji。AI 認錯的話直接改名稱，沒有照片的圖示也會跟著更新。").font(.px(12))
                }
                Section {
                    NumberField(title: "熱量", unit: "kcal", value: $draft.calories)
                    NumberField(title: "蛋白質", unit: "g", value: $draft.protein)
                    NumberField(title: "碳水化合物", unit: "g", value: $draft.carbs)
                    NumberField(title: "脂肪", unit: "g", value: $draft.fat)
                    NumberField(title: "糖", unit: "g", value: $draft.sugar)
                    NumberField(title: "鈉", unit: "mg", value: $draft.sodium)
                } header: {
                    Text("營養").font(.px(12))
                }
                Section {
                    Button("刪除這一項", role: .destructive) { confirmDelete = true }
                }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("修改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        LogService.shared.update(entry, with: draft, meal: meal, date: date, icon: icon)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                FoodIconPicker(current: iconEmoji, photoAvailable: entry.photoData != nil,
                               usingPhoto: iconSticker != nil) { choice in
                    pickIcon(choice)
                }
            }
            .confirmationDialog("確定要刪除嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    LogService.shared.delete(entry)
                    dismiss()
                }
            }
        }
    }

    private func pickIcon(_ choice: FoodIconPicker.Choice) {
        switch choice {
        case .emoji(let emoji):
            iconEmoji = emoji
            iconSticker = nil
            icon = .emoji(emoji)
        case .photo:
            if let original = entry.stickerData {
                iconSticker = original
                iconEmoji = entry.emoji
                icon = .auto
            } else if let data = entry.photoData, let image = UIImage(data: data) {
                Task { @MainActor in
                    guard let sticker = await StickerMaker.makeSticker(from: image) else { return }
                    iconSticker = sticker
                    icon = .photo(sticker)
                }
            }
        }
    }
}
