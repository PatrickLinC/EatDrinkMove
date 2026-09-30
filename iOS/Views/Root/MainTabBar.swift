import SwiftUI

/// 底部導覽列：今日、營地、足跡、圖鑑、戰績、角色
struct PixelTabBar: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        HStack(spacing: 6) {
            item(.today, title: "今日", art: .home)
            item(.camp, title: "營地", art: .campTent)
            item(.footprints, title: "足跡", art: .footprint)
            item(.dex, title: "圖鑑", art: .book)
            item(.records, title: "戰績", art: .trophy)
            item(.hero, title: "角色", art: .hero)
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 4)
        .background(Color.window.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ink).frame(height: 3)
        }
    }

    private func item(_ tab: AppTab, title: String, art: PixelArt) -> some View {
        let selected = router.selectedTab == tab
        return Button {
            router.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                PixelSprite(art: art, size: 24)
                    .opacity(selected ? 1 : 0.45)
                Text(title)
                    .font(.px(12))
                    .foregroundStyle(selected ? Color.ink : Color.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    PixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 首頁「吃東西」跳出的指令選單
struct EatCommandSheet: View {
    var onChoose: (AddFoodRequest.Start) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PixelWindow(title: "吃了什麼？", spacing: 0) {
                command(.camera, "拍照辨識", detail: "拍完可以補充說明", art: .camera)
                PixelDivider()
                command(.library, "從相簿選照片", detail: nil, art: .photo)
                PixelDivider()
                command(.label, "讀營養標示", detail: "包裝食品", art: .label)
                PixelDivider()
                command(.none, "搜尋食物", detail: "台灣營養資料庫", art: .search)
                PixelDivider()
                command(.describe, "用說的或打字", detail: "AI 估算", art: .star)
            }
            Text("會記在「\(MealType.suggested().title)」，進去之後可以改。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.paper.ignoresSafeArea())
        .presentationDetents([.height(430)])
        .presentationCornerRadius(0)
    }

    private func command(_ start: AddFoodRequest.Start, _ title: String, detail: String?, art: PixelArt) -> some View {
        Button { onChoose(start) } label: {
            PixelMenuRow(title: title, detail: detail, art: art)
        }
        .buttonStyle(.plain)
    }
}
