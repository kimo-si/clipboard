//
//  FloatingKeyCapLabel.swift
//  Clipboard
//
//  浮窗键帽：用于展示 ⌘K、⌘1、⏎ 等快捷键提示的圆角小标签。
//

import AppKit
import SnapKit

/// 圆角键帽标签
final class FloatingKeyCapLabel: NSView {
    // MARK: - Subviews

    private let label = NSTextField(labelWithString: "")

    // MARK: - State

    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    // MARK: - Init

    /// 创建键帽
    /// - Parameters:
    ///   - horizontalPadding: 左右内边距
    ///   - verticalPadding: 上下内边距
    init(horizontalPadding: CGFloat = 5, verticalPadding: CGFloat = 1) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 更新键帽文字
    func setText(_ text: String) {
        label.stringValue = text
    }

    /// 更新键帽可见性
    func setVisible(_ visible: Bool) {
        isHidden = !visible
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = FloatingTheme.keyCapRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.alignment = .center
        addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(
                NSEdgeInsets(
                    top: verticalPadding,
                    left: horizontalPadding,
                    bottom: verticalPadding,
                    right: horizontalPadding
                )
            )
        }
        updateAppearance()
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    /// 根据当前外观刷新键帽配色
    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = FloatingTheme.keyCapBackground().cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            label.textColor = .secondaryLabelColor
        }
    }
}
