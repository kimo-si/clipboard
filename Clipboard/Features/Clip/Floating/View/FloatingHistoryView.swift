//
//  FloatingHistoryView.swift
//  Clipboard
//
//  浮动窗口历史记录列表：按时间分组（今天 / 昨天 / 更早）的 NSCollectionView。
//

import AppKit
import Combine
import SnapKit

// MARK: - FloatingHistoryView

final class FloatingHistoryView: NSView {
    /// 分组标题复用标识
    static let sectionHeaderIdentifier = NSUserInterfaceItemIdentifier("FloatingSectionHeader")

    // MARK: - Subviews

    let scrollView = NSScrollView()
    let collectionView = ClipCollectionView()
    let collectionLayout = NSCollectionViewFlowLayout()
    let emptyStateView = EmptyStateView(style: .floating)
    private(set) var displayMode: FloatingDisplayMode = .standard
    private(set) var showsImageList = false

    /// 只有图片标签增大行间距，其他标签继续沿用用户选择的显示模式。
    var cardSpacing: CGFloat {
        showsImageList ? FloatingTheme.imageCardSpacing : displayMode.cardSpacing
    }

    /// 默认行高用于分页提前加载；实际图片行高由图片比例决定。
    var estimatedCardHeight: CGFloat {
        showsImageList
            ? FloatingTheme.imageCardHeight(for: nil, width: collectionLayout.itemSize.width)
            : displayMode.cardHeight
    }

    /// 列表内边距。顶栏和底栏已经把列表让开，这里只留描边和卡片间距。
    var scrollInsets: NSEdgeInsets {
        NSEdgeInsets(
            top: Const.selectionBorderWidth,
            left: displayMode.cardInset,
            bottom: cardSpacing,
            right: displayMode.cardInset
        )
    }

    // MARK: - Data Source

    var dataSource: NSCollectionViewDiffableDataSource<Int, PasteboardModel>!

    // MARK: - State

    let dataStore = PasteDataStore.main
    let env = AppEnvironment.shared
    weak var topVM: TopBarViewModel?
    private let presenter = ClipListPresenter()

    /// 扁平条目列表（全局顺序，与选中索引一一对应）
    var dataList: [PasteboardModel] = []
    /// 时间分组结果
    private(set) var sections: [FloatingTimeGroupSection] = []

    /// 重建分组（供布局扩展调用）
    func setSections(_ newSections: [FloatingTimeGroupSection]) {
        sections = newSections
    }
    /// 当前选中项的全局索引
    var selectedIndex: Int = 0
    var isQuickPastePressed: Bool = false
    var isPlainTextModifierPressed: Bool = false
    private var dragSourceApp: NSRunningApplication?

