import SwiftUI
import UIKit

// MARK: - 像素視窗

/// 有邊框、硬陰影的遊戲視窗，左上角可以掛一個標題牌
struct PixelWindow<Content: View>: View {
    var title: String?
    var tint: Color = .ink
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(.horizontal, 14)
            .padding(.top, title == nil ? 14 : 22)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelPanel()
            .overlay(alignment: .topLeading) {
                if let title {
                    PixelTag(text: title, fill: tint)
                        .offset(x: 12, y: -12)
                }
            }
            .padding(.top, title == nil ? 0 : 12)
            .padding(.trailing, 3) // 留給右下的陰影
    }
}

/// 視窗上的標題牌
struct PixelTag: View {
    let text: String
    var fill: Color = .ink
    var foreground: Color = .window
    var size: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.px(size))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Rectangle().fill(fill))
    }
}

/// 小標籤：「早」「連續 3 天」
struct PixelChip: View {
    let text: String
    var color: Color = .brand
    var filled = true

    var body: some View {
        Text(text)
            .font(.px(12))
            .foregroundStyle(filled ? Color.onBrand : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Rectangle().fill(filled ? color : Color.clear))
            .overlay(Rectangle().strokeBorder(color, lineWidth: filled ? 0 : 2))
    }
}

/// 舊的膠囊標籤，改成像素外框
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        PixelChip(text: text, color: color, filled: false)
    }
}

/// 虛線分隔
struct PixelDivider: View {
    var body: some View {
        DashLine()
            .stroke(Color.track, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            .frame(height: 2)
    }
}

struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// 分頁最上面的大標題
struct PixelPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.px(24)).foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle).font(.px(12)).foregroundStyle(Color.soft)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
    }
}

extension PixelPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 遊戲選單的一列：圖示、名稱、說明、游標箭頭
struct PixelMenuRow: View {
    let title: String
    var detail: String?
    var art: PixelArt?

    var body: some View {
        HStack(spacing: 10) {
            if let art { PixelSprite(art: art, size: 24) }
            Text(title).font(.px(16)).foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.px(12)).foregroundStyle(Color.soft).lineLimit(1)
            }
            PixelSprite(art: .cursor, size: 12)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// 三個方塊輪流亮，代表「處理中」
struct PixelLoadingDots: View {
    var color: Color = .brand

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let step = Int(timeline.date.timeIntervalSinceReferenceDate * 4) % 4
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(index < step ? color : Color.track)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .accessibilityLabel("處理中")
    }
}

// MARK: - 像素按鈕

/// 按下去時陰影消失、按鈕往右下沉，像實體按鍵
struct PixelButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary
        case tinted(Color)
    }

    var kind: Kind = .primary
    var fullWidth = false
    var fontSize: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        PixelButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth, fontSize: fontSize)
    }
}

private struct PixelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PixelButtonStyle.Kind
    let fullWidth: Bool
    let fontSize: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    private var fill: Color {
        switch kind {
        case .primary: .brand
        case .secondary: .window
        case .tinted(let color): color
        }
    }

    private var foreground: Color {
        switch kind {
        case .secondary: .ink
        default: .onBrand
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.px(fontSize))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background { PixelPanel(fill: fill, shadow: pressed ? nil : .pxShadow) }
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
            .padding(.trailing, 3)
            .padding(.bottom, 3)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PixelButtonStyle {
    static var pixel: PixelButtonStyle { PixelButtonStyle() }

    static func pixel(_ kind: PixelButtonStyle.Kind, fullWidth: Bool = false, fontSize: CGFloat = 16) -> PixelButtonStyle {
        PixelButtonStyle(kind: kind, fullWidth: fullWidth, fontSize: fontSize)
    }
}

// MARK: - 輸入框與表單

extension View {
    /// 像素外框的輸入框
    func pixelField() -> some View {
        font(.px(16))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background { PixelPanel(fill: .window, shadow: nil, lineWidth: 2) }
    }

    /// 系統表單換成像素背景與字體
    func pixelForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.paper)
            .font(.px(16))
    }

    /// 表單每一列的底色（放在 Section 或 Group 上）
    func pixelRows() -> some View {
        listRowBackground(Color.window)
    }
}

