import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - 8-bit 配色

/// 一套配色裡的所有顏色（0xRRGGBB）
struct PixelShades {
    /// 背景
    var paper: UInt32
    /// 視窗底色
    var window: UInt32
    /// 邊框與主要文字
    var ink: UInt32
    /// 次要文字
    var soft: UInt32
    /// 進度條的空格
    var track: UInt32
    /// 視窗右下的硬陰影
    var shadow: UInt32
    var brand: UInt32
    /// 主色上的文字
    var onBrand: UInt32
    var calorie: UInt32
    var water: UInt32
    var move: UInt32
    var protein: UInt32
    var carbs: UInt32
    var fat: UInt32
    var sodium: UInt32
    var danger: UInt32
}

/// 三套 8-bit 配色，在「角色 › 偏好設定」切換
enum PixelPalette: String, CaseIterable, Identifiable {
    case milkTea, handheld, arcade

    static let storageKey = "pixelPalette"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milkTea: "奶茶像素"
        case .handheld: "經典掌機綠"
        case .arcade: "夜間街機"
        }
    }

    static var current: PixelPalette {
        PixelPalette(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .milkTea
    }

    /// 街機配色只有深色版
    var forcesDark: Bool { self == .arcade }

    var light: PixelShades {
        switch self {
        case .milkTea:
            PixelShades(paper: 0xF3E9D2, window: 0xFFF8EA, ink: 0x3B2A1E, soft: 0x7A6450, track: 0xE4D3B4,
                        shadow: 0x3B2A1E, brand: 0x9C6F45, onBrand: 0xFFF8EA, calorie: 0xD9824B,
                        water: 0x4F8FBF, move: 0x6E9A4E, protein: 0xB5573C, carbs: 0xD2A03C,
                        fat: 0x8C7BB5, sodium: 0x7D8796, danger: 0xC0392B)
        case .handheld:
            PixelShades(paper: 0xC4CFA1, window: 0xDCE4BC, ink: 0x1F2E1A, soft: 0x4E6040, track: 0xB3BE8E,
                        shadow: 0x1F2E1A, brand: 0x3F5A2E, onBrand: 0xDCE4BC, calorie: 0x2F4A26,
                        water: 0x5E7D45, move: 0x86A064, protein: 0x2F4A26, carbs: 0x5E7D45,
                        fat: 0x86A064, sodium: 0x4E6040, danger: 0x7A2E1F)
        case .arcade:
            dark
        }
    }

    var dark: PixelShades {
        switch self {
        case .milkTea:
            PixelShades(paper: 0x241A13, window: 0x33261C, ink: 0xF1E4CC, soft: 0xB9A184, track: 0x4A3928,
                        shadow: 0x0F0A07, brand: 0xC8976A, onBrand: 0x241A13, calorie: 0xE8945A,
                        water: 0x6CAAD8, move: 0x8DBB6B, protein: 0xD27358, carbs: 0xE2B452,
                        fat: 0xA594CE, sodium: 0x9AA3B0, danger: 0xE0604F)
        case .handheld:
            PixelShades(paper: 0x1B2616, window: 0x263420, ink: 0xC4CFA1, soft: 0x8FA077, track: 0x3A4A30,
                        shadow: 0x0B1208, brand: 0x9BB36E, onBrand: 0x1B2616, calorie: 0xC4CFA1,
                        water: 0x9BB36E, move: 0x7A9458, protein: 0xB5C58A, carbs: 0x9BB36E,
                        fat: 0x7A9458, sodium: 0x8FA077, danger: 0xD9826B)
        case .arcade:
            PixelShades(paper: 0x1B1B2F, window: 0x26264A, ink: 0xF2E6C9, soft: 0xA9A3C4, track: 0x3A3A63,
                        shadow: 0x0B0B16, brand: 0xF2B33D, onBrand: 0x1B1B2F, calorie: 0xF26B3A,
                        water: 0x3AB8F2, move: 0x7ED957, protein: 0xE85D4A, carbs: 0xF2B33D,
                        fat: 0xB38CF2, sodium: 0xA9A3C4, danger: 0xFF5A5A)
        }
    }
}

