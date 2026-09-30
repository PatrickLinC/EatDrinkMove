import Foundation
import SwiftUI

// MARK: - 節慶活動

/// 每年固定回來的節慶：活動期間做到某個健康習慣就能喚醒節慶精靈，營地也能蓋限定裝飾。
/// 錯過了隔年還會再來，不製造「錯過就沒了」的焦慮。
enum Festival: String, CaseIterable, Identifiable {
    case newYear, dragonBoat, summer, midAutumn, halloween, christmas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newYear: "過年"
        case .dragonBoat: "端午節"
        case .summer: "夏日祭"
        case .midAutumn: "中秋節"
        case .halloween: "萬聖節"
        case .christmas: "聖誕節"
        }
    }

    /// 活動期間的說法（農曆節日寫農曆）
    var period: String {
        switch self {
        case .newYear: "除夕到初六"
        case .dragonBoat: "農曆五月初三到初七"
        case .summer: "7/25–7/31"
        case .midAutumn: "農曆八月十二到十六"
        case .halloween: "10/25–10/31"
        case .christmas: "12/19–12/25"
        }
    }

    var spirit: CompanionSkin {
        switch self {
        case .newYear: .nian
        case .dragonBoat: .zongzi
        case .summer: .goldfish
        case .midAutumn: .rabbit
        case .halloween: .pumpkin
        case .christmas: .snowman
        }
    }

    var habit: FestivalHabit {
        switch self {
        case .newYear: .steps(6000)
        case .dragonBoat: .steps(8000)
        case .summer: .water
        case .midAutumn: .sleep(hours: 7)
        case .halloween: .earlySleep(before: 24 * 60, hours: 6)
        case .christmas: .steps(8000)
        }
    }

    /// 喚醒要幾天、閃光要幾天（活動 5 天的是全勤，7 天的可以漏一天）
    var days: Int { 3 }
    var shinyDays: Int { length == 5 ? 5 : 6 }

    /// 限定裝飾
    var decorationTitle: String {
        switch self {
        case .newYear: "紅燈籠"
        case .dragonBoat: "龍舟"
        case .summer: "刨冰攤"
        case .midAutumn: "大柚子"
        case .halloween: "稻草人"
        case .christmas: "聖誕樹"
        }
    }

    var decorationArt: PixelArt {
        switch self {
        case .newYear: .festivalLantern
        case .dragonBoat: .festivalBoat
        case .summer: .festivalIce
        case .midAutumn: .festivalPomelo
        case .halloween: .festivalScarecrow
        case .christmas: .festivalTree
        }
    }

    /// 裝飾只有活動期間能蓋，蓋了就一直留在營地
    var decorationCost: Int { 30 }

    var greeting: String {
        switch self {
        case .newYear: "新年快樂！年獸寶寶在營地外探頭探腦，過年也要記得出門走走。"
        case .dragonBoat: "端午節到了！划龍舟要體力，這幾天多走一點吧。"
        case .summer: "夏日祭開始了！天氣熱，記得把水喝夠。"
        case .midAutumn: "中秋節快樂！玉兔說，賞完月早點睡，明天才有精神。"
        case .halloween: "萬聖節！熬夜的人會被當成幽靈，早點睡才不會被抓走。"
        case .christmas: "聖誕節快到了！小雪人想看你在雪地裡走出一長串腳印。"
        }
    }

    private var length: Int {
        switch self {
        case .newYear, .summer, .halloween, .christmas: 7
        case .dragonBoat, .midAutumn: 5
        }
    }

    // MARK: 日期

    /// 某一年的活動期間（從第一天 0:00 到最後一天結束）
    func window(year: Int) -> DateInterval? {
        let calendar = Calendar.current
        let first: Date?
        switch self {
        case .newYear: first = Self.lunar(year: year, month: 1, day: 1)?.adding(days: -1)
        case .dragonBoat: first = Self.lunar(year: year, month: 5, day: 3)
        case .summer: first = calendar.date(from: DateComponents(year: year, month: 7, day: 25))
        case .midAutumn: first = Self.lunar(year: year, month: 8, day: 12)
        case .halloween: first = calendar.date(from: DateComponents(year: year, month: 10, day: 25))
        case .christmas: first = calendar.date(from: DateComponents(year: year, month: 12, day: 19))
        }
        guard let first = first?.startOfDay else { return nil }
        return DateInterval(start: first, end: first.adding(days: length))
    }

    /// 正在進行，或下一次的活動期間
    func upcoming(from date: Date = .now) -> DateInterval? {
        let year = Calendar.current.component(.year, from: date)
        return [year, year + 1].compactMap { window(year: $0) }.first { $0.end > date }
    }

    func isActive(on date: Date = .now) -> Bool { upcoming(from: date)?.contains(date) ?? false }

    /// 今天正在進行的節慶
    static func active(on date: Date = .now) -> Festival? {
        #if DEBUG
        // 開發用：-festival halloween 假裝節慶進行中
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-festival"), index + 1 < arguments.count {
            return Festival(rawValue: arguments[index + 1])
        }
        #endif
        return allCases.first { $0.isActive(on: date) }
    }

    /// 某段期間內所有年份的活動期間（算喚醒進度用）
    func windows(from start: Date, to end: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let first = calendar.component(.year, from: start), last = calendar.component(.year, from: end)
        return (first...max(first, last)).compactMap { window(year: $0) }.filter { $0.end > start && $0.start <= end }
    }

    // MARK: 農曆

    private static var lunarCache: [String: Date] = [:]

    /// 農曆某月某日在這個西元年的日期（過年在 1–2 月，端午、中秋也都在同一個西元年）
    static func lunar(year: Int, month: Int, day: Int) -> Date? {
        let key = "\(year)-\(month)-\(day)"
        if let cached = lunarCache[key] { return cached }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = .current
        guard var date = gregorian.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
        for _ in 0..<366 {
            let components = chinese.dateComponents([.month, .day], from: date)
            if components.month == month, components.day == day, components.isLeapMonth != true {
                lunarCache[key] = date
                return date
            }
            date = gregorian.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return nil
    }
}

/// 節慶期間要做到的事
enum FestivalHabit {
    case steps(Double)
    case water
    case sleep(hours: Double)
    case earlySleep(before: Int, hours: Double)

    var text: String {
        switch self {
        case .steps(let steps): "走滿 \(steps.formatted()) 步"
        case .water: "喝滿每日喝水目標"
        case .sleep(let hours): "睡滿 \(hours.formatted()) 小時"
        case .earlySleep(let before, let hours): "在 \(SpiritRequirement.clock(before)) 前睡著、睡滿 \(hours.formatted()) 小時"
        }
    }

    /// 活動期間的單位（睡眠算「晚」）
    var unit: String {
        switch self {
        case .sleep, .earlySleep: "晚"
        default: "天"
        }
    }
}
