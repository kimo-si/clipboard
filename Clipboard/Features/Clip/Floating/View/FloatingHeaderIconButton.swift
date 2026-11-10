//
//  FloatingHeaderIconButton.swift
//  Clipboard
//
//  浮动窗口标题栏图标按钮：无边框，hover 时显示圆角底色。
//

import AppKit
import SnapKit

/// 标题栏 / 工具条图标按钮
final class FloatingHeaderIconButton: NSView {
    // MARK: - Subviews

    private let backgroundLayer = CALayer()
    private let imageView = NSImageView()
    private let badgeDot = NSView()

    // MARK: - State

    private let side: CGFloat
    private var isHovering = false

    // MARK: - Public API

    /// 点击回调
    var action: (() -> Void)?
    /// 右键回调
    var onRightClick: (() -> Void)?
    /// 是否显示更新红点
    var showBadge = false {
        didSet {
            guard showBadge != oldValue else { return }
            badgeDot.isHidden = !showBadge
        }
    }
    /// 是否处于激活态（例如 Pin 已固定）
    var isActive = false {
        didSet { updateAppearance(animated: false) }
    }

    // MARK: - Init

    /// 创建图标按钮
    /// - Parameters:
    ///   - symbolName: SF Symbol 名称
    ///   - pointSize: 图标字号
    ///   - side: 按钮边长
    init(symbolName: String, pointSize: CGFloat = 14, side: CGFloat = 24) {
        self.side = side
        super.init(frame: .zero)
        setup(symbolName: symbolName, pointSize: pointSize)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Setup

    private func setup(symbolName: String, pointSize: CGFloat) {
        wantsLayer = true

        backgroundLayer.cornerRadius = 6
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.masksToBounds = true
        layer?.addSublayer(backgroundLayer)

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        imageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        snp.makeConstraints { make in
            make.width.height.equalTo(side)
        }

        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = 3
        badgeDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeDot.isHidden = true
        addSubview(badgeDot)
        badgeDot.snp.makeConstraints { make in
            make.width.height.equalTo(6)
            make.top.equalToSuperview().offset(1)
            make.trailing.equalToSuperview().offset(-1)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleClick)))

        updateAppearance(animated: false)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance(animated: false)
    }

    /// 刷新图标与底色
    private func updateAppearance(animated: Bool) {
        var background: CGColor = .clear
        effectiveAppearance.performAsCurrentDrawingAppearance {
            imageView.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
            if isActive {
                background = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            } else if isHovering {
                background = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            }
        }
        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backgroundLayer.backgroundColor = background
            CATransaction.commit()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            ctx.allowsImplicitAnimation = true
            backgroundLayer.backgroundColor = background
        }
    }

    // MARK: - Mouse

    override func mouseEntered(with _: NSEvent) {
        isHovering = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with _: NSEvent) {
        isHovering = false
        updateAppearance(animated: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let onRightClick else {
            super.rightMouseDown(with: event)
            return
        }
        onRightClick()
    }

    @objc private func handleClick() {
        action?()
    }
}
