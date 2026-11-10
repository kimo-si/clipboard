//
//  FloatingCardRowView.swift
//  Clipboard
//
//  浮动窗口的单行卡片：应用图标 + 内容（最多三行）+ 时间 + 快捷粘贴序号。
//  样式参考：整行卡片底色，选中时整卡描边。
//

import AppKit
import LinkPresentation
import SnapKit

// MARK: - FloatingCardRowView

final class FloatingCardRowView: NSView {
    // MARK: - Subviews

    /// 卡片背景（承载底色与选中描边）
    private let backgroundView = NSView()
    /// 行首应用图标
    let iconView = FloatingRowIconView()
    /// 内容文本（直接展示剪贴板内容，无标题/副标题之分）
    private let contentLabel = NSTextField(labelWithString: "")
    /// 右侧时间
    private let timestampLabel = NSTextField(labelWithString: "")
    /// 快捷粘贴序号（始终展示前 9 项）
    private let indexLabel = NSTextField(labelWithString: "")
    /// 时间和快捷序号作为一组垂直居中
    private let metadataStack = NSStackView()
    /// 链接标记独立于应用图标，保持来源图标完整
    private let linkSymbolView = NSImageView()
    /// 纯文本粘贴提示图标
    private let plainTextIcon = NSImageView()

    // MARK: - State

    private(set) var currentModel: PasteboardModel?
    private var currentKeyword: String = ""
    private(set) var displayMode: FloatingDisplayMode = .standard
    private(set) var showsImagePreview = false
    private var isSelectedState = false
    private var isFocusedState = false
    private var isHovering = false
    private var iconLoadTask: Task<Void, Never>?
    private var linkTitleTask: Task<Void, Never>?
    /// 富文本 / 颜色条目的整卡底色；为空时用默认卡片色
    private var customCardBackground: NSColor?
    /// 链接预览标题，加载完成前用域名
    private var linkTitle: String?

    // MARK: - Public API

    /// 快捷粘贴序号；为 nil 时隐藏
    var quickPasteIndex: Int? {
        didSet { updateQuickPasteKeyCap() }
    }

    /// 是否展示「纯文本粘贴」提示
    var showPlainTextIndicator: Bool = false {
        didSet { plainTextIcon.isHidden = !showPlainTextIndicator || showsImagePreview }
    }

    // MARK: - Callbacks

    var onPaste: (() -> Void)?
    var onPastePlainText: (() -> Void)?
    var onCopy: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onTogglePreview: (() -> Void)?
    var onAssignToChip: ((Int) -> Void)?
    var onCreateChip: ((PasteboardModel) -> Void)?

    // MARK: - Init

