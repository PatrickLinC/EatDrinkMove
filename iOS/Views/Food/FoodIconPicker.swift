import SwiftUI
import UIKit

/// 一格一格的 emoji 選擇（畫成像素圖）
struct EmojiGrid: View {
    let emojis: [String]
    var selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                let isSelected = emoji == selected
                Button { onSelect(emoji) } label: {
                    StickerView(stickerData: nil, emoji: emoji, size: 36)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .pixelPanel(fill: isSelected ? .track : .window, border: isSelected ? .brand : .ink,
                                    shadow: nil, lineWidth: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// 替食物換圖示：Apple 所有食物與飲料 emoji，有照片的話也可以改回照片做的像素圖
struct FoodIconPicker: View {
    enum Choice {
        case emoji(String)
        case photo
    }

    let current: String
    var photoAvailable = false
    var usingPhoto = false
    let onPick: (Choice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if photoAvailable {
                        PixelWindow(title: "照片") {
                            Button(usingPhoto ? "目前用的是照片做的像素圖" : "改回用照片做像素圖") {
                                onPick(.photo)
                                dismiss()
                            }
                            .buttonStyle(.pixel(usingPhoto ? .primary : .secondary, fullWidth: true))
                        }
                    }
                    ForEach(FoodEmoji.catalog) { group in
                        PixelWindow(title: group.title) {
                            EmojiGrid(emojis: group.emojis, selected: usingPhoto ? nil : current) { emoji in
                                onPick(.emoji(emoji))
                                dismiss()
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("換圖示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }
}

/// 表單裡的「圖示」列：顯示目前的像素圖，點了打開選擇器
struct FoodIconRow: View {
    let sticker: Data?
    let emoji: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StickerView(stickerData: sticker, emoji: emoji, size: 44)
                    .padding(4)
                    .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("換圖示").foregroundStyle(Color.ink)
                    Text("從所有食物 emoji 裡挑一個").font(.px(12)).foregroundStyle(Color.soft)
                }
                Spacer()
                PixelSprite(art: .cursor, size: 12)
            }
        }
    }
}

/// 頭像與小夥伴造型可以選的 emoji：職業與角色在前，後面接所有食物
enum AvatarEmoji {
    static let groups: [FoodEmoji.Group] = [
        FoodEmoji.Group(title: "勇者職業", emojis: ["🧙", "🧙‍♀️", "🧙‍♂️", "🤺", "🥷", "🧝", "🧝‍♀️", "🧝‍♂️", "🧚",
                                                "🧚‍♂️", "🧛", "🧛‍♀️", "🧜‍♀️", "🧜‍♂️", "🧞", "🧟", "🦸", "🦸‍♀️",
                                                "🦸‍♂️", "🦹", "🦹‍♀️", "🤴", "👸", "🫅", "💂", "🕵️"]),
        FoodEmoji.Group(title: "各行各業", emojis: ["🧑‍🍳", "👩‍🍳", "👨‍🍳", "🧑‍⚕️", "👩‍⚕️", "👨‍⚕️", "🧑‍🎓", "👩‍🎓",
                                                "👨‍🎓", "🧑‍🏫", "👩‍🏫", "👨‍🏫", "🧑‍💻", "👩‍💻", "👨‍💻", "🧑‍💼",
                                                "👩‍💼", "👨‍💼", "🧑‍🔬", "👩‍🔬", "👨‍🔬", "🧑‍🔧", "👩‍🔧", "🧑‍🏭",
                                                "🧑‍🌾", "👩‍🌾", "👨‍🌾", "🧑‍🎨", "👩‍🎨", "🧑‍🎤", "👩‍🎤", "👨‍🎤",
                                                "🧑‍✈️", "👩‍✈️", "🧑‍🚀", "👩‍🚀", "🧑‍🚒", "👩‍🚒", "👮", "👮‍♀️",
                                                "👷", "👷‍♀️", "🧑‍⚖️", "🕵️‍♀️", "💂‍♀️", "🧑‍🍼"]),
        FoodEmoji.Group(title: "運動員", emojis: ["🏃", "🏃‍♀️", "🚶", "🚶‍♀️", "🧘", "🧘‍♀️", "🏋️", "🏋️‍♀️",
                                               "🤸", "🤸‍♀️", "🚴", "🚴‍♀️", "🏊", "🏊‍♀️", "⛹️", "⛹️‍♀️", "🤾",
                                               "🧗", "🧗‍♀️", "🏄", "🏄‍♀️", "🤽", "🚣", "🏇", "⛷️", "🏂", "🤼", "🥋"]),
        FoodEmoji.Group(title: "動物夥伴", emojis: ["🐱", "🐶", "🐻", "🐼", "🐨", "🐰", "🦊", "🐸", "🐧", "🐹",
                                                "🐯", "🦁", "🐷", "🐮", "🐔", "🐤", "🦄", "🐉", "🐲", "🦖",
                                                "🐢", "🐙", "🐳", "🦉"]),
        FoodEmoji.Group(title: "其他", emojis: ["🤖", "👾", "👽", "👻", "🎃", "🌷", "🌻", "🌿", "🍀", "⭐️",
                                             "🌈", "🔥", "💎", "🎮"]),
    ] + FoodEmoji.catalog
}
