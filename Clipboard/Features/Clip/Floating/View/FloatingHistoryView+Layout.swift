import AppKit
import SnapKit

// MARK: - Setup & Data

extension FloatingHistoryView {
    /// 搭建列表视图
    func setup() {
        wantsLayer = true

        configureLayout()
        configureCollectionView()
        setupCallbacks()
        configureScrollView()
        addSubview(scrollView)

        setupSource()

        emptyStateView.isHidden = true
        addSubview(emptyStateView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyStateView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(Const.space16)
            make.trailing.lessThanOrEqualToSuperview().offset(-Const.space16)
        }
    }

    /// 配置流式布局与分组标题尺寸
    private func configureLayout() {
        collectionLayout.scrollDirection = .vertical
        collectionLayout.minimumInteritemSpacing = 0
        collectionLayout.minimumLineSpacing = FloatingTheme.rowSpacing
        collectionLayout.sectionInset = scrollInsets
        collectionLayout.itemSize = NSSize(
            width: FloatConst.cardSize,
            height: displayMode.cardHeight
        )
        collectionLayout.headerReferenceSize = .zero
    }

    /// 配置集合视图行为
    private func configureCollectionView() {
        collectionView.collectionViewLayout = collectionLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = false
        collectionView.allowsMultipleSelection = true
        collectionView.focusRingType = .none
        collectionView.delegate = self
        collectionView.register(
            FloatingCollectionItem.self,
            forItemWithIdentifier: FloatingCollectionItem.id
        )
        collectionView.register(
            FloatingSectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: FloatingHistoryView.sectionHeaderIdentifier
        )
        collectionView.registerForDraggedTypes(PasteboardType.supportTypes)
        collectionView.setDraggingSourceOperationMask(.every, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
    }

    /// 配置滚动视图
    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = collectionView
        scrollView.scrollerInsets = NSEdgeInsets(
            top: scrollInsets.top,
            left: 0,
            bottom: scrollInsets.bottom,
            right: 0
        )
    }

