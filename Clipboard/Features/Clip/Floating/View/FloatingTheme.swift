//
//  FloatingTheme.swift
//  Clipboard
//
//  浮动窗口新版视觉令牌：统一间距、圆角、字号与语义色，避免样式散落在各个视图里。
//

import AppKit

/// 浮动窗口统一视觉令牌
enum FloatingTheme {
    // MARK: - 间距

    /// 窗口内容横向内边距
    static let horizontalPadding: CGFloat = 14

    // MARK: - 尺寸

    /// 拖拽区高度
    static let dragHandleHeight: CGFloat = 30
    /// 搜索框高度
    static let searchFieldHeight: CGFloat = 36
    /// 搜索框与分类行的间距
    static let searchToTabsSpacing: CGFloat = 16
    /// 分类行高度
    static let tabBarHeight: CGFloat = 28
    /// 分类行底部与第一张卡片的间距
    static let tabsBottomGap: CGFloat = 14
    /// 列表不再使用时间分组标题
    static let sectionHeaderHeight: CGFloat = 0
    /// 列表行高度（可容纳最多三行内容）
    static let rowHeight: CGFloat = 72
    /// 列表行之间的间距
    static let rowSpacing: CGFloat = 12
    /// 图片标签使用单列大图，留出完整预览区域与独立信息栏。
    static let imageCardSpacing: CGFloat = 16
    static let imageCardPadding: CGFloat = 12
    static let imagePreviewInset: CGFloat = 8
    static let imageMinPreviewHeight: CGFloat = 144
    static let imageMaxPreviewHeight: CGFloat = 300
    static let imageDefaultPreviewHeight: CGFloat = 220
    static let imageCardFooterHeight: CGFloat = 44
    /// 行内图标尺寸
    static let rowIconSize: CGFloat = 32
    /// 右侧时间列固定宽度，保证各行正文右缘对齐
    static let rowMetaWidth: CGFloat = 60
    /// 卡片内部边距与图文间距
    static let rowPadding: CGFloat = 10
    static let iconToContentSpacing: CGFloat = 14
    static let contentToMetaSpacing: CGFloat = 10
    /// 链接标记在来源图标与标题之间独立排列
    static let linkSymbolSize: CGFloat = 20
    static let linkSymbolSpacing: CGFloat = 10
    /// 顶部按钮与搜索框之间的留白
    static let headerButtonSize: CGFloat = 32
    static let headerControlSpacing: CGFloat = 14
    /// 外窗与底部状态栏尺寸
    static let windowRadius: CGFloat = 30
    static let footerHeight: CGFloat = 40
    static let minimumWindowSize = NSSize(width: 340, height: 480)
    static let compactWindowSize = NSSize(width: 300, height: 560)
    static let compactHeaderHeight: CGFloat = 18
    static let compactSearchHeight: CGFloat = 30
    static let compactTabSpacing: CGFloat = 8

    // MARK: - 圆角

    /// 搜索框圆角
    static let searchFieldRadius: CGFloat = 18
    /// 列表行圆角
    static let rowRadius: CGFloat = 20
    static let selectionBorderWidth: CGFloat = 2.5
    /// 键帽圆角
    static let keyCapRadius: CGFloat = 4

    // MARK: - 字体

    /// 列表行内容字体
    static let rowTitleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let compactRowFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let compactRowLineHeight: CGFloat = 16
    /// 列表行内容行高（多行排版用）
    static let rowTitleLineHeight: CGFloat = 16
    /// 列表行内容最多显示行数
    static let rowTitleMaxLines = 3
    /// 时间戳字体
    static let timestampFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let searchFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let linkTitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let linkAddressFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let footerFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    /// 分组标题字体
    static let sectionHeaderFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// 分类胶囊字体
    static let tabFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    // MARK: - 语义色

    /// 根据图片比例和卡片宽度计算行高，限制超长截图高度并保留呼吸空间。
    static func imageCardHeight(for imageSize: CGSize?, width: CGFloat) -> CGFloat {
        let contentWidth = max(1, width - (imageCardPadding + imagePreviewInset) * 2)
        let previewHeight: CGFloat
        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            previewHeight = contentWidth * imageSize.height / imageSize.width + imagePreviewInset * 2
        } else {
            previewHeight = imageDefaultPreviewHeight
        }
        let boundedHeight = min(max(previewHeight, imageMinPreviewHeight), imageMaxPreviewHeight)
        return ceil(imageCardPadding + boundedHeight + imageCardFooterHeight)
    }

    /// 搜索框填充底色
    static func searchFieldBackground() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(white: 1, alpha: 0.16)
                : NSColor(white: 1, alpha: 0.42)
        }
    }

    /// 列表行默认底色（压在玻璃上的深色卡片）
    static func rowBackground() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.07, green: 0.08, blue: 0.12, alpha: 0.52)
                : NSColor(white: 1, alpha: 0.64)
        }
    }

    /// 行 hover 底色
    static func rowHoverBackground() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.12, green: 0.14, blue: 0.20, alpha: 0.62)
                : NSColor(white: 1, alpha: 0.82)
        }
    }

    /// 选中项使用较通透的底色，让蓝色轮廓清晰呈现
    static func selectedRowBackground() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.10, green: 0.14, blue: 0.22, alpha: 0.25)
                : NSColor(white: 1, alpha: 0.38)
        }
    }

    /// 选中行使用参考图的蓝色轮廓
    static var rowAccentColor: NSColor {
        .systemBlue
    }

    /// 玻璃叠色随系统明暗外观变化，保留桌面透射
    static func glassTint() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.25, green: 0.31, blue: 0.46, alpha: 0.16)
                : NSColor(srgbRed: 0.85, green: 0.89, blue: 0.98, alpha: 0.12)
        }
    }

    /// 行内图标容器底色
    static func rowIconBackground() -> NSColor {
        NSColor.labelColor.withAlphaComponent(0.11)
    }

    /// 分隔线颜色
    static func divider() -> NSColor {
        NSColor.labelColor.withAlphaComponent(0.09)
    }

    /// 键帽底色
    static func keyCapBackground() -> NSColor {
        NSColor.labelColor.withAlphaComponent(0.12)
    }
}
