import SwiftUI

// MARK: - 小夥伴的樣子

extension CompanionStyle {
    /// 動物風格對應的造型
    var animalSkin: CompanionSkin? {
        switch self {
        case .cat: .cat
        case .dog: .dog
        case .bird: .parrot
        default: nil
        }
    }
}

/// 目前的造型：自己挑的優先；沒挑過時，動物風格用動物、其他用飯糰精靈（都要已經喚醒）
enum CompanionLook {
    case sprite(CompanionSkin)
    case emoji(String)

    static let emojiPrefix = "emoji:"

    /// 只會回傳已經喚醒的精靈（emoji 造型要收集 5 隻後才能用）
    static func current(skin: String, style: String) -> CompanionLook {
        if skin.hasPrefix(emojiPrefix), SpiritCollection.emojiSkinsUnlocked {
            let emoji = String(skin.dropFirst(emojiPrefix.count))
            if !emoji.isEmpty { return .emoji(emoji) }
        }
        if let preset = CompanionSkin(rawValue: skin), SpiritCollection.isUnlocked(preset) { return .sprite(preset) }
        if let animal = CompanionStyle(rawValue: style)?.animalSkin, SpiritCollection.isUnlocked(animal) { return .sprite(animal) }
        return .sprite(.onigiri)
    }
}

/// 小夥伴本人：會上下跳、會眨眼；閃光版旁邊有星光閃爍
struct CompanionAvatar: View {
    var size: CGFloat = 48
    var animated = true
    /// 指定造型（設定頁預覽用）；nil 表示用目前的設定
    var look: CompanionLook?
    /// 指定是不是閃光版；nil 表示用目前的設定
    var shiny: Bool?
    @AppStorage(SettingKey.companionStyle) private var style = CompanionStyle.motivating.rawValue
    @AppStorage(SettingKey.companionSkin) private var skin = ""
    @AppStorage(SettingKey.companionShiny) private var shinySetting = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 2)
            let bob: CGFloat = animated && tick % 2 == 0 ? -2 : 0
            let blink = animated && tick % 8 == 0
            Group {
                switch look ?? CompanionLook.current(skin: skin, style: style) {
                case .sprite(let preset):
                    let isShiny = shiny ?? (shinySetting && SpiritCollection.isShinyUnlocked(preset))
                    PixelSprite(art: preset.art(shiny: isShiny, blink: blink), size: size)
                        .overlay { if isShiny { ShinySparkles(size: size, tick: animated ? tick : 1) } }
                case .emoji(let emoji):
                    StickerView(stickerData: nil, emoji: emoji, size: size)
                }
            }
            .offset(y: bob)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 浮在畫面上的小夥伴

/// 可以拖到任何高度，放開後貼齊左邊或右邊；點一下聊天，長按可以隱藏
struct CompanionFloat: View {
    @ObservedObject private var store = CompanionStore.shared
    @AppStorage(SettingKey.companionOnRight) private var onRight = true
    @AppStorage(SettingKey.companionY) private var yRatio = 0.72
    @AppStorage(SettingKey.companionEnabled) private var enabled = true
    @AppStorage(SettingKey.companionName) private var name = "小卡"
    @State private var drag: CGSize = .zero
    @State private var showChat = false

    private let size: CGFloat = 56
    private let bubbleWidth: CGFloat = 220

    var body: some View {
        GeometryReader { geometry in
            let x = onRight ? geometry.size.width - size / 2 - 10 : size / 2 + 10
            let y = min(max(geometry.size.height * yRatio, size), geometry.size.height - size / 2 - 8)
            let point = CGPoint(x: x + drag.width, y: y + drag.height)

            if let bubble = store.bubble, drag == .zero {
                bubbleView(bubble)
                    .frame(width: bubbleWidth, alignment: onRight ? .trailing : .leading)
                    .position(x: onRight ? point.x - size / 2 - 6 - bubbleWidth / 2 : point.x + size / 2 + 6 + bubbleWidth / 2,
                              y: point.y - 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // 不加框，只有角色本身；硬陰影讓它在任何背景上都看得到
            CompanionAvatar(size: size)
                .shadow(color: Color.pxShadow.opacity(0.35), radius: 0, x: 2, y: 3)
                .contentShape(Rectangle())
                .position(point)
                .onTapGesture { showChat = true }
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            onRight = x + value.translation.width > geometry.size.width / 2
                            yRatio = min(max((y + value.translation.height) / max(geometry.size.height, 1), 0.08), 0.95)
                            drag = .zero
                        }
                )
                .contextMenu {
                    Button("跟\(name)聊天") { showChat = true }
                    Button("先隱藏小夥伴", role: .destructive) { enabled = false }
                }
                .accessibilityElement()
                .accessibilityLabel("AI 小夥伴\(name)")
                .accessibilityHint("點兩下聊天")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showChat = true }
        }
        .sheet(isPresented: $showChat) { CompanionChatView() }
    }

    private func bubbleView(_ text: String) -> some View {
        Text(text)
            .font(.px(12))
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .background { PixelPanel(fill: .window, shadow: .pxShadow, lineWidth: 2) }
            .onTapGesture {
                store.bubble = nil
                showChat = true
            }
    }
}

