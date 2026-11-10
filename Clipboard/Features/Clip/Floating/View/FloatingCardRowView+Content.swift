//
//  FloatingCardRowView+Content.swift
//  Clipboard
//
//  浮动窗口列表行的内容渲染：多行文本 + 搜索高亮。
//

import AppKit
import SnapKit

extension FloatingCardRowView {
    // MARK: - 文本渲染

    /// 渲染带搜索高亮的多行内容
    /// - Parameters:
    ///   - text: 已由模型生成的展示文本
    ///   - keyword: 搜索关键字，为空时不做高亮
    ///   - font: 内容字体
    ///   - color: 内容颜色
    ///   - lineHeight: 行高，多行排版用
    ///   - lineBreakMode: 正文自动换行，链接标题与地址各自单行截断
    /// - Returns: 可直接赋给 NSTextField 的富文本
    func makeHighlightedContent(
        text: String,
        keyword: String,
        font: NSFont,
        color: NSColor,
        lineHeight: CGFloat,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttributes(
            [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ],
            range: fullRange
        )

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return attributed }
        applyKeywordHighlight(to: attributed, keyword: trimmed)
        return attributed
    }

    /// 富文本或颜色条目需要整卡换底时返回该颜色
    func cardFill(for model: PasteboardModel) -> NSColor? {
        switch model.type {
        case .color:
            return model.cachedBackgroundColor
        case .rich:
            return model.richBackground(on: FloatingTheme.rowBackground())
        default:
            return nil
        }
    }

    /// 按类型生成列表正文：普通文本最多三行，链接为标题 + 地址，富文本保留原色
    func makeContent(
        for model: PasteboardModel,
        keyword: String,
        cardFill: NSColor?,
        linkTitle: String?
    ) -> NSAttributedString {
        switch model.type {
        case .link:
            return makeLinkContent(model: model, keyword: keyword, title: linkTitle)
        case .rich:
            return makeRichContent(model: model, keyword: keyword, preserveColors: cardFill != nil)
        case .color:
            let background = model.cachedBackgroundColor ?? .controlBackgroundColor
            return makeHighlightedContent(
                text: model.colorDisplayText,
                keyword: keyword,
                font: displayMode.contentFont,
                color: contrastingNSColor(for: background),
                lineHeight: displayMode.contentLineHeight
            )
        default:
            return makeHighlightedContent(
                text: model.titleText(),
                keyword: keyword,
                font: displayMode.contentFont,
                color: .labelColor,
                lineHeight: displayMode.contentLineHeight
            )
        }
    }

    /// 链接两行展示标题与地址，并统一叠加搜索高亮
    private func makeLinkContent(
        model: PasteboardModel,
        keyword: String,
        title: String?
    ) -> NSAttributedString {
        let address = model.attributeString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let headline = (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? linkHost(from: address)
        let result = NSMutableAttributedString(attributedString: makeHighlightedContent(
            text: headline, keyword: keyword, font: displayMode == .standard ? FloatingTheme.linkTitleFont : displayMode.contentFont,
            color: .labelColor, lineHeight: displayMode.contentLineHeight,
            lineBreakMode: .byTruncatingTail
        ))
        guard headline != address else { return result }
        result.append(makeHighlightedContent(
            text: "\n\(address)", keyword: keyword, font: FloatingTheme.linkAddressFont,
            color: .secondaryLabelColor, lineHeight: displayMode.contentLineHeight,
            lineBreakMode: .byTruncatingTail
        ))
        return result
    }

    /// 富文本保留前景色；和默认卡片对比不够时由整卡底色负责可读性
    private func makeRichContent(
        model: PasteboardModel,
        keyword: String,
        preserveColors: Bool
    ) -> NSAttributedString {
        let source = model.attributeString
        guard source.length > 0 else {
            return makeHighlightedContent(
                text: model.titleText(),
                keyword: keyword,
                font: displayMode.contentFont,
                color: .labelColor,
                lineHeight: displayMode.contentLineHeight
            )
        }

        let mutable = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: mutable.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = displayMode.contentLineHeight
        paragraph.maximumLineHeight = displayMode.contentLineHeight
        mutable.addAttribute(.paragraphStyle, value: paragraph, range: full)
        // 保留代码片段的等宽字体与原有字重，只统一展示字号。
        applyRichFonts(from: source, to: mutable)
        if !preserveColors {
            mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            applyKeywordHighlight(to: mutable, keyword: trimmed)
        }
        return mutable
    }

    /// 保留富文本字体特征，避免代码片段丢失等宽排版
    private func applyRichFonts(from source: NSAttributedString, to result: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: source.length)
        source.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = (value as? NSFont).map {
                NSFontManager.shared.convert($0, toSize: displayMode.contentFont.pointSize)
            } ?? displayMode.contentFont
            result.addAttribute(.font, value: font, range: range)
        }
    }

    /// 用域名作为链接标题的占位
    private func linkHost(from urlString: String) -> String {
        guard let host = urlString.asCompleteURL()?.host() else { return urlString }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    /// 在富文本中标记所有匹配到的关键字
    private func applyKeywordHighlight(to attributed: NSMutableAttributedString, keyword: String) {
        let source = attributed.string as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        var searchRange = NSRange(location: 0, length: source.length)

        // 逐段查找并叠加高亮背景，直到文本末尾
        while searchRange.length > 0 {
            let found = source.range(of: keyword, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.65),
                range: found
            )
            let next = found.location + found.length
            guard next < source.length else { break }
            searchRange = NSRange(location: next, length: source.length - next)
        }
    }
}