    /// 创建包含来源、正文与时间的剪贴记录卡片
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        iconLoadTask?.cancel()
        linkTitleTask?.cancel()
    }

    // MARK: - Configure

    /// 绑定模型与状态
    func configure(
        with model: PasteboardModel,
        keyword: String,
        isSelected: Bool,
        isFocused: Bool,
        quickPasteIndex: Int?,
        displayMode: FloatingDisplayMode = .standard,
        showsImagePreview: Bool = false
    ) {
        let expandsImage = showsImagePreview && model.type == .image
        let layoutChanged = self.displayMode != displayMode || currentModel?.type != model.type
            || self.showsImagePreview != expandsImage
        self.displayMode = displayMode
        self.showsImagePreview = expandsImage
        // 复用卡片先更新模型，异步图标与链接结果仍按条目身份校验。
        updateModel(model)
        currentKeyword = keyword
        // 依据条目类型重排链接标记，复用卡片时同步恢复正文起点。
        if layoutChanged { applyDisplayMode() }
        reloadContent()
        updateTimestamp()
        self.quickPasteIndex = quickPasteIndex

        updateSelection(isSelected: isSelected, isFocused: isFocused)
    }

    /// 模型身份变化时更新来源图标与链接标题，避免重复启动远程请求
    private func updateModel(_ model: PasteboardModel) {
        let modelChanged = currentModel?.uniqueId != model.uniqueId
        currentModel = model
        guard modelChanged else { return }
        linkTitle = nil
        reloadIcon(for: model)
        // 链接标题允许异步补全，失败时继续显示域名与地址。
        loadLinkTitleIfNeeded(for: model)
    }

    /// 更新选中态
    func updateSelection(isSelected: Bool, isFocused: Bool) {
        isSelectedState = isSelected
        isFocusedState = isFocused
        updateAppearance(animated: false)
    }

    /// 刷新相对时间
    func updateTimestamp() {
        guard let model = currentModel else { return }
        timestampLabel.stringValue = model.timestamp.timeAgo(
            relativeTo: TimeManager.shared.currentTime
        )
    }

    /// 刷新搜索关键字高亮
    func updateKeyword(_ keyword: String) {
        guard currentModel != nil, keyword != currentKeyword else { return }
        currentKeyword = keyword
        reloadContent()
    }

    // MARK: - Content

    /// 按当前外观重绘正文，并决定富文本是否换成对比底色
    private func reloadContent() {
        guard let model = currentModel else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            customCardBackground = cardFill(for: model)
            contentLabel.attributedStringValue = makeContent(
                for: model,
                keyword: currentKeyword,
                cardFill: customCardBackground,
                linkTitle: linkTitle
            )
        }
    }

    /// 链接行异步换成网页标题，失败时保留域名
    private func loadLinkTitleIfNeeded(for model: PasteboardModel) {
        linkTitleTask?.cancel()
        linkTitleTask = nil
        guard model.type == .link else { return }
        let urlString = model.attributeString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = urlString.asCompleteURL() else { return }
        let uniqueId = model.uniqueId
        linkTitleTask = Task { @MainActor [weak self] in
            let title = await Self.fetchLinkTitle(for: url)
            guard !Task.isCancelled, self?.currentModel?.uniqueId == uniqueId else { return }
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty, trimmed != "/" else { return }
            self?.linkTitle = trimmed
            self?.reloadContent()
        }
    }

    /// 只取网页标题，图标仍用来源应用
    private static func fetchLinkTitle(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 4
        nonisolated(unsafe) let unsafeProvider = provider
        do {
            try Task.checkCancellation()
            let metadata = try await withTaskCancellationHandler {
                try await provider.startFetchingMetadata(for: url)
            } onCancel: {
                unsafeProvider.cancel()
            }
            try Task.checkCancellation()
            return metadata.title
        } catch {
            return nil
        }
    }

    /// 加载行首图标：优先展示来源应用图标
    private func reloadIcon(for model: PasteboardModel) {
        iconLoadTask?.cancel()
        switch model.type {
        case .image:
            // 复用图片卡片时先显示该图片的缓存，避免旧缩略图残留到异步加载完成。
            iconView.showThumbnail(model.thumbnail())
            iconLoadTask = Task { @MainActor [weak self] in
                let image = await model.loadThumbnail()
                guard !Task.isCancelled, self?.currentModel?.uniqueId == model.uniqueId else { return }
                self?.iconView.showThumbnail(image)
            }
        case .file:
            let paths = model.cachedFilePaths ?? []
            if paths.count == 1, let path = paths.first {
                iconView.showAppIcon(
                    FileThumbnailService.shared.systemIcon(for: URL(filePath: path))
                )
            } else {
                iconView.showSymbol("folder.fill", tintColor: .secondaryLabelColor)
            }
        default:
            iconLoadTask = Task { @MainActor [weak self] in
                let icon = await AppIconCache.shared.loadIcon(
                    forAppID: model.appID,
                    path: model.appPath
                )
                guard !Task.isCancelled else { return }
                self?.iconView.showAppIcon(icon)
            }
        }
    }

    // MARK: - Quick Paste

    /// 刷新快捷粘贴序号
    private func updateQuickPasteKeyCap() {
        guard let index = quickPasteIndex else {
            indexLabel.stringValue = ""
            indexLabel.isHidden = true
            return
        }
        indexLabel.stringValue = "\(index)"
        indexLabel.isHidden = false
    }

    /// 根据实际正文宽度更新多行排版宽度
    override func layout() {
        super.layout()
        let width = contentLabel.bounds.width
        guard width > 1, abs(contentLabel.preferredMaxLayoutWidth - width) > 0.5 else { return }
        contentLabel.preferredMaxLayoutWidth = width
        contentLabel.invalidateIntrinsicContentSize()
    }
}

// MARK: - Setup & Layout

private extension FloatingCardRowView {
    /// 搭建视图层级与约束
    func setup() {
        wantsLayer = true
        setupBackground()
        setupContentLabel()
        setupLinkSymbol()
        setupRightSide()
        applyDisplayMode()
        updateAppearance(animated: false)
        setupDoubleClick()
        setupTracking()
        setupContextMenu()
    }

    /// 构建承载卡片底色、选中轮廓与来源图标的背景层
    func setupBackground() {
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = FloatingTheme.rowRadius
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }

        backgroundView.addSubview(iconView)
    }

    /// 内容文本：最多三行，超出截断
    func setupContentLabel() {
        contentLabel.font = FloatingTheme.rowTitleFont
        contentLabel.textColor = .labelColor
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.maximumNumberOfLines = FloatingTheme.rowTitleMaxLines
        contentLabel.cell?.wraps = true
        contentLabel.cell?.truncatesLastVisibleLine = true
        contentLabel.setContentHuggingPriority(.required, for: .vertical)
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        backgroundView.addSubview(contentLabel)
    }

    /// 右侧时间与序号
    func setupRightSide() {
        timestampLabel.font = FloatingTheme.timestampFont
        timestampLabel.textColor = .secondaryLabelColor
        timestampLabel.alignment = .right
        timestampLabel.setContentHuggingPriority(.required, for: .horizontal)
        timestampLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        indexLabel.font = .monospacedDigitSystemFont(ofSize: FloatingTheme.timestampFont.pointSize, weight: .regular)
        indexLabel.textColor = .tertiaryLabelColor
        indexLabel.alignment = .right
        indexLabel.isHidden = true
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)
        metadataStack.orientation = .vertical
        metadataStack.alignment = .trailing
        metadataStack.spacing = Const.space4
        metadataStack.addArrangedSubview(timestampLabel)
        metadataStack.addArrangedSubview(indexLabel)
        backgroundView.addSubview(metadataStack)
        metadataStack.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-FloatingTheme.rowPadding)
            make.centerY.equalToSuperview()
            make.width.equalTo(FloatingTheme.rowMetaWidth)
        }
        setupPlainTextIndicator()
    }

    /// 纯文本粘贴修饰键提示放在时间组左侧
    func setupPlainTextIndicator() {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        plainTextIcon.image = NSImage(
            systemSymbolName: "textformat",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(iconConfig)
        plainTextIcon.contentTintColor = .tertiaryLabelColor
        plainTextIcon.imageScaling = .scaleNone
        plainTextIcon.isHidden = true
        backgroundView.addSubview(plainTextIcon)
        plainTextIcon.snp.makeConstraints { make in
            make.trailing.equalTo(metadataStack.snp.leading).offset(-Const.space4)
            make.centerY.equalTo(timestampLabel)
            make.width.height.equalTo(10)
        }
    }

    /// 按显示模式重排布局
    func applyDisplayMode() {
        iconView.setExpandedPreview(showsImagePreview)
        plainTextIcon.isHidden = !showPlainTextIndicator || showsImagePreview
        if showsImagePreview {
            layoutImagePreview()
            return
        }
        let isStandard = displayMode == .standard
        let showsLink = isStandard && currentModel?.type == .link
        backgroundView.layer?.cornerRadius = displayMode.cardRadius
        iconView.isHidden = !isStandard
        metadataStack.isHidden = !isStandard
        linkSymbolView.isHidden = !showsLink
        contentLabel.maximumNumberOfLines = displayMode.contentMaxLines
        layoutRowMetadata()

        iconView.snp.remakeConstraints { make in
            make.leading.equalToSuperview().offset(FloatingTheme.rowPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(isStandard ? FloatingTheme.rowIconSize : 20)
        }
        layoutContent(isStandard: isStandard, showsLink: showsLink)
    }

    /// 普通行的时间与快捷序号恢复到右侧，保持既有标准和简洁模式布局。
    func layoutRowMetadata() {
        metadataStack.orientation = .vertical
        metadataStack.alignment = .trailing
        metadataStack.spacing = Const.space4
        metadataStack.snp.remakeConstraints { make in
            make.trailing.equalToSuperview().offset(-FloatingTheme.rowPadding)
            make.centerY.equalToSuperview()
            make.width.equalTo(FloatingTheme.rowMetaWidth)
        }
    }

    /// 图片独占卡片上方，底部保留尺寸、时间与快捷序号。
    func layoutImagePreview() {
        backgroundView.layer?.cornerRadius = FloatingTheme.rowRadius
        iconView.isHidden = false
        metadataStack.isHidden = false
        linkSymbolView.isHidden = true
        contentLabel.maximumNumberOfLines = 1
        iconView.snp.remakeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(FloatingTheme.imageCardPadding)
            make.bottom.equalToSuperview().inset(FloatingTheme.imageCardFooterHeight)
        }
        // 底栏单独布局，避免时间信息挤压图片的可用宽度。
        layoutImageMetadata()
    }

    /// 将尺寸与时间放在同一底栏，并允许窄窗口优先压缩尺寸文字。
    func layoutImageMetadata() {
        metadataStack.orientation = .horizontal
        metadataStack.alignment = .centerY
        metadataStack.spacing = Const.space8
        metadataStack.snp.remakeConstraints { make in
            make.trailing.equalToSuperview().inset(FloatingTheme.imageCardPadding)
            make.centerY.equalTo(contentLabel)
        }
        contentLabel.snp.remakeConstraints { make in
            make.leading.equalToSuperview().inset(FloatingTheme.imageCardPadding)
            make.trailing.equalTo(metadataStack.snp.leading).offset(-Const.space8)
            make.centerY.equalTo(backgroundView.snp.bottom).offset(-FloatingTheme.imageCardFooterHeight / 2)
        }
    }

    /// 为链接预留独立标记位置，并为正文限定三行可用高度
    func layoutContent(isStandard: Bool, showsLink: Bool) {
        contentLabel.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(Const.space4)
            make.bottom.lessThanOrEqualToSuperview().offset(-Const.space4)
            if isStandard {
                if showsLink {
                    make.leading.equalTo(linkSymbolView.snp.trailing).offset(FloatingTheme.linkSymbolSpacing)
                } else {
                    make.leading.equalTo(iconView.snp.trailing).offset(FloatingTheme.iconToContentSpacing)
                }
                make.trailing.equalTo(metadataStack.snp.leading).offset(-FloatingTheme.contentToMetaSpacing)
            } else {
                make.leading.trailing.equalToSuperview().inset(Const.space10)
            }
        }
    }

    /// 链接标记与来源应用图标在同一水平线上展示
    func setupLinkSymbol() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        linkSymbolView.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        linkSymbolView.contentTintColor = .secondaryLabelColor
        linkSymbolView.imageScaling = .scaleNone
        linkSymbolView.isHidden = true
        backgroundView.addSubview(linkSymbolView)
        linkSymbolView.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(FloatingTheme.iconToContentSpacing)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(FloatingTheme.linkSymbolSize)
        }
    }

    /// 双击粘贴
    func setupDoubleClick() {
        let doubleClick = CollectionClickGestureRecognizer(
            target: self,
            action: #selector(handleDoubleClick)
        )
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(doubleClick)
    }

    /// 设置 hover 追踪
    func setupTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    /// 双击调用当前条目的粘贴操作
    @objc func handleDoubleClick() {
        onPaste?()
    }
}