// MARK: - 聊天

struct CompanionChatView: View {
    @ObservedObject private var store = CompanionStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.companionName) private var name = "小卡"
    @AppStorage(SettingKey.companionStyle) private var styleRaw = CompanionStyle.motivating.rawValue
    @State private var input = ""
    @State private var showSettings = false

    private var style: CompanionStyle { CompanionStyle(rawValue: styleRaw) ?? .motivating }

    private var quickPrompts: [String] {
        style.isAnimal
            ? ["摸摸頭", "要吃東西嗎？", "陪我散步", "今天好累"]
            : ["給我打打氣", "晚餐吃什麼好？", "今天吃得怎樣？", "好想吃宵夜…", "怎麼多喝點水？"]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        PixelWindow {
                            HStack(spacing: 12) {
                                CompanionAvatar(size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name).font(.px(20))
                                    Text("回話風格：\(style.title)").font(.px(12)).foregroundStyle(Color.soft)
                                }
                            }
                        }
                        // 招呼跟著目前的名字與風格即時產生
                        bubble(CompanionMessage(role: .companion, text: store.greeting()))
                        ForEach(store.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if store.isThinking {
                            HStack(spacing: 8) {
                                CompanionAvatar(size: 32, animated: false)
                                PixelLoadingDots()
                                    .padding(10)
                                    .background { PixelPanel(fill: .window, shadow: nil, lineWidth: 2) }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: store.messages.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: store.isThinking) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .background(Color.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("設定") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    CompanionSettingsView(showsChatButton: false)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showSettings = false }
                            }
                        }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }

    @ViewBuilder private func bubble(_ message: CompanionMessage) -> some View {
        switch message.role {
        case .companion:
            HStack(alignment: .top, spacing: 8) {
                CompanionAvatar(size: 32, animated: false)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background { PixelPanel(fill: .window, shadow: nil, lineWidth: 2) }
                Spacer(minLength: 36)
            }
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(message.text)
                    .foregroundStyle(Color.onBrand)
                    .textSelection(.enabled)
                    .padding(10)
                    .background { PixelPanel(fill: .brand, shadow: nil, lineWidth: 2) }
            }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        Button(prompt) { store.send(prompt) }
                            .buttonStyle(.pixel(.secondary, fontSize: 12))
                            .disabled(store.isThinking)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("跟\(name)說話…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .pixelField()
                Button("送出") {
                    store.send(input)
                    input = ""
                }
                .buttonStyle(.pixel(.primary))
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isThinking)
            }
            DictationButton(text: $input)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.window.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.ink).frame(height: 3) }
    }
}

// MARK: - 設定

struct CompanionSettingsView: View {
    var showsChatButton = true
    @ObservedObject private var store = CompanionStore.shared
    @AppStorage(SettingKey.companionEnabled) private var enabled = true
    @AppStorage(SettingKey.companionTips) private var tips = true
    @AppStorage(SettingKey.companionName) private var name = "小卡"
    @AppStorage(SettingKey.companionStyle) private var style = CompanionStyle.motivating.rawValue
    @AppStorage(SettingKey.companionSkin) private var skin = ""
    @AppStorage(SettingKey.companionShiny) private var shiny = false
    @ObservedObject private var collection = SpiritCollection.shared
    @State private var confirmClear = false
    @State private var showChat = false
    @State private var showMoreSkins = false

    private var currentLook: CompanionLook { CompanionLook.current(skin: skin, style: style) }

    private func skinCell(_ preset: CompanionSkin) -> some View {
        let unlocked = SpiritCollection.isUnlocked(preset)
        let selected: Bool = {
            if case .sprite(let current) = currentLook { return current == preset }
            return false
        }()
        return Button {
            skin = preset.rawValue
            shiny = false
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    CompanionAvatar(size: 44, animated: selected, look: .sprite(preset),
                                    shiny: selected && shiny && SpiritCollection.isShinyUnlocked(preset))
                } else {
                    PixelSprite(art: preset.art, size: 44, tint: .track)
                        .overlay { PixelSprite(art: .lock, size: 16) }
                }
                Text(unlocked ? preset.title : "？？？").font(.px(12)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .pixelPanel(fill: selected ? .track : (unlocked ? .window : .paper), border: selected ? .brand : .ink,
                        shadow: nil, lineWidth: 2)
        }
        .buttonStyle(.plain)
        // 不用 disabled：系統會再調暗一次，跟圖鑑的剪影不一致
        .allowsHitTesting(unlocked)
        .accessibilityLabel(unlocked ? preset.title : "還沒喚醒的精靈")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PixelWindow(title: "小夥伴") {
                    HStack(spacing: 12) {
                        CompanionAvatar(size: 56)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("名字").font(.px(12)).foregroundStyle(Color.soft)
                            TextField("小卡", text: $name).pixelField()
                        }
                    }
                    Toggle("顯示在畫面上", isOn: $enabled)
                    Toggle("主動冒泡提示", isOn: $tips)
                        .disabled(!enabled)
                    Text("拖曳小夥伴可以換位置，長按可以快速隱藏。隱藏後還是可以從這裡聊天。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                    if showsChatButton {
                        Button("跟\(name.isEmpty ? "小卡" : name)聊天") { showChat = true }
                            .buttonStyle(.pixel(.primary, fullWidth: true))
                    }
                }

