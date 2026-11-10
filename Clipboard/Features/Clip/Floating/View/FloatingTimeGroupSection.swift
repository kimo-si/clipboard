//
//  FloatingTimeGroupSection.swift
//  Clipboard
//
//  浮动窗口列表的时间分组：把条目按「今天 / 昨天 / 更早」分段并统计条数。
//

import Foundation

// MARK: - FloatingTimeGroup

/// 时间分组类型
enum FloatingTimeGroup: Int, CaseIterable {
    case today
    case yesterday
    case earlier

    /// 分组标题文案
    var title: String {
        switch self {
        case .today: String(localized: .today)
        case .yesterday: String(localized: .yesterday)
        case .earlier: String(localized: .earlier)
        }
    }
}

// MARK: - FloatingTimeGroupSection

/// 一个时间分组及其条目
struct FloatingTimeGroupSection {
    /// 分组类型
    let group: FloatingTimeGroup
    /// 该分组内的条目
    var items: [PasteboardModel]

    /// 分组标题右侧的条数文案
    var countText: String {
        String(localized: .itemCount(items.count))
    }
}

// MARK: - Section Builder

/// 时间分组构建器
enum FloatingTimeGroupBuilder {
    /// 按时间倒序把条目切分为「今天 / 昨天 / 更早」三段
    /// - Parameters:
    ///   - items: 已按时间倒序排列的条目
    ///   - referenceDate: 判定「今天」的基准时间
    ///   - calendar: 使用的日历
    /// - Returns: 仅包含非空分组的段列表
    static func build(
        items: [PasteboardModel],
        referenceDate: Date = TimeManager.shared.currentTime,
        calendar: Calendar = .current
    ) -> [FloatingTimeGroupSection] {
        var buckets: [FloatingTimeGroup: [PasteboardModel]] = [:]

        // 逐条按日期归入对应分组，保持原有倒序
        for item in items {
            let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp))
            let group = group(for: date, referenceDate: referenceDate, calendar: calendar)
            buckets[group, default: []].append(item)
        }

        return FloatingTimeGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return FloatingTimeGroupSection(group: group, items: items)
        }
    }

    /// 判断某个时间点属于哪个分组
    private static func group(
        for date: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> FloatingTimeGroup {
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return .today
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) else {
            return .earlier
        }
        if calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .earlier
    }
}
