import AppKit

/// 浮动窗口显示模式
enum FloatingDisplayMode: Int, CaseIterable {
    case standard
    case minimal

    var title: String {
        switch self {
        case .standard: String(localized: .floatingModeStandard)
        case .minimal: String(localized: .floatingModeMinimal)
        }
    }

    /// 窗口尺寸
    var windowSize: NSSize {
        self == .standard
            ? NSSize(width: FloatConst.floatWindowWidth, height: FloatConst.floatWindowHeight)
            : FloatingTheme.compactWindowSize
    }

    /// 头部总高：拖拽区 + 搜索框 + 分类胶囊
    var headerHeight: CGFloat {
        if self == .minimal {
            return FloatingTheme.compactHeaderHeight + FloatingTheme.compactSearchHeight
                + FloatingTheme.compactTabSpacing + FloatingTheme.tabBarHeight
                + FloatingTheme.tabsBottomGap
        }
        return FloatingTheme.dragHandleHeight
            + FloatingTheme.searchFieldHeight
            + FloatingTheme.searchToTabsSpacing
            + FloatingTheme.tabBarHeight
            + FloatingTheme.tabsBottomGap
    }

    /// 窗口圆角
    var windowRadius: CGFloat {
        self == .standard ? FloatingTheme.windowRadius : 22
    }

    var footerHeight: CGFloat { self == .standard ? FloatingTheme.footerHeight : 30 }
    var cardHeight: CGFloat { self == .standard ? FloatingTheme.rowHeight : 44 }
    var cardSpacing: CGFloat { self == .standard ? FloatingTheme.rowSpacing : 4 }
    var cardInset: CGFloat { FloatingTheme.horizontalPadding }
    var cardRadius: CGFloat { self == .standard ? FloatingTheme.rowRadius : 8 }
    var contentFont: NSFont { self == .standard ? FloatingTheme.rowTitleFont : FloatingTheme.compactRowFont }
    var contentLineHeight: CGFloat {
        self == .standard ? FloatingTheme.rowTitleLineHeight : FloatingTheme.compactRowLineHeight
    }
    var contentMaxLines: Int { self == .standard ? FloatingTheme.rowTitleMaxLines : 2 }
}