    var onActivateSearch: ((String?) -> Void)?
    var onTogglePreview: ((Int) -> Void)?
    var onResetHoverPreview: (() -> Void)?
    var onCreateChip: ((PasteboardModel) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// 宽度变化时重新计算单列布局，图片保持完整等比显示。
    override func layout() {
        super.layout()
        let width = scrollView.contentSize.width - scrollInsets.left - scrollInsets.right
        let size = NSSize(width: width, height: estimatedCardHeight)
        let headerSize = NSSize(width: 0, height: 0)
        var needsInvalidate = false
        if width > 0, collectionLayout.itemSize != size {
            collectionLayout.itemSize = size
            needsInvalidate = true
        }
        if collectionLayout.headerReferenceSize != headerSize {
            collectionLayout.headerReferenceSize = headerSize
            needsInvalidate = true
        }
        guard needsInvalidate else { return }
        collectionLayout.invalidateLayout()
    }

    // MARK: - Public API

    /// 切换显示模式
    func setDisplayMode(_ mode: FloatingDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        updateLayoutMetrics()
        reloadAllItems()
    }

    /// 在应用最新数据快照前同步标签布局，避免把其他标签永久切成大图。
    @discardableResult
    func syncImageListLayout() -> Bool {
        let shouldShow = topVM?.getSelectChipId() == CategoryChip.imagesID
        guard showsImageList != shouldShow else { return false }
        showsImageList = shouldShow
        // 清理旧卡片悬停状态后，统一更新间距、分页阈值与布局缓存。
        onResetHoverPreview?()
        updateLayoutMetrics()
        return true
    }

    /// 统一更新列表几何参数，标准与简洁模式均保留各自的普通行布局。
    private func updateLayoutMetrics() {
        collectionLayout.minimumLineSpacing = cardSpacing
        collectionLayout.sectionInset = scrollInsets
        collectionLayout.headerReferenceSize = .zero
        scrollView.scrollerInsets = NSEdgeInsets(
            top: scrollInsets.top, left: 0, bottom: scrollInsets.bottom, right: 0
        )
        presenter.loadMoreThreshold = (estimatedCardHeight + cardSpacing) * 5
        needsLayout = true
        collectionLayout.invalidateLayout()
    }

    /// 注入预览相关钩子
    func setPreviewHooks(
        isShown: @escaping () -> Bool,
        close: @escaping () -> Void,
        reopen: @escaping () -> Void
    ) {
        presenter.previewIsShown = isShown
        presenter.closePreview = close
        presenter.reopenPreview = reopen
    }

    /// 绑定 ViewModel 并首次渲染
    func configure(topVM: TopBarViewModel) {
        self.topVM = topVM
        dataList = dataStore.dataList.value
        env.focusRegion = .collection
        applySnapshot()
        resetToFirst()
        configurePresenter()
        observeChipContentChanges()
        focusCollection()
    }

    /// 焦点区域变化时刷新选中态描边
    func setFocusRegion(_ region: FocusRegion) {
        guard region != env.focusRegion else { return }
        env.focusRegion = region
        updateSelectedItemBorder()
    }

    /// 刷新可见项的焦点态
    func updateSelectedItemBorder() {
        let focused = env.focusRegion == .collection
        for case let item as FloatingCollectionItem in collectionView.visibleItems() {
            item.setFocused(focused)
        }
    }

    /// 快捷粘贴修饰键按下状态
    func setIsQuickPastePressed(_ pressed: Bool) {
        guard pressed != isQuickPastePressed else { return }
        isQuickPastePressed = pressed
        updateQuickPasteDisplay()
    }

    /// 复位快捷粘贴提示
    func resetQuickPasteState() {
        isQuickPastePressed = false
        updateQuickPasteDisplay()
    }

    /// 纯文本粘贴修饰键按下状态
    func setIsPlainTextModifierPressed(_ pressed: Bool) {
        guard pressed != isPlainTextModifierPressed else { return }
        isPlainTextModifierPressed = pressed
        updatePlainTextIndicatorDisplay()
    }

    /// 选中并滚动到指定全局索引
    func selectAndScrollTo(index: Int) {
        selectRow(index)
        scrollTo(index: index)
    }

    /// 取得某项卡片的视图，用于预览锚点
    func anchorViewForItem(at index: Int) -> NSView {
        guard let indexPath = indexPath(forGlobal: index),
              let item = collectionView.item(at: indexPath) as? FloatingCollectionItem
        else { return collectionView }
        return item.cardView
    }

    /// 粘贴某项
    func pasteItem(at index: Int, isAttribute: Bool = true) {
        guard index < dataList.count else { return }
        ClipActionService.shared.paste(
            dataList[index],
            isAttribute: isAttribute,
            checkPermissions: PasteUserDefaults.pasteDirect,
            showTip: !PasteUserDefaults.pasteDirect
        )
    }

    /// 复制某项
    func copyItem(at index: Int) {
        guard index < dataList.count else { return }
        ClipActionService.shared.copy(dataList[index], showTip: true)
    }

    /// 请求删除某项（多选时二次确认）
    func requestDelete(at index: Int) {
        let items = selectedModels
        guard items.count <= 1 else {
            confirmDeleteMultiple(items, at: index)
            return
        }
        guard index < dataList.count else { return }
        deleteSingle(dataList[index])
    }

    /// 打开编辑窗口
    func openEditWindow(at index: Int) {
        guard index < dataList.count else { return }
        let item = dataList[index]
        guard item.pasteboardType.isText() else { return }
        EditWindowController.shared.openWindow(with: item)
    }

    /// 激活搜索框
    func activateSearchField(with text: String?) {
        onActivateSearch?(text)
    }

    /// 当前选中的条目
    var selectedModels: [PasteboardModel] {
        collectionView.selectionIndexPaths
            .compactMap { globalIndex(for: $0) }
            .sorted()
            .compactMap { $0 < dataList.count ? dataList[$0] : nil }
    }
}

// MARK: - Index Mapping

extension FloatingHistoryView {
    /// 全局索引 → IndexPath
    func indexPath(forGlobal index: Int) -> IndexPath? {
        var offset = 0
        for (section, group) in sections.enumerated() {
            if index < offset + group.items.count {
                return IndexPath(item: index - offset, section: section)
            }
            offset += group.items.count
        }
        return nil
    }

