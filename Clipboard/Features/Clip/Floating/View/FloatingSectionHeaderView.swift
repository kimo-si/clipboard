//
//  FloatingSectionHeaderView.swift
//  Clipboard
//
//  浮动窗口列表的时间分组标题：左侧分组名，右侧该组条数。
//

import AppKit
import SnapKit

/// 时间分组标题
final class FloatingSectionHeaderView: NSView, NSCollectionViewElement {
    // MARK: - Subviews

    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 绑定分组与条数
    func configure(title: String, countText: String) {
        titleLabel.stringValue = title
        countLabel.stringValue = countText
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true

        titleLabel.font = FloatingTheme.sectionHeaderFont
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Const.space8)
            make.centerY.equalToSuperview()
        }

        countLabel.font = FloatingTheme.sectionHeaderFont
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Const.space8)
            make.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(Const.space8)
        }
    }
}
