//
//  CategoryChip.swift
//  Clipboard
//
//  Created by crown on 2025/9/21.
//

import SwiftUI

struct CategoryChip: Identifiable, Equatable, Codable {
    static let allID = -1
    static let imagesID = -3

    let id: Int
    var name: String
    var colorIndex: Int // 存储颜色在调色板中的索引
    var isSystem: Bool

    private static let semanticPalette: [Color] = [
        .gray,
        .blue,
        .green,
        .purple,
        .red,
        .orange,
        .yellow
    ]

    static let paletteNSColors: [NSColor] = [
        .systemGray,
        .systemBlue,
        .systemGreen,
        .systemPurple,
        .systemRed,
        .systemOrange,
        .systemYellow
    ]

    static let palette = paletteNSColors.map { Color(nsColor: $0) }

    static func nsColor(at index: Int) -> NSColor {
        guard index >= 0, index < paletteNSColors.count else {
            return paletteNSColors[0]
        }
        return paletteNSColors[index]
    }

    var color: Color {
        get {
            guard colorIndex >= 0, colorIndex < CategoryChip.palette.count
            else {
                return .gray
            }
            return CategoryChip.palette[colorIndex]
        }
        set {
            if let index = CategoryChip.semanticPalette.firstIndex(of: newValue)
                ?? CategoryChip.palette.firstIndex(of: newValue) {
                colorIndex = index
            } else {
                colorIndex = 0
            }
        }
    }

    /// 自动分类只限定内容类型，不作为记录的存储分组。
    var typeFilter: PasteModelType? {
        isSystem && id == Self.imagesID ? .image : nil
    }

    /// 自动聚合标签不接受手动归组，避免把系统标签 ID 写入记录。
    var acceptsManualAssignment: Bool {
        !isSystem || id == Self.allID
    }

    /// 系统标签在图标模式下仍可区分全部历史与图片。
    var systemSymbolName: String? {
        guard isSystem else { return nil }
        if id == Self.imagesID { return "photo" }
        if #available(macOS 15.0, *) {
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
        return "clock.arrow.circlepath"
    }

    init(id: Int, name: String, color: Color, isSystem: Bool) {
        self.id = id
        self.name = name
        self.isSystem = isSystem

        if let index = CategoryChip.semanticPalette.firstIndex(of: color)
            ?? CategoryChip.palette.firstIndex(of: color) {
            colorIndex = index
        } else {
            colorIndex = 0
        }
    }

    init(id: Int, name: String, colorIndex: Int, isSystem: Bool) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.isSystem = isSystem
    }

    static let systemChips: [CategoryChip] = [
        .init(
            id: allID,
            name: String(localized: .allItems),
            color: .gray,
            isSystem: true
        ),
        .init(
            id: imagesID,
            name: String(localized: .image),
            color: .blue,
            isSystem: true
        )
    ]
}