enum PixelTheme {
    /// iPhone 依目前配色與深淺色模式即時取色；手錶固定用奶茶深色
    static func color(_ key: KeyPath<PixelShades, UInt32>) -> Color {
        #if os(iOS)
        // 同一種顏色重複用同一個物件：每次都新建的話，SwiftUI 會把「主色換成白色」當成沒變，按鈕選取狀態不會重畫
        if let cached = cache[key] { return cached }
        let color = Color(uiColor: uiColor(key))
        cache[key] = color
        return color
        #else
        Color(hex: PixelPalette.milkTea.dark[keyPath: key])
        #endif
    }

    #if os(iOS)
    private static var cache: [KeyPath<PixelShades, UInt32>: Color] = [:]
    #endif

    #if os(iOS)
    static func uiColor(_ key: KeyPath<PixelShades, UInt32>) -> UIColor {
        UIColor { traits in
            let palette = PixelPalette.current
            let dark = traits.userInterfaceStyle == .dark || palette.forcesDark
            return UIColor(hex: (dark ? palette.dark : palette.light)[keyPath: key])
        }
    }
    #endif
}

extension Color {
    static var paper: Color { PixelTheme.color(\.paper) }
    static var window: Color { PixelTheme.color(\.window) }
    static var ink: Color { PixelTheme.color(\.ink) }
    static var soft: Color { PixelTheme.color(\.soft) }
    static var track: Color { PixelTheme.color(\.track) }
    static var pxShadow: Color { PixelTheme.color(\.shadow) }
    static var brand: Color { PixelTheme.color(\.brand) }
    static var onBrand: Color { PixelTheme.color(\.onBrand) }
    static var calorie: Color { PixelTheme.color(\.calorie) }
    static var water: Color { PixelTheme.color(\.water) }
    static var move: Color { PixelTheme.color(\.move) }
    static var protein: Color { PixelTheme.color(\.protein) }
    static var carbs: Color { PixelTheme.color(\.carbs) }
    static var fat: Color { PixelTheme.color(\.fat) }
    static var sodium: Color { PixelTheme.color(\.sodium) }
    static var danger: Color { PixelTheme.color(\.danger) }

    /// 舊名稱，設定頁等表單還在用
    static var appBackground: Color { paper }
    static var cardBackground: Color { window }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#if os(iOS)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

// MARK: - 名稱

enum AppBrand {
    /// App 顯示名稱（主畫面上的名字在 project.yml 的 CFBundleDisplayName）
    static let name = "卡路里大作戰"
    static let subtitle = "CALORIE WARS"
}

// MARK: - 像素字體

enum PixelFont {
    /// 俐方體 11 號（Cubic 11，OFL 授權），每個字是 12×12 格
    static let name = "Cubic_11"
}

extension Font {
    /// 像素字體。字級用 4 的倍數（12、16、20、24、32…），在 iPhone 的 3 倍螢幕上每一格都對齊，不會糊
    static func px(_ size: CGFloat) -> Font {
        .custom(PixelFont.name, fixedSize: size)
    }
}

// MARK: - 共用小工具

extension Double {
    /// 四捨五入成整數；NaN 或無限大時回傳 0，避免當機
    var rounded0: Int { isFinite ? Int(rounded()) : 0 }
}

extension Sequence {
    func sum(_ value: (Element) -> Double) -> Double {
        reduce(0) { $0 + value($1) }
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// 例如 "20260924"，用來當作每日的識別字串
    var dayKey: String { DateFormatter.dayKey.string(from: self) }

    /// 從午夜起算的分鐘數
    var minutesSinceMidnight: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 某一天的某個時間（以午夜起算的分鐘數表示）
    static func at(minutes: Int, on day: Date = .now) -> Date {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        return Calendar.current.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day) ?? day
    }
}

extension DateFormatter {
    static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