    /// IndexPath → 全局索引
    func globalIndex(for indexPath: IndexPath) -> Int? {
        guard indexPath.section < sections.count else { return nil }
        let offset = sections.prefix(indexPath.section).reduce(0) { $0 + $1.items.count }
        return offset + indexPath.item
    }

    /// 条目在分组中的模型
    func model(at indexPath: IndexPath) -> PasteboardModel? {
        guard indexPath.section < sections.count,
              indexPath.item < sections[indexPath.section].items.count
        else { return nil }
        return sections[indexPath.section].items[indexPath.item]
    }

    /// 快捷粘贴序号：前 9 项始终展示，和参考列表右侧数字一致
    func quickPasteDisplayIndex(forGlobal index: Int) -> Int? {
        guard index < 9 else { return nil }
        return index + 1
    }
}

// MARK: - Selection

private extension FloatingHistoryView {
    /// 多选删除确认
    func confirmDeleteMultiple(_ items: [PasteboardModel], at index: Int) {
        guard NSAlert.runConfirm(
            title: String(localized: .deleteTitle),
            message: String(localized: .deleteMessage)
        ) else { return }
        let minIndex = collectionView.selectionIndexPaths
            .compactMap { globalIndex(for: $0) }
            .min() ?? index
        let countAfterDelete = dataList.count - items.count
        if countAfterDelete > 0 {
            selectedIndex = min(minIndex, countAfterDelete - 1)
        }
        dataStore.deleteItems(items)
    }

    /// 单条删除
    func deleteSingle(_ item: PasteboardModel) {
        guard PasteUserDefaults.delConfirm else {
            dataStore.deleteItems(item)
            return
        }
        guard NSAlert.runConfirm(
            title: String(localized: .deleteTitle),
            message: String(localized: .deleteMessage)
        ) else { return }
        dataStore.deleteItems(item)
    }
}

// MARK: - Presenter Wiring

private extension FloatingHistoryView {
    /// 配置数据变化回调
    func configurePresenter() {
        presenter.applyFull = { [weak self] items, animating, completion in
            guard let self else { return }
            dataList = items
            applySnapshot(animating: animating)
            completion?()
        }
        presenter.appendItems = { [weak self] newItems in
            guard let self else { return }
            appendItems(newItems)
        }
        setupReorder()
        presenter.currentSnapshotItems = { [weak self] in self?.dataList ?? [] }
        presenter.resetSelection = { [weak self] in self?.resetToFirst() }
        presenter.restoreSelection = { [weak self] in self?.restoreSelection() }
        presenter.adjustAfterDelete = { [weak self] in self?.adjustSelectionAfterDelete() }
        presenter.updateEmptyState = { [weak self] isEmpty in
            self?.emptyStateView.isHidden = !isEmpty
        }
        presenter.reconfigureItems = { [weak self] items in
            self?.reconfigure(items)
        }
        presenter.isVerticalScroll = true
        presenter.loadMoreThreshold = (estimatedCardHeight + cardSpacing) * 5
        presenter.startObserving(scrollView: scrollView)
    }

    /// 追加新条目
    func appendItems(_ newItems: [PasteboardModel]) {
        let existing = Set(dataList.map(\.uniqueId))
        let appended = newItems.filter { !existing.contains($0.uniqueId) }
        guard !appended.isEmpty else { return }
        dataList.append(contentsOf: appended)
        applySnapshot()
        restoreSelection()
    }

    /// 监听分类内容变化，刷新行内分类标记
    func observeChipContentChanges() {
        CategoryChipStore.shared.chipsContentDidChange
            .sink { [weak self] in
                guard let self else { return }
                presenter.reconfigureItems(dataList)
            }
            .store(in: &cancellables)
    }

