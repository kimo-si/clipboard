//
//  FloatingRowIconView.swift
//  Clipboard
//
//  列表行左侧图标：应用图标铺满，符号和缩略图走圆角底，链接可叠加角标。
//

import AppKit
import SnapKit

/// 列表行图标容器
final class FloatingRowIconView: NSView {
    // MARK: - Subviews

    private let backgroundView = NSView()
    private let imageView = NSImageView()
    private let tintedImageView = NSImageView()
    private let linkBadge = NSView()
    private let linkIcon = NSImageView()

    // MARK: - State

    private let side: CGFloat
    private var isExpandedPreview = false
    private var usesInsetImage = false

    // MARK: - Init

    /// 创建行图标容器
    /// - Parameter side: 容器边长
    init(side: CGFloat = FloatingTheme.rowIconSize) {
        self.side = side
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 展示来源应用 / 文件图标，直接铺满，不垫底色块
    func showAppIcon(_ image: NSImage?) {
        usesInsetImage = false
        backgroundView.isHidden = true
        tintedImageView.isHidden = true
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isHidden = image == nil
        imageView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    /// 展示彩色位图（应用图标、图片缩略图）
    func showImage(_ image: NSImage?) {
        showInsetImage(image)
    }

    /// 展示可着色符号图标
    func showSymbol(_ symbolName: String, tintColor: NSColor) {
        usesInsetImage = false
        backgroundView.isHidden = false
        imageView.isHidden = true
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        tintedImageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
        tintedImageView.contentTintColor = tintColor
        tintedImageView.isHidden = false
    }

    /// 展示缩略图（图片类内容），保持等比缩放
    func showThumbnail(_ image: NSImage?) {
        showInsetImage(image)
    }

    /// 在图片专属列表中展开预览区域，普通列表仍使用原有小图标尺寸。
    func setExpandedPreview(_ expanded: Bool) {
        guard isExpandedPreview != expanded else { return }
        isExpandedPreview = expanded
        if usesInsetImage { layoutInsetImage() }
    }

    /// 链接条目在图标右下角叠加链接角标
    func setShowsLinkBadge(_ shows: Bool) {
        linkBadge.isHidden = !shows
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 7
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isHidden = true
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        tintedImageView.imageScaling = .scaleProportionallyUpOrDown
        tintedImageView.isHidden = true
        backgroundView.addSubview(tintedImageView)
        tintedImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(16)
        }

        linkBadge.wantsLayer = true
        linkBadge.layer?.cornerRadius = 6.5
        linkBadge.layer?.cornerCurve = .continuous
        linkBadge.isHidden = true
        addSubview(linkBadge)
        linkBadge.snp.makeConstraints { make in
            make.width.height.equalTo(13)
            make.trailing.equalToSuperview().offset(3)
            make.bottom.equalToSuperview().offset(2)
        }

        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        linkIcon.image = NSImage(
            systemSymbolName: "link",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
        linkIcon.imageScaling = .scaleNone
        linkBadge.addSubview(linkIcon)
        linkIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        updateAppearance()
    }

    /// 缩略图放在圆角底中央
    private func showInsetImage(_ image: NSImage?) {
        usesInsetImage = true
        backgroundView.isHidden = false
        tintedImageView.isHidden = true
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isHidden = image == nil
        layoutInsetImage()
    }

    /// 大图完整等比铺在可用区域内，图标模式继续保持原有固定内边距。
    private func layoutInsetImage() {
        imageView.snp.remakeConstraints { make in
            if isExpandedPreview {
                make.edges.equalToSuperview().inset(FloatingTheme.imagePreviewInset)
            } else {
                make.center.equalToSuperview()
                make.width.height.equalTo(side - 8)
            }
        }
    }

    // MARK: - Intrinsic Size

    /// 默认使用设计令牌尺寸，外部改写约束时以外部为准
    override var intrinsicContentSize: NSSize {
        NSSize(width: side, height: side)
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    /// 刷新底色与链接角标
    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundView.layer?.backgroundColor = FloatingTheme.rowIconBackground().cgColor
            linkBadge.layer?.backgroundColor = NSColor.white.cgColor
            linkIcon.contentTintColor = NSColor(white: 0.25, alpha: 1)
        }
    }
}
