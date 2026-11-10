//
//  FloatingTabBarView.swift
//  Clipboard
//
//  浮动窗口分类栏：选中项为填充胶囊，未选中为纯文字。
//  保留右键重命名 / 删除 / 改色，拖拽内容到 Tab 可归入该分类。
//

import AppKit
import SnapKit

// MARK: - FloatingTabItemView

/// 单个分类胶囊：选中时填充强调色
final class FloatingTabItemView: NSView {
    // MARK: - Subviews

    private let titleField = NSTextField(labelWithString: "")

    // MARK: - State

    private let chip: CategoryChip
    private var isSelectedState = false
    private var isHovering = false
    private var isDraggingOver = false

    // MARK: - Callbacks

    /// 点击 Tab
    var onSelect: (() -> Void)?
    /// 请求重命名
    var onRename: (() -> Void)?
    /// 请求删除
    var onDelete: (() -> Void)?
    /// 请求改色
    var onColorChange: ((Int) -> Void)?
    /// 拖入内容
    var onDrop: ((PasteboardModel) -> Bool)?

    // MARK: - Init

    /// 创建分类 Tab
    init(chip: CategoryChip, isSelected: Bool) {
        self.chip = chip
        self.isSelectedState = isSelected
        super.init(frame: .zero)
        setup()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 更新选中态
    func setSelected(_ selected: Bool) {
        guard isSelectedState != selected else { return }
        isSelectedState = selected
        updateAppearance(animated: true)
    }

    /// 更新展示名称（重命名后）
    func updateName(_ name: String) {
        titleField.stringValue = name
        invalidateIntrinsicContentSize()
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true

        layer?.cornerCurve = .continuous

        titleField.font = FloatingTheme.tabFont
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        addSubview(titleField)
        titleField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Const.space12)
            make.trailing.equalToSuperview().offset(-Const.space12)
            make.centerY.equalToSuperview()
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)

        registerForDraggedTypes([.pasteboardModel])

        snp.makeConstraints { make in
            make.height.equalTo(FloatingTheme.tabBarHeight)
        }
        titleField.stringValue = chip.name
    }

    // MARK: - Appearance

    override var intrinsicContentSize: NSSize {
        let width = titleField.intrinsicContentSize.width + Const.space12 * 2
        return NSSize(width: ceil(width), height: FloatingTheme.tabBarHeight)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    /// 选中胶囊的填充色：默认分类用系统蓝，自定义分类用自身颜色
    private func selectedFill() -> NSColor {
        chip.id == -1 ? .systemBlue : CategoryChip.nsColor(at: chip.colorIndex)
    }

    /// 刷新胶囊底色与文字
    private func updateAppearance(animated: Bool = false) {
        var fill = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelectedState {
                titleField.textColor = .white
                titleField.font = .systemFont(ofSize: FloatingTheme.tabFont.pointSize, weight: .semibold)
                fill = selectedFill().cgColor
            } else {
                titleField.textColor = (isHovering || isDraggingOver)
                    ? .labelColor
                    : .labelColor
                titleField.font = FloatingTheme.tabFont
                if isHovering || isDraggingOver {
                    fill = NSColor.labelColor.withAlphaComponent(0.08).cgColor
                }
            }
        }
        let applyFill = {
            self.layer?.backgroundColor = fill
        }
        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyFill()
            CATransaction.commit()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            applyFill()
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

    @objc private func handleClick() {
        onSelect?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !chip.isSystem else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// 构建分类右键菜单
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(
            title: String(localized: .rename),
            action: #selector(handleRename),
            symbolName: "pencil"
        ))
        menu.addItem(menuItem(
            title: String(localized: .delete),
            action: #selector(handleDelete),
            symbolName: "trash"
        ))
        menu.addItem(.separator())

        let colorItem = NSMenuItem()
        colorItem.view = ChipColorPaletteMenuView(
            currentColorIndex: chip.colorIndex,
            onColorChange: { [weak self, weak menu] index in
                menu?.cancelTracking()
                self?.onColorChange?(index)
            }
        )
        menu.addItem(colorItem)
        return menu
    }

    /// 构建带图标的菜单项
    private func menuItem(title: String, action: Selector, symbolName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if #available(macOS 26.0, *) {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func handleRename() {
        onRename?()
    }

    @objc private func handleDelete() {
        onDelete?()
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard chip.acceptsManualAssignment,
              sender.draggingPasteboard.availableType(from: [.pasteboardModel]) != nil else {
            return []
        }
        isDraggingOver = true
        updateAppearance(animated: true)
        return .copy
    }

    override func draggingExited(_: NSDraggingInfo?) {
        isDraggingOver = false
        updateAppearance(animated: true)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDraggingOver = false
        updateAppearance(animated: true)
        guard chip.acceptsManualAssignment,
              let data = sender.draggingPasteboard.data(forType: .pasteboardModel),
              let model = try? JSONDecoder().decode(PasteboardModel.self, from: data)
        else { return false }
        return onDrop?(model) ?? false
    }
}