/// 導覽列、分段選擇器等系統元件也換成像素字體
enum PixelAppearance {
    static func configure() {
        let ink = PixelTheme.uiColor(\.ink)
        let paper = PixelTheme.uiColor(\.paper)
        let title = UIFont(name: PixelFont.name, size: 20) ?? .boldSystemFont(ofSize: 20)
        let large = UIFont(name: PixelFont.name, size: 32) ?? .boldSystemFont(ofSize: 32)
        let small = UIFont(name: PixelFont.name, size: 12) ?? .systemFont(ofSize: 12)

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = paper
        bar.shadowColor = .clear
        bar.titleTextAttributes = [.font: title, .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar

        UISegmentedControl.appearance().setTitleTextAttributes([.font: small], for: .normal)
    }
}

// MARK: - 食物像素圖

/// 食物貼紙：有照片去背就做成像素圖，沒有就把 emoji 縮成像素圖
struct StickerView: View {
    var stickerData: Data?
    var emoji: String
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image = Pixelator.sprite(data: stickerData, emoji: emoji) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(emoji.isEmpty ? FoodEmoji.fallback : emoji)
                    .font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension StickerView {
    init(entry: FoodEntry, size: CGFloat = 64) {
        self.init(stickerData: entry.stickerData, emoji: entry.emoji, size: size)
    }
}

/// 把圖片縮成低解析度、限制顏色、加深色外框，做成 8-bit 風的小圖
enum Pixelator {
    private static let cache = NSCache<NSString, UIImage>()
    /// 外框顏色（深可可色，固定不隨配色變，像遊戲道具圖）
    private static let outline: (UInt8, UInt8, UInt8) = (0x3B, 0x2A, 0x1E)

    static func sprite(data: Data?, emoji: String) -> UIImage? {
        if let data {
            let key = "d\(data.count)-\(data.prefix(64).hashValue)-\(data.suffix(64).hashValue)" as NSString
            if let cached = cache.object(forKey: key) { return cached }
            guard let image = UIImage(data: data), let result = pixelate(image, grid: 32) else { return nil }
            cache.setObject(result, forKey: key)
            return result
        }
        let symbol = emoji.isEmpty ? FoodEmoji.fallback : emoji
        let key = "e\(symbol)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = renderEmoji(symbol), let result = pixelate(image, grid: 24) else { return nil }
        cache.setObject(result, forKey: key)
        return result
    }

    private static func renderEmoji(_ emoji: String) -> UIImage? {
        let side: CGFloat = 96
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 76)])
            let bounds = text.size()
            text.draw(at: CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2))
        }
        return trimmed(image)
    }

    /// 裁掉四周的透明邊，讓 emoji 撐滿格子
    private static func trimmed(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return image }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cropped = cgImage.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return image }
        return UIImage(cgImage: cropped)
    }

    static func pixelate(_ image: UIImage, grid: Int) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let size = grid
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: space, bitmapInfo: info) else { return false }
            context.interpolationQuality = .high
            // 四周留一格給外框
            let inner = CGFloat(size - 2)
            let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
            let scale = inner / max(w, h)
            let drawSize = CGSize(width: w * scale, height: h * scale)
            context.draw(cgImage, in: CGRect(x: (CGFloat(size) - drawSize.width) / 2,
                                             y: (CGFloat(size) - drawSize.height) / 2,
                                             width: drawSize.width, height: drawSize.height))
            return true
        }
        guard drawn else { return nil }

        // 透明度只留全有或全無；顏色每個頻道壓成 8 階
        var solid = [Bool](repeating: false, count: size * size)
        for index in 0..<(size * size) {
            let base = index * 4
            let alpha = pixels[base + 3]
            if alpha >= 110 {
                solid[index] = true
                for channel in 0..<3 {
                    let value = Double(pixels[base + channel]) * 255 / Double(alpha)
                    let level = (min(value, 255) / 255 * 7).rounded() / 7 * 255
                    pixels[base + channel] = UInt8(level)
                }
                pixels[base + 3] = 255
            } else {
                pixels[base] = 0; pixels[base + 1] = 0; pixels[base + 2] = 0; pixels[base + 3] = 0
            }
        }

        // 透明格子旁邊有實心格子，就畫成外框
        for y in 0..<size {
            for x in 0..<size where !solid[y * size + x] {
                let touches = (x > 0 && solid[y * size + x - 1]) || (x < size - 1 && solid[y * size + x + 1])
                    || (y > 0 && solid[(y - 1) * size + x]) || (y < size - 1 && solid[(y + 1) * size + x])
                guard touches else { continue }
                let base = (y * size + x) * 4
                pixels[base] = outline.0; pixels[base + 1] = outline.1; pixels[base + 2] = outline.2
                pixels[base + 3] = 255
            }
        }

        return pixels.withUnsafeMutableBytes { buffer -> UIImage? in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: space, bitmapInfo: info),
                  let output = context.makeImage() else { return nil }
            return UIImage(cgImage: output)
        }
    }
}

// MARK: - 其他元件

/// 可輸入小數的數字欄位
struct NumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit)
                .foregroundStyle(Color.soft)
                .frame(width: 38, alignment: .leading)
        }
    }
}

extension Binding where Value == Int {
    /// 把「午夜起算分鐘數」轉成 DatePicker 用的時間
    var timeOfDay: Binding<Date> {
        Binding<Date>(
            get: { Date.at(minutes: wrappedValue) },
            set: { wrappedValue = $0.minutesSinceMidnight }
        )
    }
}

extension UIImage {
    /// 縮小照片並轉正方向：送給 AI 用 1568px，縮圖 480px，貼紙 640px
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension || imageOrientation != .up else { return self }
        let scale = min(1, maxDimension / longest)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
