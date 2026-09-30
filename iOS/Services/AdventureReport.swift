import Foundation

// MARK: - AI 冒險軍師週報

/// 把最近的步數、睡眠、喝水、精神力、路線整理成文字給 AI。
/// 「數據關聯」在手機上先算好（例如睡滿 7 小時隔天走幾步），AI 只負責解讀，不會自己編數字。
@MainActor
enum AdventureReport {
    static let prompt = """
    你是「元氣大陸」的冒險軍師，說話溫暖、帶一點遊戲感，但內容務實。根據使用者最近的冒險紀錄（步數、睡眠、喝水、精神力、散步跑步），用繁體中文寫本週冒險週報：
    1. 【本週戰況】一兩句總結，先肯定做得好的地方。
    2. 【軍師發現】根據「數據關聯」列出 1 到 3 個發現。只能用提供的數字，不要自己編數字或推測病因；資料太少就說還要多觀察幾週。
    3. 【下週任務】3 個具體、做得到的小任務（例如「週三、週五晚上 11:30 前熄燈」）。
    4. 最後一句鼓勵。
    不超過 350 字，不要用表格，不做醫療診斷。某天數字特別低可能只是沒戴手錶或沒記錄，不要苛責。
    """

    private struct Day {
        let date: Date
        var steps: Double = 0
        var sleep: SleepNight?
        var water: Double = 0
        var calories: Double = 0
        var mp: Int?
        var breathed = false
        var routes: [SavedRoute] = []
    }

    static func summary() async -> String {
        let health = HealthKitManager.shared
        let today = Date.now.startOfDay
        let start = today.adding(days: -13)
        let steps = await health.dailySteps(from: start, to: .now)
        let nights = await health.allSleepNights(from: start, to: .now)
        let totals = LogService.shared.dayTotals(from: start, days: 14)
        let mp = StressStore.shared.history
        let breathing = StressStore.breathingDays()
        let routes = RouteStore.shared.routes.filter { $0.start >= start }

        let days: [Day] = (0..<14).map { offset in
            let date = start.adding(days: offset)
            var day = Day(date: date)
            day.steps = steps[date] ?? 0
            day.sleep = nights[date]
            day.water = totals[date]?.water ?? 0
            day.calories = totals[date]?.calories ?? 0
            day.mp = mp[date]
            day.breathed = breathing.contains(date.dayKey)
            day.routes = routes.filter { $0.start.startOfDay == date }
            return day
        }

        var lines = [
            "目標：每天 \(AppSettings.stepGoal.rounded0) 步、喝水 \(AppSettings.waterGoal.rounded0) ml。精神力 0–100，越高越放鬆（由手錶的心率變異度估算）。",
            "",
            "最近 7 天：",
        ]
        for day in days.suffix(7) {
            var parts = ["步數 \(day.steps.rounded0)"]
            if let night = day.sleep {
                let score = SleepScore.compute(night, recent: days.compactMap(\.sleep))
                parts.append("前一晚睡 \(night.hours.formatted(.number.precision(.fractionLength(1)))) 小時"
                             + "（\(night.start.formatted(date: .omitted, time: .shortened)) 睡著、睡眠分數 \(score.total)）")
            } else {
                parts.append("沒有睡眠資料")
            }
            parts.append("喝水 \(day.water.rounded0) ml")
            if day.calories > 0 { parts.append("攝取 \(day.calories.rounded0) kcal") }
            if let mp = day.mp { parts.append("精神力 \(mp)") }
            if day.breathed { parts.append("做了一分鐘呼吸") }
            if !day.routes.isEmpty {
                let meters = day.routes.reduce(0) { $0 + $1.distance }
                let time = day.routes.reduce(0) { $0 + $1.activeTime }
                parts.append("出發冒險 \(day.routes.count) 次、\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) 公里、"
                             + "配速 \(RouteStore.pace(seconds: time, meters: meters))")
            }
            lines.append("\(day.date.formatted(.dateTime.month().day().weekday()))：" + parts.joined(separator: "、"))
        }

        let findings = correlations(days)
        lines.append("")
        lines.append("數據關聯（最近 14 天，手機算好的）：")
        lines.append(contentsOf: findings.isEmpty ? ["資料還太少，看不出關聯。"] : findings.map { "- " + $0 })
        return lines.joined(separator: "\n")
    }