// MARK: - FloatingTabBarView

/// 分类 Tab 容器：横向滚动 + 新建分类按钮
final class FloatingTabBarView: NSView {
    // MARK: - Subviews

    private let scrollView = HorizontalScrollView()
    private let contentStack = NSStackView()
    private let addButton = FloatingHeaderIconButton(
        symbolName: "plus", pointSize: 20, side: FloatingTheme.headerButtonSize
    )

    // MARK: - State

    private var tabViews: [FloatingTabItemView] = []
    private var chips: [CategoryChip] = []
    private var selectedChipId: Int = -1

    // MARK: - Callbacks

    /// 选中分类
    var onSelectChip: ((Int) -> Void)?
    /// 请求新建分类
    var onAddChip: (() -> Void)?
    /// 请求重命名
    var onRenameChip: ((CategoryChip) -> Void)?
    /// 请求删除
    var onDeleteChip: ((CategoryChip) -> Void)?
    /// 请求改色
    var onColorChange: ((CategoryChip, Int) -> Void)?
    /// 拖拽归组
    var onDropToChip: ((PasteboardModel, Int) -> Bool)?

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

    /// 重建分类列表
    func reload(chips: [CategoryChip], selectedId: Int) {
        self.chips = chips
        selectedChipId = selectedId
        rebuildTabs()
    }

    /// 仅同步选中态，避免重建视图
    func updateSelection(_ selectedId: Int) {
        guard selectedChipId != selectedId else { return }
        selectedChipId = selectedId
        applySelection()
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none

        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        contentStack.orientation = .horizontal
        contentStack.spacing = Const.space8
        contentStack.alignment = .centerY
        scrollView.documentView = contentStack
        contentStack.snp.makeConstraints { make in
            make.top.bottom.leading.equalTo(clipView)
        }

        addSubview(scrollView)

        addButton.action = { [weak self] in self?.onAddChip?() }
        addButton.toolTip = String(localized: .untitled)
        addSubview(addButton)
        addButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(scrollView)
        }

        scrollView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(addButton.snp.leading).offset(-Const.space4)
        }
    }

    // MARK: - Rebuild

    /// 依据最新分类数据重建 Tab
    private func rebuildTabs() {
        tabViews.forEach { $0.removeFromSuperview() }
        for arranged in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        tabViews = []

        for chip in chips {
            let tab = makeTab(for: chip)
            tabViews.append(tab)
            contentStack.addArrangedSubview(tab)
        }
        layoutSubtreeIfNeeded()
    }

    /// 创建单个 Tab 并绑定回调
    private func makeTab(for chip: CategoryChip) -> FloatingTabItemView {
        let tab = FloatingTabItemView(chip: chip, isSelected: chip.id == selectedChipId)
        tab.onSelect = { [weak self] in
            self?.selectedChipId = chip.id
            self?.applySelection()
            self?.onSelectChip?(chip.id)
            self?.scrollToSelected()
        }
        tab.onRename = { [weak self] in self?.onRenameChip?(chip) }
        tab.onDelete = { [weak self] in self?.onDeleteChip?(chip) }
        tab.onColorChange = { [weak self] index in self?.onColorChange?(chip, index) }
        tab.onDrop = { [weak self] model in self?.onDropToChip?(model, chip.id) ?? false }
        return tab
    }

    /// 同步所有 Tab 的选中态
    private func applySelection() {
        for (tab, chip) in zip(tabViews, chips) {
            tab.setSelected(chip.id == selectedChipId)
        }
    }

    /// 将选中 Tab 滚动到可见区域
    private func scrollToSelected() {
        guard let tab = tabViews.first(where: { $0.chipId == selectedChipId }) else { return }
        Task { @MainActor in tab.scrollToVisible(tab.bounds) }
    }

}

// MARK: - CategoryChip 便捷访问

extension FloatingTabItemView {
    /// 当前 Tab 对应的分类 id
    var chipId: Int { chip.id }
}
