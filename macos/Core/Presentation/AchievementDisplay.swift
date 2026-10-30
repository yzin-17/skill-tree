import Foundation

public enum AchievementDisplay {
    public static func eventSummary(_ event: ActivityRecord) -> String {
        switch event.type {
        case "career.created": return replacingPrefix("创建职业阶段", with: "创建成长阶段", in: event.summary)
        case "career.updated": return replacingPrefix("更新职业阶段", with: "更新成长阶段", in: event.summary)
        case "career.transitioned": return replacingPrefix("确认职业转职", with: "进入成长阶段", in: event.summary)
        default: return event.summary
        }
    }
    private static func replacingPrefix(_ prefix: String, with replacement: String, in value: String) -> String {
        value.hasPrefix(prefix) ? replacement + value.dropFirst(prefix.count) : value
    }
    public static func message(_ value: String) -> String {
        let replacements = [
            "路径和职业标识不同。": "路径和阶段标识不同。",
            "相同职业标识的内容不同。": "相同阶段标识的内容不同。",
            "职业配置已变化，请刷新。": "阶段配置已变化，请刷新。",
            "职业阶段不能形成循环。": "成长阶段不能形成循环。",
            "转职标识、版本或当前职业无效。": "阶段操作标识、版本或当前阶段无效。",
            "职业条件已变化，请刷新后确认。": "阶段条件已变化，请刷新后确认。",
            "职业条件或前一阶段尚未满足。": "阶段条件或前一阶段尚未满足。",
            "当前职业已变化，请刷新后确认。": "当前阶段已变化，请刷新后确认。",
            "这已经是当前职业。": "这已经是当前阶段。"
        ]
        return replacements[value] ?? value
    }
}