// MARK: - Appearance

extension FloatingCardRowView {
    /// 鼠标进入时显示悬停底色
    override func mouseEntered(with _: NSEvent) {
        isHovering = true
        updateAppearance(animated: true)
    }

    /// 鼠标离开时恢复卡片底色
    override func mouseExited(with _: NSEvent) {
        isHovering = false
        updateAppearance(animated: true)
    }

    /// 外观切换时同步正文、背景与选中轮廓
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reloadContent()
        updateAppearance(animated: false)
    }

    /// 选中只加描边；富文本对比底色优先于默认卡片色
    func updateAppearance(animated: Bool) {
        var background: CGColor = .clear
        var border: CGColor = .clear
        var borderWidth: CGFloat = 0
        var metaColor = NSColor.secondaryLabelColor
        var indexColor = NSColor.tertiaryLabelColor

        effectiveAppearance.performAsCurrentDrawingAppearance {
            background = cardBackground().cgColor
            if let custom = customCardBackground {
                let contrast = contrastingNSColor(for: custom)
                metaColor = contrast.withAlphaComponent(0.62)
                indexColor = contrast.withAlphaComponent(0.48)
            }
            if isSelectedState {
                border = FloatingTheme.rowAccentColor.cgColor
                borderWidth = FloatingTheme.selectionBorderWidth
            }
        }

        timestampLabel.textColor = metaColor
        indexLabel.textColor = indexColor

        applyCardAppearance(background: background, border: border, borderWidth: borderWidth, animated: animated)
    }

    /// 富文本与颜色条目优先使用内容底色，其余按选择与悬停状态取色
    private func cardBackground() -> NSColor {
        if let customCardBackground { return customCardBackground }
        if isSelectedState { return FloatingTheme.selectedRowBackground() }
        return isHovering ? FloatingTheme.rowHoverBackground() : FloatingTheme.rowBackground()
    }

    /// 在同一事务内同步卡片底色与选中轮廓
    private func applyCardAppearance(background: CGColor, border: CGColor, borderWidth: CGFloat, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        backgroundView.layer?.backgroundColor = background
        backgroundView.layer?.borderColor = border
        backgroundView.layer?.borderWidth = borderWidth
        CATransaction.commit()
    }
}

// MARK: - Context Menu

private extension FloatingCardRowView {
    /// 安装右键菜单
    func setupContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        self.menu = menu
    }
}
