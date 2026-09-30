import SwiftUI

/// 主畫面的 App 圖示：預設，或換成已經喚醒的精靈
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard, onigiri, boba, cat, dog, slime, dragon, unicorn, fox, pumpkin

    var id: String { rawValue }

    /// 資產目錄裡的名稱；預設圖示是 nil
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    var skin: CompanionSkin? { self == .standard ? nil : CompanionSkin(rawValue: rawValue) }

    var title: String { skin?.title ?? "預設" }

    /// 跟圖示一樣的底色（產生圖示時用的顏色）
    var background: Color {
        switch self {
        case .standard, .onigiri: Color(red: 173 / 255, green: 130 / 255, blue: 87 / 255)
        case .boba: Color(red: 97 / 255, green: 140 / 255, blue: 170 / 255)
        case .cat: Color(red: 130 / 255, green: 115 / 255, blue: 170 / 255)
        case .dog: Color(red: 110 / 255, green: 150 / 255, blue: 85 / 255)
        case .slime: Color(red: 185 / 255, green: 110 / 255, blue: 85 / 255)
        case .dragon: Color(red: 170 / 255, green: 85 / 255, blue: 70 / 255)
        case .unicorn: Color(red: 80 / 255, green: 130 / 255, blue: 175 / 255)
        case .fox: Color(red: 70 / 255, green: 130 / 255, blue: 130 / 255)
        case .pumpkin: Color(red: 110 / 255, green: 90 / 255, blue: 150 / 255)
        }
    }

    var isUnlocked: Bool { skin.map(SpiritCollection.isUnlocked) ?? true }

    static var current: AppIconChoice {
        allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .standard
    }

    static func choice(for skin: CompanionSkin) -> AppIconChoice? { allCases.first { $0.skin == skin } }
}

struct AppIconView: View {
    @State private var current = AppIconChoice.current
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PixelWindow(title: "App 圖示") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                        ForEach(AppIconChoice.allCases) { choice in
                            Button {
                                Task { await apply(choice) }
                            } label: {
                                VStack(spacing: 6) {
                                    AppIconPreview(choice: choice)
                                        .frame(width: 72, height: 72)
                                        .overlay {
                                            if current == choice {
                                                RoundedRectangle(cornerRadius: 17).strokeBorder(Color.brand, lineWidth: 3).padding(-4)
                                            }
                                        }
                                    Text(choice.isUnlocked ? choice.title : "？？？")
                                        .font(.px(12))
                                        .foregroundStyle(current == choice ? Color.brand : Color.soft)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(choice.isUnlocked)
                            .accessibilityLabel(choice.isUnlocked ? "\(choice.title)圖示" : "還沒解鎖的圖示")
                            .accessibilityAddTraits(current == choice ? .isSelected : [])
                        }
                    }
                    Text("喚醒精靈就能把主畫面的圖示換成牠。換的時候 iPhone 會跳出一個確認視窗，按「好」就好。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage {
                        Text(errorMessage).font(.px(12)).foregroundStyle(Color.danger)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.paper)
        .navigationTitle("App 圖示")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func apply(_ choice: AppIconChoice) async {
        guard choice != current, choice.isUnlocked else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.iconName)
            current = choice
            errorMessage = nil
        } catch {
            errorMessage = "換圖示失敗：\(error.localizedDescription)"
        }
    }
}

/// 圖示預覽（跟真正的圖示同一個樣子，用畫的）
struct AppIconPreview: View {
    let choice: AppIconChoice

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            VStack(spacing: 0) {
                ZStack {
                    choice.background
                    if let skin = choice.skin {
                        PixelSprite(art: skin.art, size: side * 0.56, tint: choice.isUnlocked ? nil : .track)
                    } else {
                        VStack(spacing: 1) {
                            Text("卡路里").foregroundStyle(Color(red: 1, green: 249 / 255, blue: 238 / 255))
                            Text("大作戰").foregroundStyle(Color(red: 245 / 255, green: 205 / 255, blue: 110 / 255))
                        }
                        .font(.px(side * 0.2))
                    }
                }
                .frame(height: side * 0.656)
                Rectangle().fill(Color(red: 76 / 255, green: 56 / 255, blue: 40 / 255)).frame(height: side * 0.03)
                ZStack {
                    Color(red: 246 / 255, green: 237 / 255, blue: 218 / 255)
                    if choice.skin == nil {
                        HStack(spacing: side * 0.06) {
                            PixelSprite(art: .bowl, size: side * 0.18)
                            PixelSprite(art: .drop, size: side * 0.18)
                            PixelSprite(art: .dumbbell, size: side * 0.18)
                        }
                    } else {
                        Text("卡路里大作戰")
                            .font(.px(side * 0.1))
                            .foregroundStyle(Color(red: 76 / 255, green: 56 / 255, blue: 40 / 255))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
            .overlay {
                if !choice.isUnlocked {
                    PixelSprite(art: .lock, size: side * 0.28)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
