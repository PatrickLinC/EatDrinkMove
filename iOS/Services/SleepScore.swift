import Foundation

/// 睡眠分數（0–100）：時長 35、規律 20、效率 15、深層＋快速動眼 15、入睡時間 15
struct SleepScore: Equatable {
    var duration: Int
    var regularity: Int
    var efficiency: Int
    var stages: Int
    var bedtime: Int
    /// 手動補記或最近資料太少，有些項目是用預設值估的
    var isEstimated: Bool

    var total: Int { duration + regularity + efficiency + stages + bedtime }

    var rating: String {
        switch total {
        case 90...: "極佳"
        case 75..<90: "良好"
        case 60..<75: "普通"
        default: "不足"
        }
    }

    /// 各項目（名稱、得分、滿分）
    var parts: [(title: String, value: Int, max: Int)] {
        [("時長", duration, 35), ("規律", regularity, 20), ("效率", efficiency, 15),
         ("深眠與快速動眼", stages, 15), ("入睡時間", bedtime, 15)]
    }

    /// recent 是最近幾晚（含這一晚），用來算規律
    static func compute(_ night: SleepNight, recent: [SleepNight]) -> SleepScore {
        let hours = night.hours
        let duration: Double
        switch hours {
        case 7...9: duration = 35
        case ..<7: duration = max(0, (hours - 4) / 3 * 35)
        default: duration = max(20, 35 - (hours - 9) * 15)
        }

        // 規律：最近幾晚入睡、起床時間的標準差，30 分鐘以內滿分，2 小時以上 0 分
        var estimated = night.isManual
        let regularity: Double
        if recent.count >= 3 {
            let spread = (standardDeviation(recent.map { Double($0.bedMinutesFromNoon) })
                          + standardDeviation(recent.map { Double($0.wakeMinutes) })) / 2
            regularity = 20 * clamp((120 - spread) / 90)
        } else {
            regularity = 15
            estimated = true
        }

        let span = night.end.timeIntervalSince(night.start)
        let efficiency: Double
        if night.isManual || span <= 0 {
            efficiency = 12
        } else {
            efficiency = 15 * clamp((night.asleep / span - 0.75) / 0.15)
        }

        let stages: Double
        if night.deep + night.rem <= 0 {
            stages = 10
            estimated = true
        } else {
            stages = min(night.deep / night.asleep / 0.13, 1) * 7.5 + min(night.rem / night.asleep / 0.20, 1) * 7.5
        }

        // 23:00 前睡著滿分，凌晨 2 點以後 0 分
        let bedtime = 15 * clamp(Double(14 * 60 - night.bedMinutesFromNoon) / 180)

        return SleepScore(duration: Int(duration.rounded()), regularity: Int(regularity.rounded()),
                          efficiency: Int(efficiency.rounded()), stages: Int(stages.rounded()),
                          bedtime: Int(bedtime.rounded()), isEstimated: estimated)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
}

/// 依睡眠中點判斷的作息類型
enum Chronotype {
    case earlyBird, middle, nightOwl

    var title: String {
        switch self {
        case .earlyBird: "早鳥型"
        case .middle: "中間型"
        case .nightOwl: "夜貓型"
        }
    }

    var advice: String {
        switch self {
        case .earlyBird: "早上精神最好，重要的事和運動可以排在上午。"
        case .middle: "作息很平均，保持固定的上床時間就好。"
        case .nightOwl: "晚睡的日子宵夜比較容易失控，晚上 9 點後先喝水、吃清淡一點。"
        }
    }

    /// 最近幾晚的平均睡眠中點：凌晨 3 點前早鳥、4 點半後夜貓
    static func from(_ nights: [SleepNight]) -> Chronotype? {
        guard nights.count >= 3 else { return nil }
        let middle = nights.map { Double($0.bedMinutesFromNoon) + $0.end.timeIntervalSince($0.start) / 120 }
            .reduce(0, +) / Double(nights.count)
        switch middle {
        case ..<(15 * 60): return .earlyBird
        case ..<(16 * 60 + 30): return .middle
        default: return .nightOwl
        }
    }
}

extension SleepNight {
    /// 入睡時間：從前一天中午起算幾分鐘（23:00 = 660、凌晨 1:00 = 780）
    var bedMinutesFromNoon: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0) + 12 * 60) % (24 * 60)
    }
}
