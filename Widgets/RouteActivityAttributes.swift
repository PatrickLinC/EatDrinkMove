import ActivityKit
import Foundation

/// 出發冒險時在鎖定畫面、動態島顯示的資料（App 和小工具共用）
struct RouteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 公尺
        var distance: Double
        /// 扣掉暫停後的「虛擬開始時間」，計時器從這裡往上數
        var timerStart: Date
        /// 暫停或結束時固定顯示的秒數；nil 表示正在走
        var frozenElapsed: TimeInterval?
        /// 平均配速（每公里）
        var pace: String
        var finished = false
    }

    /// RouteKind 的 rawValue：walk、brisk、run
    var kind: String
    /// 散步、快走、跑步
    var title: String
    /// 帶著的精靈（CompanionSkin 的 rawValue）
    var companion: String
    var shiny: Bool
}