    /// 绑定交互回调
    private func setupCallbacks() {
        let clickGesture = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleBackgroundClick(_:))
        )
        clickGesture.buttonMask = 0x1
        clickGesture.delegate = self
        addGestureRecognizer(clickGesture)

        collectionView.onBecomeFirstResponder = { [weak self] in
            self?.setFocusRegion(.collection)
        }
        collectionView.onDragMoved = { [weak self] screenPoint in
            self?.handleDragMoved(screenPoint)
        }
        collectionView.onDragEnded = { [weak self] screenPoint in
            self?.handleDragEnded(screenPoint)
        }
        collectionView.onShiftClick = { [weak self] clickedPath in
            self?.handleShiftClick(clickedPath)
        }
        collectionView.onClick = { [weak self] indexPath in
            self?.resetSelectIndex(indexPath)
        }
    }

    /// Shift 范围选择
    private func handleShiftClick(_ clickedPath: IndexPath) {
        guard let target = globalIndex(for: clickedPath) else { return }
        let lower = min(selectedIndex, target)
        let upper = max(selectedIndex, target)
        var paths = Set<IndexPath>()
        for index in lower ... upper {
            if let path = indexPath(forGlobal: index) {
                paths.insert(path)
            }
        }
        collectionView.selectionIndexPaths = paths
        scrollTo(index: target)
    }

    // MARK: - Data Source

    /// 构建分组化的数据源
    private func setupSource() {
        dataSource = NSCollectionViewDiffableDataSource<Int, PasteboardModel>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, model in
            self?.makeItem(collectionView: collectionView, indexPath: indexPath, model: model)
        }
        // diffable data source 必须通过 supplementaryViewProvider 提供分组标题，
        // 走 delegate 的同名方法会被框架自身的实现覆盖并抛异常。
        dataSource.supplementaryViewProvider = {
            [weak self] (
                collectionView: NSCollectionView,
                kind: NSCollectionView.SupplementaryElementKind,
                indexPath: IndexPath
            ) -> (any NSView & NSCollectionViewElement)? in
            self?.makeSectionHeader(in: collectionView, kind: kind, at: indexPath)
        }
    }

    /// 构建时间分组标题
    private func makeSectionHeader(
        in collectionView: NSCollectionView,
        kind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> (any NSView & NSCollectionViewElement)? {
        // 必须走 makeSupplementaryView 复用已注册的类，且不能返回 nil，否则 AppKit 会抛异常
        guard let header = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: FloatingHistoryView.sectionHeaderIdentifier,
            for: indexPath
        ) as? FloatingSectionHeaderView else {
            return FloatingSectionHeaderView()
        }
        guard kind == NSCollectionView.elementKindSectionHeader,
              indexPath.section < sections.count
        else { return header }

        let section = sections[indexPath.section]
        header.configure(title: section.group.title, countText: section.countText)
        return header
    }

    /// 构建单个列表项
    private func makeItem(
        collectionView: NSCollectionView,
        indexPath: IndexPath,
        model: PasteboardModel
    ) -> NSCollectionViewItem? {
        guard let item = collectionView.makeItem(
            withIdentifier: FloatingCollectionItem.id,
            for: indexPath
        ) as? FloatingCollectionItem else { return nil }

        let global = globalIndex(for: indexPath) ?? 0
        item.configure(
            with: model,
            keyword: topVM?.query ?? "",
            isFocused: env.focusRegion == .collection,
            quickPasteIndex: quickPasteDisplayIndex(forGlobal: global),
            displayMode: displayMode,
            showsImagePreview: showsImageList
        )
        item.setShowPlainTextIndicator(isPlainTextModifierPressed)
        bindItemCallbacks(item, model: model)
        return item
    }

    /// 绑定列表项的粘贴/复制/编辑等回调
    private func bindItemCallbacks(_ item: FloatingCollectionItem, model: PasteboardModel) {
        item.onPaste = { [weak self] in
            self?.perform(for: model) { $0.pasteItem(at: $1) }
        }
        item.onPastePlainText = { [weak self] in
            self?.perform(for: model) { $0.pasteItem(at: $1, isAttribute: false) }
        }
        item.onCopy = { [weak self] in
            self?.perform(for: model) { $0.copyItem(at: $1) }
        }
        item.onEdit = { [weak self] in
            self?.perform(for: model) { $0.openEditWindow(at: $1) }
        }
        item.onDelete = { [weak self] in
            self?.perform(for: model) { $0.requestDelete(at: $1) }
        }
        item.onTogglePreview = { [weak self] in
            self?.perform(for: model) { $0.onTogglePreview?($1) }
        }
        item.onAssignToChip = { [weak self] chipId in
            self?.perform(for: model) { owner, _ in
                _ = owner.topVM?.assignModelToChip(model: model, chipId: chipId)
            }
        }
        item.onCreateChip = { [weak self] target in
            self?.onCreateChip?(target)
        }
    }

    /// 用模型反查最新全局索引后再执行动作，避免行复用导致索引错位
    private func perform(
        for model: PasteboardModel,
        action: @escaping (FloatingHistoryView, Int) -> Void
    ) {
        guard let index = dataList.firstIndex(where: { $0.uniqueId == model.uniqueId }) else { return }
        action(self, index)
    }

    // MARK: - Snapshot

    /// 平铺为单组，不插入今天 / 昨天标题
    func applySnapshot(animating: Bool = false) {
        // 快照变化时清除旧悬停目标，避免自动预览错误条目。
        onResetHoverPreview?()
        let layoutChanged = syncImageListLayout()
        if dataList.isEmpty {
            setSections([])
        } else {
            setSections([
                FloatingTimeGroupSection(group: .today, items: dataList)
            ])
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, PasteboardModel>()
        if let section = sections.first, !section.items.isEmpty {
            snapshot.appendSections([0])
            snapshot.appendItems(section.items, toSection: 0)
        }
        // 两个标签可能包含相同图片；显式重载交集，保证复用卡片切换布局。
        if layoutChanged {
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reloadItems(snapshot.itemIdentifiers.filter { existing.contains($0) })
        }
        dataSource.apply(snapshot, animatingDifferences: animating)
    }

    /// 重载所有可见项（显示模式变化时）
    func reloadAllItems() {
        // 显示模式切换会重建卡片，先收起原卡片的悬停预览。
        onResetHoverPreview?()
        let selectedPaths = collectionView.selectionIndexPaths
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            collectionView.selectionIndexPaths = selectedPaths
            updateSelectedItemBorder()
            updateQuickPasteDisplay()
        }
    }

    /// 选中第一项并回到顶部
    func resetToFirst() {
        guard !dataList.isEmpty else { return }
        selectRow(0)
        collectionView.scroll(.zero)
    }

    /// 删除后修正选中索引
    func adjustSelectionAfterDelete() {
        guard !dataList.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(selectedIndex, dataList.count - 1)
        restoreSelection()
        scrollTo(index: selectedIndex)
    }

    /// 恢复当前选中项
    func restoreSelection() {
        guard let path = indexPath(forGlobal: selectedIndex) else { return }
        collectionView.selectionIndexPaths = [path]
    }

    /// 选中指定全局索引
    func selectRow(_ index: Int) {
        guard index >= 0, index < dataList.count,
              let path = indexPath(forGlobal: index)
        else { return }
        selectedIndex = index
        collectionView.selectionIndexPaths = [path]
    }

    // MARK: - Scroll

    /// 判断当前是否为按住方向键的连续滚动
    private func event_isARepeat() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.type == .keyDown && event.isARepeat
    }

    /// 滚动到指定全局索引
    func scrollTo(index: Int) {
        guard let path = indexPath(forGlobal: index),
              let attrs = collectionView.layoutAttributesForItem(at: path),
              let clipView = collectionView.enclosingScrollView?.contentView
        else { return }

        let visibleRect = clipView.documentVisibleRect
        let topCover = scrollInsets.top - Const.selectionBorderWidth
        let bottomCover = scrollInsets.bottom
        let peek = showsImageList ? cardSpacing : displayMode.cardHeight / 3

        let effectiveMinY = visibleRect.minY + topCover + peek
        let effectiveMaxY = visibleRect.maxY - bottomCover - peek

        var newOriginY = visibleRect.origin.y
        if attrs.frame.minY < effectiveMinY {
            newOriginY = attrs.frame.minY - topCover - peek
        } else if attrs.frame.maxY > effectiveMaxY {
            newOriginY = attrs.frame.maxY + bottomCover + peek - visibleRect.height
        } else {
            return
        }

        let maxScrollY = max(0, collectionView.bounds.height - visibleRect.height)
        newOriginY = min(max(0, newOriginY), maxScrollY)

        let scrollView = clipView.enclosingScrollView
        if event_isARepeat() {
            clipView.setBoundsOrigin(NSPoint(x: 0, y: newOriginY))
            scrollView?.reflectScrolledClipView(clipView)
        } else {
            clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: newOriginY))
            scrollView?.reflectScrolledClipView(clipView)
        }
    }

    // MARK: - Quick Paste Display

    /// 刷新所有可见项的快捷粘贴提示
    func updateQuickPasteDisplay() {
        for case let item as FloatingCollectionItem in collectionView.visibleItems() {
            guard let path = collectionView.indexPath(for: item),
                  let global = globalIndex(for: path)
            else { continue }
            item.setQuickPasteIndex(quickPasteDisplayIndex(forGlobal: global))
        }
    }

    /// 刷新所有可见项的纯文本粘贴提示
    func updatePlainTextIndicatorDisplay() {
        for case let item as FloatingCollectionItem in collectionView.visibleItems() {
            item.setShowPlainTextIndicator(isPlainTextModifierPressed)
        }
    }
}
