//
//  PasteboardModel+RowDisplay.swift
//  Clipboard
//
//  浮动窗口列表行的展示文本：主标题直接展示剪贴板内容，副标题标注来源与类型。
//

import AppKit

extension PasteboardModel {
    // MARK: - 主标题

    /// 列表行正文：保留换行，由行视图截到三行
    func titleText() -> String {
        switch type {
        case .image:
            guard let size = imageSize() else { return type.string }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .file:
            return fileDisplayText()
        case .color:
            return colorDisplayText
        case .none:
            return ""
        default:
            return attributeString.string
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - 副标题

    /// 列表行副标题：来源应用 · 内容类型，避免与主标题内容重复
    func subtitleText() -> String {
        guard !appName.isEmpty else { return type.string }
        return "\(appName) · \(type.string)"
    }

    // MARK: - Private

    /// 文件展示内容：单个显示文件名，多个显示数量（完整路径过长不适合列表）
    private func fileDisplayText() -> String {
        guard let paths = cachedFilePaths, !paths.isEmpty else { return type.string }
        guard paths.count == 1, let path = paths.first else {
            return String(localized: .fileCount(paths.count))
        }
        return URL(filePath: path).lastPathComponent
    }
}