    /// 让列表获得焦点
    func focusCollection() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(collectionView)
        }
    }

    /// 强制刷新指定条目的内容
    func reconfigure(_ items: [PasteboardModel]) {
        let focused = env.focusRegion == .collection
        for item in items {
            guard let indexPath = dataSource.indexPath(for: item),
                  let global = globalIndex(for: indexPath),
                  let cell = collectionView.item(at: indexPath) as? FloatingCollectionItem
            else { continue }
            cell.configure(
                with: item,
                keyword: topVM?.query ?? "",
                isFocused: focused,
                quickPasteIndex: quickPasteDisplayIndex(forGlobal: global),
                displayMode: displayMode,
                showsImagePreview: showsImageList
            )
        }
    }

    /// 调整顺序后重建快照
    func setupReorder() {
        presenter.applyReorder = { [weak self] items in
            guard let self else { return }
            let selectedID = dataList.indices.contains(selectedIndex) ? dataList[selectedIndex].id : nil
            dataList = items
            selectedIndex = items.firstIndex { $0.id == selectedID } ?? 0
            applySnapshot(animating: true)
            restoreSelection()
            updateQuickPasteDisplay()
        }
    }
}

// MARK: - NSCollectionViewDelegate

extension FloatingHistoryView: NSCollectionViewDelegateFlowLayout {
    /// 图片标签按单张图片比例计算大图行高，其他标签保持原有固定行高。
    func collectionView(
        _: NSCollectionView,
        layout _: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let width = max(1, scrollView.contentSize.width - scrollInsets.left - scrollInsets.right)
        guard showsImageList, let model = model(at: indexPath), model.type == .image else {
            return NSSize(width: width, height: displayMode.cardHeight)
        }
        return NSSize(width: width, height: FloatingTheme.imageCardHeight(for: model.cachedImageSize, width: width))
    }

    func collectionView(
        _: NSCollectionView,
        shouldSelectItemsAt indexPaths: Set<IndexPath>
    ) -> Set<IndexPath> {
        if collectionView.handlesShiftSelection { return [] }
        if let first = indexPaths.min(), let global = globalIndex(for: first) {
            selectedIndex = global
        }
        return indexPaths
    }

    func collectionView(
        _: NSCollectionView,
        canDragItemsAt _: Set<IndexPath>,
        with _: NSEvent
    ) -> Bool {
        true
    }

    func collectionView(
        _: NSCollectionView,
        shouldDeselectItemsAt indexPaths: Set<IndexPath>
    ) -> Set<IndexPath> {
        collectionView.handlesShiftSelection ? [] : indexPaths
    }

    func collectionView(
        _: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        model(at: indexPath)?.writeItem
    }

    func collectionView(
        _: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath _: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation _: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard !(draggingInfo.draggingSource is NSCollectionView) else { return [] }
        let pasteboard = draggingInfo.draggingPasteboard
        guard pasteboard.canReadItem(withDataConformingToTypes: Self.dropSupportedTypes) else { return [] }
        dragSourceApp = NSWorkspace.shared.frontmostApplication
        return .copy
    }

    func collectionView(
        _: NSCollectionView,
        acceptDrop draggingInfo: any NSDraggingInfo,
        indexPath _: IndexPath,
        dropOperation _: NSCollectionView.DropOperation
    ) -> Bool {
        let accepted = dataStore.addNewItem(
            draggingInfo.draggingPasteboard,
            sourceApp: dragSourceApp,
            chipId: CategoryChipStore.shared.getSelectChipId()
        )
        dragSourceApp = nil
        return accepted
    }

    private static let dropSupportedTypes = PasteboardType.supportTypes.map(\.rawValue)

    /// 点击后重置为单选
    func resetSelectIndex(_ indexPath: IndexPath) {
        guard let global = globalIndex(for: indexPath) else { return }
        selectedIndex = global
        collectionView.selectionIndexPaths = [indexPath]
        scrollTo(index: global)
    }
}

// MARK: - NSGestureRecognizerDelegate

extension FloatingHistoryView: NSGestureRecognizerDelegate {
    func gestureRecognizer(
        _: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        guard let hitView = window?.contentView?.hitTest(event.locationInWindow)
        else { return true }
        return !hitView.isDescendant(of: collectionView)
    }

    @objc func handleBackgroundClick(_: NSClickGestureRecognizer) {
        setFocusRegion(.collection)
        window?.makeFirstResponder(collectionView)
    }
}
