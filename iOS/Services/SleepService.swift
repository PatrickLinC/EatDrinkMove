import Foundation
import HealthKit

/// 一晚的睡眠（算在起床那天）
struct SleepNight: Codable, Equatable {
    /// 入睡、起床
    var start: Date
    var end: Date
    /// 實際睡著的秒數（多個來源重疊的部分只算一次）
    var asleep: TimeInterval
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var awake: TimeInterval = 0
    /// 手動補記的只算半晚
    var isManual = false

    var hours: Double { asleep / 3600 }
    /// 成就計算用的份量：手錶記錄 1、手動補記 0.5
    var weight: Double { isManual ? 0.5 : 1 }

    /// 在某個時間前睡著（分鐘；午夜 = 1440。凌晨睡著的算成 24 點之後，例如 0:30 = 1470）
    func isAsleep(before minutes: Int) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        var clock = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if clock < 12 * 60 { clock += 24 * 60 }
        return clock < minutes
    }

    /// 起床時間是當天第幾分鐘
    var wakeMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: end)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// 沒戴手錶睡覺時手動補記的睡眠（key 是起床那天的 dayKey）
enum ManualSleepStore {
    private static let key = "manualSleep"

    static func all() -> [String: SleepNight] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let nights = try? JSONDecoder().decode([String: SleepNight].self, from: data) else { return [:] }
        return nights
    }

    static func save(start: Date, end: Date) {
        guard end > start else { return }
        var nights = all()
        nights[end.dayKey] = SleepNight(start: start, end: end, asleep: end.timeIntervalSince(start), isManual: true)
        if let data = try? JSONEncoder().encode(nights) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(dayKey: String) {
        var nights = all()
        nights[dayKey] = nil
        if let data = try? JSONEncoder().encode(nights) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension HealthKitManager {
    /// 每一晚的主要睡眠，key 是起床那天的 00:00。
    ///
    /// 傍晚 6 點到隔天中午 12 點之間的睡眠算同一晚（午睡不算）；中間醒來超過 2 小時就切成兩段，取睡最久的那段。
    func sleepNights(from start: Date, to end: Date) async -> [Date: SleepNight] {
        guard isAvailable, !needsAuthorization, start < end else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-6 * 3600), end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [:] }

        func stage(_ sample: HKCategorySample) -> HKCategoryValueSleepAnalysis? {
            HKCategoryValueSleepAnalysis(rawValue: sample.value)
        }
        let asleepValues: Set<HKCategoryValueSleepAnalysis> = [.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM]

        // 依「起床那天」分組：區間中點落在前一天 18:00 到當天 12:00 之間
        var byNight: [Date: [HKCategorySample]] = [:]
        for sample in samples {
            let middle = sample.startDate.addingTimeInterval(sample.endDate.timeIntervalSince(sample.startDate) / 2)
            let night = middle.addingTimeInterval(6 * 3600).startOfDay
            let windowStart = night.addingTimeInterval(-6 * 3600)
            let windowEnd = night.addingTimeInterval(12 * 3600)
            guard middle >= windowStart, middle < windowEnd, night >= start.startOfDay else { continue }
            byNight[night, default: []].append(sample)
        }

        var result: [Date: SleepNight] = [:]
        for (night, group) in byNight {
            let asleep = group.filter { stage($0).map(asleepValues.contains) ?? false }
            let clusters = Self.clusters(Self.union(asleep.map { ($0.startDate, $0.endDate) }), gap: 2 * 3600)
            guard let main = clusters.max(by: { Self.total($0) < Self.total($1) }),
                  let first = main.first, let last = main.last else { continue }
            let span = (first.0, last.1)
            func within(_ value: HKCategoryValueSleepAnalysis) -> TimeInterval {
                Self.total(Self.union(group.filter { stage($0) == value }.compactMap { Self.clip(($0.startDate, $0.endDate), to: span) }))
            }
            let asleepTime = Self.total(main)
            guard asleepTime >= 3600 else { continue }
            result[night] = SleepNight(start: span.0, end: span.1, asleep: asleepTime,
                                       deep: within(.asleepDeep), rem: within(.asleepREM), awake: within(.awake))
        }
        return result
    }

    /// 手錶的睡眠＋手動補記（同一晚兩個都有時用手錶的）
    func allSleepNights(from start: Date, to end: Date) async -> [Date: SleepNight] {
        var nights = await sleepNights(from: start, to: end)
        for manual in ManualSleepStore.all().values {
            let day = manual.end.startOfDay
            guard day >= start.startOfDay, day <= end, nights[day] == nil else { continue }
            nights[day] = manual
        }
        return nights
    }

    // MARK: 區間計算

    private static func union(_ ranges: [(Date, Date)]) -> [(Date, Date)] {
        var merged: [(Date, Date)] = []
        for range in ranges.sorted(by: { $0.0 < $1.0 }) where range.1 > range.0 {
            if let last = merged.last, range.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, range.1)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func clusters(_ ranges: [(Date, Date)], gap: TimeInterval) -> [[(Date, Date)]] {
        var result: [[(Date, Date)]] = []
        for range in ranges {
            if let last = result.last?.last, range.0.timeIntervalSince(last.1) <= gap {
                result[result.count - 1].append(range)
            } else {
                result.append([range])
            }
        }
        return result
    }

    private static func total(_ ranges: [(Date, Date)]) -> TimeInterval {
        ranges.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
    }

    private static func clip(_ range: (Date, Date), to span: (Date, Date)) -> (Date, Date)? {
        let clipped = (max(range.0, span.0), min(range.1, span.1))
        return clipped.1 > clipped.0 ? clipped : nil
    }
}
