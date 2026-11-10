//
//  FloatingHeaderView.swift
//  Clipboard
//
//  浮动窗口顶部：拖拽条 + 搜索框 + 更多 + 分类胶囊
//

import AppKit
import Combine
import SnapKit
import Sparkle
import SwiftUI

// MARK: - FloatingHeaderView

final class FloatingHeaderView: NSView {
    // MARK: - Subviews

    let dragHandle = FloatingDragHandle()
    let pinButton = FloatingPinButton()
    let settingsBtn = FloatingHeaderIconButton(
        symbolName: "ellipsis", pointSize: 18, side: FloatingTheme.headerButtonSize
    )
    let searchContainer = FloatingSearchContainer()
    let tabBarView = FloatingTabBarView()

    /// 搜索输入框
    var searchField: FloatingSearchField { searchContainer.searchField }

    // MARK: - State

    weak var topVM: TopBarViewModel?
    private(set) var displayMode: FloatingDisplayMode = .standard
    private var cancellables = Set<AnyCancellable>()
    /// 分类重命名弹窗（需持有，否则 sheet 会随局部变量释放）
    var renameAlert: FloatingChipRenameAlert?

    // MARK: - Init

    /// 创建包含拖拽区、搜索行与分类栏的顶部视图
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 搜索框获得焦点
    var onSearchBecameFirstResponder: (() -> Void)?
    /// 分类切换完成
    var onChipSelected: (() -> Void)?
    /// 分类编辑焦点变化
    var onChipEditingFocusChange: ((Bool) -> Void)?

    /// 切换显示模式
    func setDisplayMode(_ mode: FloatingDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        let isStandard = mode == .standard
        dragHandle.snp.updateConstraints {
            $0.height.equalTo(isStandard ? FloatingTheme.dragHandleHeight : FloatingTheme.compactHeaderHeight)
        }
        searchContainer.setCompact(!isStandard)
        searchContainer.snp.updateConstraints {
            $0.height.equalTo(isStandard ? FloatingTheme.searchFieldHeight : FloatingTheme.compactSearchHeight)
        }
        tabBarView.snp.updateConstraints {
            $0.top.equalTo(searchContainer.snp.bottom).offset(
                isStandard ? FloatingTheme.searchToTabsSpacing : FloatingTheme.compactTabSpacing
            )
        }
        layoutSubtreeIfNeeded()
    }

    /// 判断视图是否不应触发「回到列表」手势
    func isExcludedFromFocusGesture(_ view: NSView) -> Bool {
        view === pinButton || view.isDescendant(of: pinButton) ||
            view === searchContainer || view.isDescendant(of: searchContainer) ||
            view === settingsBtn || view.isDescendant(of: settingsBtn) ||
            view === tabBarView || view.isDescendant(of: tabBarView)
    }

    /// 绑定 ViewModel 并渲染分类
    func configure(topVM: TopBarViewModel) {
        self.topVM = topVM
        reloadChips()
    }

    /// 搜索框是否为第一响应者
    var isSearchFieldFirstResponder: Bool {
        window?.firstResponder === searchField
    }

    /// 清空搜索
    func clearSearch() {
        searchField.stringValue = ""
        topVM?.setQuery(text: "")
    }

    /// 仅清空输入框文本，不重复改写查询状态（用于快捷指令清空场景）
    func resetSearchFieldOnly() {
        searchField.stringValue = ""
    }

    /// 激活搜索框并可选填入关键字
    func activateSearch(with text: String?) {
        window?.makeFirstResponder(searchField)
        guard let text, !text.isEmpty else { return }
        searchField.stringValue = text
        topVM?.setQuery(text: text)
        searchField.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
    }

    // MARK: - Setup

    /// 按参考图的三层结构搭建顶部控件
    private func setup() {
        wantsLayer = true

        addSubview(dragHandle)
        addSubview(pinButton)
        addSubview(searchContainer)
        addSubview(settingsBtn)
        addSubview(tabBarView)

        layoutDragHandle()
        layoutSearchRow()
        layoutTabRow()

        bindSearch()
        observeUpdateBadge()
    }

