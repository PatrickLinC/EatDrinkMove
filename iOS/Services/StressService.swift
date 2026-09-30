import Foundation
import HealthKit

/// 壓力等級（精神力 MP = 100 − 壓力分數）
enum StressLevel {
    case relaxed, steady, tense, overloaded

    init(stress: Int) {
        switch stress {
        case ..<30: self = .relaxed
        case ..<55: self = .steady
        case ..<75: self = .tense
        default: self = .overloaded
        }
    }

    var title: String {
        switch self {
        case .relaxed: "放鬆"
        case .steady: "平穩"
        case .tense: "緊繃"
        case .overloaded: "爆表"
        }
    }

    /// 緊繃以上會出現焦慮霧
    var summonsFog: Bool { self == .tense || self == .overloaded }

    var advice: String {
        switch self {
        case .relaxed: "身體很放鬆，今天適合挑戰多走一點。"
        case .steady: "狀態平穩，照平常的步調就好。"
        case .tense: "身體有點緊繃，可能是累了或沒睡好。做一分鐘呼吸、早點休息，想吃零食時先喝杯水。"
        case .overloaded: "壓力很大的一天。先深呼吸一分鐘，今天對自己好一點，不用硬撐運動量，吃得規律最重要。"
        }
    }
}

/// 今天的壓力判讀：心率變異度（HRV）和靜止心率，都跟自己過去 30 天的基準比
struct StressReading: Equatable {
    var hrv: Double
    var hrvBaseline: Double
    var restingHeartRate: Double?
    var restingBaseline: Double?
    var stress: Int
    var measuredAt: Date

    var mp: Int { 100 - stress }
    var level: StressLevel { StressLevel(stress: stress) }
}

/// 壓力監測、焦慮霧、一分鐘呼吸
@MainActor
final class StressStore: ObservableObject {
    static let shared = StressStore()

    /// 至少幾天的資料才建立基準
    static let baselineDaysNeeded = 7

    @Published private(set) var reading: StressReading?
    /// 已經有幾天的 HRV 資料（還沒滿 7 天時顯示「建立基準中」）
    @Published private(set) var baselineDays = 0
    /// 最近 7 天每天的精神力（沒資料的天不列）
    @Published private(set) var history: [Date: Int] = [:]
    @Published var showBreathing = false

    private static let calmDayKey = "calmBreathingDay"
    /// 做過一分鐘呼吸的日子、精神力 60 以上的日子（dayKey，喚醒靜心塔的精靈用）
    private static let breathingDaysKey = "breathingDays"
    private static let calmDaysKey = "calmDays"
    static let calmThreshold = 60

    nonisolated static func breathingDays() -> Set<String> {
        // 舊版只記得最後一次呼吸的日子，也算進來
        var days = Set(UserDefaults.standard.stringArray(forKey: breathingDaysKey) ?? [])
        if let last = UserDefaults.standard.string(forKey: calmDayKey) { days.insert(last) }
        return days
    }