    /// 兩組都至少 2 天才列出來
    private static func correlations(_ days: [Day]) -> [String] {
        var result: [String] = []
        func average(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }

        let slept = days.filter { ($0.sleep?.hours ?? 0) >= 7 }
        let short = days.filter { $0.sleep != nil && ($0.sleep?.hours ?? 0) < 7 }
        if slept.count >= 2, short.count >= 2 {
            result.append("前一晚睡滿 7 小時的日子平均走 \(average(slept.map(\.steps)).rounded0) 步（\(slept.count) 天），"
                          + "沒睡滿的日子平均 \(average(short.map(\.steps)).rounded0) 步（\(short.count) 天）。")
            let sleptMP = slept.compactMap(\.mp).map(Double.init), shortMP = short.compactMap(\.mp).map(Double.init)
            if sleptMP.count >= 2, shortMP.count >= 2 {
                result.append("睡滿 7 小時的日子平均精神力 \(average(sleptMP).rounded0)，沒睡滿的日子 \(average(shortMP).rounded0)。")
            }
            let sleptRoutes = slept.flatMap(\.routes), shortRoutes = short.flatMap(\.routes)
            if sleptRoutes.count >= 2, shortRoutes.count >= 2 {
                func pace(_ routes: [SavedRoute]) -> String {
                    RouteStore.pace(seconds: routes.reduce(0) { $0 + $1.activeTime }, meters: routes.reduce(0) { $0 + $1.distance })
                }
                result.append("睡滿 7 小時後出發冒險的平均配速 \(pace(sleptRoutes))，沒睡滿時 \(pace(shortRoutes))。")
            }
        }

        let early = days.filter { $0.sleep?.isAsleep(before: 24 * 60) == true }
        let late = days.filter { $0.sleep != nil && $0.sleep?.isAsleep(before: 24 * 60) == false }
        if early.count >= 2, late.count >= 2 {
            result.append("午夜前睡著的隔天平均走 \(average(early.map(\.steps)).rounded0) 步，過了午夜才睡的隔天 \(average(late.map(\.steps)).rounded0) 步。")
        }

        let goal = AppSettings.waterGoal
        let watered = days.filter { goal > 0 && $0.water >= goal }.compactMap(\.mp).map(Double.init)
        let dry = days.filter { goal > 0 && $0.water > 0 && $0.water < goal }.compactMap(\.mp).map(Double.init)
        if watered.count >= 2, dry.count >= 2 {
            result.append("喝滿水的日子平均精神力 \(average(watered).rounded0)，沒喝滿的日子 \(average(dry).rounded0)。")
        }

        let breathed = days.filter(\.breathed).compactMap(\.mp).map(Double.init)
        let notBreathed = days.filter { !$0.breathed }.compactMap(\.mp).map(Double.init)
        if breathed.count >= 2, notBreathed.count >= 2 {
            result.append("有做一分鐘呼吸的日子平均精神力 \(average(breathed).rounded0)，沒做的日子 \(average(notBreathed).rounded0)。")
        }

        let active = days.filter { !$0.routes.isEmpty }
        let rest = days.filter { $0.routes.isEmpty && $0.steps > 0 }
        if active.count >= 2, rest.count >= 2 {
            let activeNext = active.compactMap { day in days.first { $0.date == day.date.adding(days: 1) }?.sleep?.hours }
            let restNext = rest.compactMap { day in days.first { $0.date == day.date.adding(days: 1) }?.sleep?.hours }
            if activeNext.count >= 2, restNext.count >= 2 {
                result.append("有出發冒險的那晚平均睡 \(average(activeNext).formatted(.number.precision(.fractionLength(1)))) 小時，"
                              + "沒出門的晚上 \(average(restNext).formatted(.number.precision(.fractionLength(1)))) 小時。")
            }
        }
        return result
    }
}
