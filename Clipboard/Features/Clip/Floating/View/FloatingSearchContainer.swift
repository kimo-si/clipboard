//
//  FloatingSearchContainer.swift
//  Clipboard
//
//  浮动窗口搜索框容器：圆角填充底 + 放大镜 + 输入框。
//

import AppKit
import SnapKit

// MARK: - FloatingSearchContainer

/// 圆角搜索框容器
final class FloatingSearchContainer: NSView {
    // MARK: - Subviews

    private let backgroundLayer = CALayer()
    private let magnifierView = NSImageView()
    let searchField = FloatingSearchField()

    // MARK: - State

    private var isFocused = false

    // MARK: - Callbacks

    /// 获得焦点
    var onBecomeFirstResponder: (() -> Void)?
    /// 点击取消按钮
    var onCancelSearch: (() -> Void)?

    // MARK: - Init

    /// 初始化独立胶囊搜索框
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 紧凑模式（简洁浮窗）：缩小字号
    func setCompact(_ compact: Bool) {
        searchField.font = compact ? .systemFont(ofSize: 13) : FloatingTheme.searchFont
        let radius = compact ? FloatingTheme.compactSearchHeight / 2 : FloatingTheme.searchFieldRadius
        layer?.cornerRadius = radius
        backgroundLayer.cornerRadius = radius
    }

    // MARK: - Setup

    /// 布置搜索底色、放大镜与文本输入区域
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = FloatingTheme.searchFieldRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        backgroundLayer.cornerRadius = FloatingTheme.searchFieldRadius
        backgroundLayer.cornerCurve = .continuous
        layer?.addSublayer(backgroundLayer)

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        magnifierView.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
        magnifierView.contentTintColor = .secondaryLabelColor
        magnifierView.imageScaling = .scaleNone
        addSubview(magnifierView)
        magnifierView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Const.space12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(18)
        }

        searchField.onBecomeFirstResponder = { [weak self] in
            self?.onBecomeFirstResponder?()
        }
        searchField.onFocusChange = { [weak self] focused in
            self?.isFocused = focused
            self?.updateAppearance()
        }
        searchField.onCancelRequested = { [weak self] in
            self?.onCancelSearch?()
        }
        addSubview(searchField)
        searchField.snp.makeConstraints { make in
            make.leading.equalTo(magnifierView.snp.trailing).offset(Const.space8)
            make.trailing.equalToSuperview().offset(-Const.space10)
            make.centerY.equalToSuperview()
        }

        updateAppearance()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    /// 刷新搜索框底色（聚焦时略深）
    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = FloatingTheme.searchFieldBackground()
            backgroundLayer.backgroundColor = isFocused
                ? base.blended(withFraction: 0.04, of: .labelColor)?.cgColor ?? base.cgColor
                : base.cgColor
        }
    }
}