                PixelWindow(title: "造型") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(CompanionSkin.dexOrder) { preset in
                            skinCell(preset)
                        }
                    }
                    Text("精靈要在「圖鑑」達成條件才會醒來，目前 \(collection.unlockedTotal)／\(CompanionSkin.dexOrder.count) 隻。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                    if case .sprite(let current) = currentLook, SpiritCollection.isShinyUnlocked(current) {
                        Toggle("用閃光版", isOn: $shiny)
                    }
                    HStack(spacing: 10) {
                        if case .emoji(let emoji) = currentLook {
                            StickerView(stickerData: nil, emoji: emoji, size: 32)
                                .padding(4)
                                .pixelPanel(fill: .track, border: .brand, shadow: nil, lineWidth: 2)
                        }
                        Button(SpiritCollection.emojiSkinsUnlocked
                               ? "更多造型（動物、職業、食物…）"
                               : "更多造型：喚醒 \(SpiritCollection.emojiSkinUnlockCount) 隻精靈後開放") { showMoreSkins = true }
                            .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                            .disabled(!SpiritCollection.emojiSkinsUnlocked)
                    }
                }

                PixelWindow(title: "回話風格", spacing: 0) {
                    ForEach(Array(CompanionStyle.allCases.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { PixelDivider() }
                        let selected = style == item.rawValue
                        let locked = !SpiritCollection.isStyleUnlocked(item)
                        Button {
                            style = item.rawValue
                            // 選動物風格時，造型也跟著換成那隻動物（之後還可以再改）
                            if let animal = item.animalSkin {
                                skin = animal.rawValue
                                shiny = false
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Rectangle()
                                    .fill(selected ? Color.brand : Color.window)
                                    .frame(width: 14, height: 14)
                                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                    if locked, let animal = item.animalSkin {
                                        Text("喚醒「\(animal.title)」後學會").font(.px(12)).foregroundStyle(Color.soft)
                                    } else {
                                        Text("「\(item.sample)」").font(.px(12)).foregroundStyle(Color.soft)
                                    }
                                }
                                Spacer(minLength: 0)
                                if locked { PixelSprite(art: .lock, size: 16) }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .opacity(locked ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(!locked)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                PixelWindow(title: "聊天紀錄") {
                    Text("共 \(store.messages.count) 則，只存在這支 iPhone。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                    Button("清除聊天紀錄") { confirmClear = true }
                        .buttonStyle(.pixel(.secondary, fullWidth: true))
                        .disabled(store.messages.isEmpty)
                }
            }
            .padding(16)
        }
        .background(Color.paper)
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .navigationTitle("AI 小夥伴")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showChat) { CompanionChatView() }
        .sheet(isPresented: $showMoreSkins) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(AvatarEmoji.groups) { group in
                            PixelWindow(title: group.title) {
                                EmojiGrid(emojis: group.emojis, selected: {
                                    if case .emoji(let current) = currentLook { return current }
                                    return nil
                                }()) { emoji in
                                    skin = CompanionLook.emojiPrefix + emoji
                                    showMoreSkins = false
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color.paper)
                .navigationTitle("更多造型")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showMoreSkins = false }
                    }
                }
            }
            .font(.px(16))
            .foregroundStyle(Color.ink)
        }
        .confirmationDialog("要清除所有聊天紀錄嗎？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) { store.clear() }
        }
    }
}

/// 閃光版旁邊輪流亮起的小星星
struct ShinySparkles: View {
    let size: CGFloat
    let tick: Int

    private static let sparkle = PixelArt([
        "..k..",
        ".kyk.",
        "kywyk",
        ".kyk.",
        "..k..",
    ])

    var body: some View {
        let star = max(size * 0.28, 8)
        ZStack {
            PixelSprite(art: Self.sparkle, size: star)
                .opacity(tick % 3 == 0 ? 0 : 1)
                .position(x: size * 0.1, y: size * 0.14)
            PixelSprite(art: Self.sparkle, size: star * 0.8)
                .opacity(tick % 3 == 1 ? 0 : 1)
                .position(x: size * 0.92, y: size * 0.34)
            PixelSprite(art: Self.sparkle, size: star * 0.7)
                .opacity(tick % 3 == 2 ? 0 : 1)
                .position(x: size * 0.18, y: size * 0.86)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