    nonisolated static func calmDays() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: calmDaysKey) ?? [])
    }

    private static func remember(_ keys: [String], in key: String) {
        let merged = Set(UserDefaults.standard.stringArray(forKey: key) ?? []).union(keys)
        UserDefaults.standard.set(Array(merged.sorted().suffix(800)), forKey: key)
    }

    /// 今天做過一分鐘呼吸（焦慮霧已經散了）
    var calmedToday: Bool { UserDefaults.standard.string(forKey: Self.calmDayKey) == Date.now.dayKey }

    /// 今天有焦慮霧
    var fogActive: Bool { (reading?.level.summonsFog ?? false) && !calmedToday }

    func refresh() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-seedStress"), index + 1 < arguments.count, let stress = Int(arguments[index + 1]) {
            reading = StressReading(hrv: 38, hrvBaseline: 52, restingHeartRate: 66, restingBaseline: 60, stress: stress, measuredAt: .now)
            baselineDays = 24
            history = Dictionary(uniqueKeysWithValues: (0..<7).map { (Date.now.adding(days: -$0).startOfDay, [100 - stress, 62, 71, 58, 80, 66, 74][$0]) })
            showBreathing = arguments.contains("-breathing")
            return
        }
        #endif
        let health = HealthKitManager.shared
        let start = Date.now.adding(days: -30).startOfDay
        let hrvSamples = await health.quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start)
        let restingSamples = await health.quantitySamples(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: start)

        let today = Date.now.startOfDay
        let hrvByDay = Self.dailyMeans(hrvSamples)
        let restingByDay = Self.dailyMeans(restingSamples)
        let pastHRV = hrvByDay.filter { $0.key < today }.map(\.value)
        baselineDays = pastHRV.count

        // 今天：最近 24 小時的平均
        let cutoff = Date.now.addingTimeInterval(-24 * 3600)
        let recentHRV = hrvSamples.filter { $0.date >= cutoff }.map(\.value)
        guard pastHRV.count >= Self.baselineDaysNeeded, !recentHRV.isEmpty else {
            reading = nil
            history = [:]
            return
        }
        let baseline = Self.median(pastHRV)
        let spread = max(Self.robustSpread(pastHRV), 5)
        let pastResting = restingByDay.filter { $0.key < today }.map(\.value)
        let restingBaseline = pastResting.count >= Self.baselineDaysNeeded ? Self.median(pastResting) : nil
        let recentResting = restingSamples.filter { $0.date >= cutoff }.last?.value

        func stress(hrv: Double, resting: Double?) -> Int {
            let hrvStress = 50 + (baseline - hrv) / spread * 20
            var value = hrvStress
            if let resting, let restingBaseline {
                value = hrvStress * 0.7 + (50 + (resting - restingBaseline) * 6) * 0.3
            }
            return Int(min(max(value, 0), 100).rounded())
        }

        let hrvToday = recentHRV.reduce(0, +) / Double(recentHRV.count)
        reading = StressReading(hrv: hrvToday, hrvBaseline: baseline, restingHeartRate: recentResting,
                                restingBaseline: restingBaseline, stress: stress(hrv: hrvToday, resting: recentResting),
                                measuredAt: hrvSamples.last?.date ?? .now)
        // 最近 7 天每天的精神力
        var days: [Date: Int] = [:]
        for offset in 0..<7 {
            let day = today.adding(days: -offset)
            if let hrv = hrvByDay[day] {
                days[day] = 100 - stress(hrv: hrv, resting: restingByDay[day])
            }
        }
        history = days
        Self.remember(days.filter { $0.value >= Self.calmThreshold }.map(\.key.dayKey), in: Self.calmDaysKey)
    }

    /// 做完一分鐘呼吸：焦慮霧散去、寫進「健康」的正念分鐘、一天一次 +2 元氣幣
    func finishBreathing(start: Date, end: Date) async -> Int {
        let first = !calmedToday
        UserDefaults.standard.set(Date.now.dayKey, forKey: Self.calmDayKey)
        Self.remember([Date.now.dayKey], in: Self.breathingDaysKey)
        objectWillChange.send()
        await HealthKitManager.shared.saveMindfulSession(start: start, end: end)
        guard first else { return 0 }
        AdventureStore.shared.addBonus(2, source: .calm)
        return 2
    }

    // MARK: 計算

    private static func dailyMeans(_ samples: [(date: Date, value: Double)]) -> [Date: Double] {
        var groups: [Date: [Double]] = [:]
        for sample in samples { groups[sample.date.startOfDay, default: []].append(sample.value) }
        return groups.mapValues { $0.reduce(0, +) / Double($0.count) }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// 中位數絕對離差 × 1.4826（比標準差不怕極端值）
    private static func robustSpread(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) }) * 1.4826
    }
}

extension HealthKitManager {
    /// 某種數值從某天起的所有樣本（時間、數值），依時間排序
    func quantitySamples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> [(date: Date, value: Double)] {
        guard isAvailable, !needsAuthorization else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    /// 呼吸練習寫進「健康」的正念分鐘
    func saveMindfulSession(start: Date, end: Date) async {
        guard isAvailable, end > start else { return }
        let sample = HKCategorySample(type: HKCategoryType(.mindfulSession), value: HKCategoryValue.notApplicable.rawValue,
                                      start: start, end: end)
        _ = try? await store.save(sample)
    }
}