    /// 拖拽区布局
    private func layoutDragHandle() {
        dragHandle.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(FloatingTheme.dragHandleHeight)
        }
    }

    /// 搜索行独立排列置顶、胶囊搜索框与更多按钮
    private func layoutSearchRow() {
        bindSearchRowActions()
        pinButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(FloatingTheme.horizontalPadding)
            make.centerY.equalTo(searchContainer)
        }
        settingsBtn.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-FloatingTheme.horizontalPadding)
            make.centerY.equalTo(searchContainer)
        }
        searchContainer.snp.makeConstraints { make in
            make.leading.equalTo(pinButton.snp.trailing).offset(FloatingTheme.headerControlSpacing)
            make.trailing.equalTo(settingsBtn.snp.leading).offset(-FloatingTheme.headerControlSpacing)
            make.top.equalTo(dragHandle.snp.bottom)
            make.height.equalTo(FloatingTheme.searchFieldHeight)
        }
    }

    /// 绑定搜索焦点、清空操作和更多菜单
    private func bindSearchRowActions() {
        searchContainer.onBecomeFirstResponder = { [weak self] in
            self?.onSearchBecameFirstResponder?()
        }
        searchContainer.onCancelSearch = { [weak self] in
            self?.clearSearch()
        }
        settingsBtn.action = { [weak self] in self?.showSettingsMenu() }
        settingsBtn.setAccessibilityLabel(String(localized: .settings))
    }

    /// 分类行布局
    private func layoutTabRow() {
        tabBarView.onAddChip = { [weak self] in self?.startCreatingChip() }
        tabBarView.onSelectChip = { [weak self] id in
            self?.topVM?.setSelectChipId(chip: id)
            self?.onChipSelected?()
        }
        tabBarView.onRenameChip = { [weak self] chip in self?.handleRenameChip(chip) }
        tabBarView.onDeleteChip = { [weak self] chip in self?.confirmDeleteChip(chip) }
        tabBarView.onColorChange = { [weak self] chip, index in
            self?.topVM?.updateChip(chip, colorIndex: index)
            self?.reloadChips()
        }
        tabBarView.onDropToChip = { [weak self] model, chipId in
            self?.topVM?.assignModelToChip(model: model, chipId: chipId) ?? false
        }

        tabBarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(FloatingTheme.horizontalPadding)
            make.trailing.equalToSuperview().offset(-FloatingTheme.horizontalPadding)
            make.top.equalTo(searchContainer.snp.bottom).offset(FloatingTheme.searchToTabsSpacing)
            make.height.equalTo(FloatingTheme.tabBarHeight)
        }
    }

    /// 搜索框文字变化绑定
    private func bindSearch() {
        searchField.$text
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                topVM?.setQuery(text: text)
                topVM?.handleQueryChange()
            }
            .store(in: &cancellables)
    }

    /// 监听更新徽标
    func observeUpdateBadge() {
        withObservationTracking {
            settingsBtn.showBadge = UpdateManager.shared.hasUpdate
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeUpdateBadge()
            }
        }
    }

    // MARK: - Settings Menu

    /// 弹出设置菜单
    func showSettingsMenu() {
        let builder = TopBarMenuBuilder(target: self, topVM: topVM)
        let menu = builder.buildSettingsMenu()
        let pinItem = NSMenuItem(
            title: String(localized: pinButton.isPinned ? .unpin : .pin),
            action: #selector(FloatingPinButton.togglePinned),
            keyEquivalent: ""
        )
        pinItem.target = pinButton
        if #available(macOS 26.0, *) {
            pinItem.image = NSImage(
                systemSymbolName: pinButton.isPinned ? "pin.slash" : "pin",
                accessibilityDescription: nil
            )
        }
        menu.insertItem(pinItem, at: 0)
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: settingsBtn)
        }
    }
}

// MARK: - TopBarMenuActions

extension FloatingHeaderView: TopBarMenuActions {
    func openSettingsAction() {
        SettingWindowController.shared.toggleWindow()
    }

    func checkForUpdatesAction() {
        AppDelegate.shared?.updaterController.checkForUpdates(nil)
    }

    func invokeHelpAction() {
        if let url = URL(string: "https://github.com/Ineffable919/clipboard/blob/master/README.md") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNewTextItemAction() {
        EditWindowController.shared.openNewWindow()
    }

    func openAboutAction() {
        SettingWindowController.shared.toggleWindow(page: .about)
    }

    func resumePasteboardAction() {
        topVM?.resume()
    }

    func pauseIndefinitelyAction() {
        topVM?.pauseIndefinitely()
    }

    func pause15MinutesAction() {
        topVM?.pause(for: 15)
    }

    func pause30MinutesAction() {
        topVM?.pause(for: 30)
    }

    func pause1HourAction() {
        topVM?.pause(for: 60)
    }

    func pause3HoursAction() {
        topVM?.pause(for: 180)
    }

    func pause8HoursAction() {
        topVM?.pause(for: 480)
    }
}
