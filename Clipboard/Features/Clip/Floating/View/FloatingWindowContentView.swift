//
//  FloatingWindowContentView.swift
//  Clipboard
//
//  浮动窗口主容器：背景 + Header + HistoryView + Footer 的布局与数据编排
//

import AppKit
import Combine
import SnapKit

final class FloatingWindowContentView: NSView {
    // MARK: - Subviews

    /// 整窗一层毛玻璃，模糊窗口背后的桌面
    private let effectView: NSVisualEffectView = {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        return effect
    }()

    private let container = NSView()
    private let glassTintLayer = CALayer()
    private let glassHighlightLayer = CAGradientLayer()
    let headerView = FloatingHeaderView()
    let historyView = FloatingHistoryView()
    let footerView = FloatingFooterView()

    // MARK: - State

    let topVM = TopBarViewModel()
    private(set) var displayMode: FloatingDisplayMode = .standard
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// 初始化玻璃容器及顶部、列表、底部区域
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 切换标准 / 简洁模式
    func setDisplayMode(_ mode: FloatingDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        // 保存用户选择后同步三个区域的显示模式与窗口尺寸。
        UserDefaults.standard.set(mode.rawValue, forKey: PrefKey.floatMode.rawValue)
        headerView.setDisplayMode(mode)
        footerView.displayMode = mode
        headerView.snp.updateConstraints { $0.height.equalTo(mode.headerHeight) }
        footerView.snp.updateConstraints { $0.height.equalTo(mode.footerHeight) }
        historyView.setDisplayMode(mode)
        resizeWindow(for: mode)
        layoutSubtreeIfNeeded()
        historyView.scrollTo(index: historyView.selectedIndex)
    }

    /// 重置过滤与滚动状态
    func resetState() {
        topVM.resetFilterState()
        headerView.clearSearch()
        headerView.reloadChips()
        PasteDataStore.main.resetToDefault()
        historyView.setFocusRegion(.collection)
        window?.makeFirstResponder(historyView.collectionView)
    }

    // MARK: - Setup

    /// 搭建浮窗层级并绑定现有数据与交互
    private func setup() {
        wantsLayer = true
        addSubview(effectView)
        effectView.snp.makeConstraints { $0.edges.equalToSuperview() }
        // 玻璃叠层位于内容下方，维持桌面模糊与文字可读性。
        setupGlassLayers()

        effectView.addSubview(container)
        container.snp.makeConstraints { $0.edges.equalToSuperview() }

        container.addSubview(historyView)
        container.addSubview(headerView)
        container.addSubview(footerView)

        headerView.configure(topVM: topVM)
        historyView.configure(topVM: topVM)
        footerView.configure(topVM: topVM)

        bindCallbacks()
        bindDataFlow()
        layoutSubviews()
    }

    /// 使用轻微叠色、高光与细描边呈现整窗磨砂玻璃
    private func setupGlassLayers() {
        effectView.layer?.addSublayer(glassTintLayer)
        effectView.layer?.addSublayer(glassHighlightLayer)
        glassHighlightLayer.locations = [0, 0.45, 1]
        glassHighlightLayer.startPoint = CGPoint(x: 0, y: 1)
        glassHighlightLayer.endPoint = CGPoint(x: 1, y: 0)
        effectView.layer?.borderWidth = 0.75
        updateGlassAppearance()
    }

    /// 根据实际窗口大小铺满玻璃叠色，禁止布局触发隐式动画
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassTintLayer.frame = effectView.bounds
        glassHighlightLayer.frame = effectView.bounds
        CATransaction.commit()
    }

    /// 系统外观变化时同步玻璃叠色
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlassAppearance()
    }

    /// 玻璃边缘高光保持轻盈，让底部桌面颜色自然透出
    private func updateGlassAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            glassTintLayer.backgroundColor = FloatingTheme.glassTint().cgColor
            glassHighlightLayer.colors = [
                NSColor.white.withAlphaComponent(0.10).cgColor,
                NSColor.white.withAlphaComponent(0.015).cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor,
            ]
            effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        }
    }

    /// 视图之间的交互回调
    private func bindCallbacks() {
        footerView.onDisplayModeChanged = { [weak self] mode in
            self?.setDisplayMode(mode)
        }
        footerView.onOpenSettings = {
            SettingWindowController.shared.toggleWindow()
        }
        footerView.onBackgroundClick = { [weak self] in
            self?.focusCollection()
        }
        historyView.onActivateSearch = { [weak self] text in
            self?.headerView.activateSearch(with: text)
        }
        historyView.onCreateChip = { [weak self] model in
            self?.headerView.startCreatingChip(pinModel: model)
        }
        headerView.onSearchBecameFirstResponder = { [weak self] in
            self?.historyView.setFocusRegion(.search)
        }
        headerView.onChipEditingFocusChange = { [weak self] focused in
            self?.historyView.setFocusRegion(focused ? .chipEditing : .collection)
        }
        headerView.onChipSelected = { [weak self] in
            self?.focusCollection()
        }
    }

    /// 数据与筛选变化订阅
    private func bindDataFlow() {
        PasteDataStore.main.dataList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.footerView.updateCount() }
            .store(in: &cancellables)

        topVM.filterDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                topVM.performSearch()
                headerView.updateChipSelection()
            }
            .store(in: &cancellables)

        // 在主线程同步清空输入框，让重新呼出和快捷指令及时替换待执行的搜索。
        topVM.clearQueryRequested
            .sink { [weak self] in
                self?.headerView.resetSearchFieldOnly()
            }
            .store(in: &cancellables)
    }

    /// 让列表获得键盘焦点
    private func focusCollection() {
        historyView.setFocusRegion(.collection)
        window?.makeFirstResponder(historyView.collectionView)
    }

    /// 毛玻璃自身裁成圆角，避免父层 mask 把模糊采样盖掉
    func applyWindowCornerRadius(_ radius: CGFloat) {
        effectView.layer?.cornerRadius = radius
    }

    /// 依据显示模式调整窗口尺寸
    private func resizeWindow(for mode: FloatingDisplayMode) {
        guard let window else { return }
        applyWindowCornerRadius(mode.windowRadius)
        window.contentMinSize = mode == .standard ? FloatingTheme.minimumWindowSize : mode.windowSize
        var frame = window.frame
        frame.origin.y = frame.maxY - mode.windowSize.height
        frame.size = mode.windowSize
        if let screen = window.screen {
            frame.size.width = min(frame.width, screen.visibleFrame.width)
            frame.size.height = min(frame.height, screen.visibleFrame.height)
            frame.origin.y = max(screen.visibleFrame.minY, frame.origin.y)
            frame.origin.x = min(max(screen.visibleFrame.minX, frame.minX), screen.visibleFrame.maxX - frame.width)
        }
        window.setFrame(frame, display: true)
    }

    /// 顶部与底部固定高度，历史列表填满中间区域
    private func layoutSubviews() {
        historyView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(container)
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
        }

        headerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(container)
            make.height.equalTo(FloatingDisplayMode.standard.headerHeight)
        }

        footerView.snp.makeConstraints { make in
            make.bottom.leading.trailing.equalTo(container)
            make.height.equalTo(FloatingDisplayMode.standard.footerHeight)
        }
    }
}
