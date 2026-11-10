//
//  FloatingFooterView.swift
//  Clipboard
//
//  浮动窗口底部：设置入口 + 居中项目总数 + 暂停指示器
//

import AppKit
import Combine
import SnapKit
import SwiftUI

// MARK: - FloatingFooterView

final class FloatingFooterView: NSView {
    // MARK: - Subviews

    private let settingsButton = FloatingHeaderIconButton(
        symbolName: "line.3.horizontal.decrease", pointSize: 19, side: FloatingTheme.headerButtonSize
    )
    private let countLabel = NSTextField(labelWithString: "")
    private let pauseButton = NSButton()
    private let pauseTimeLabel = NSTextField(labelWithString: "")
    private let pauseStack = PauseIndicatorStackView()

    // MARK: - State

    weak var topVM: TopBarViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?

    /// 当前显示模式
    var displayMode: FloatingDisplayMode = .standard {
        didSet {
            countLabel.font = .systemFont(
                ofSize: displayMode == .standard ? FloatingTheme.footerFont.pointSize : 12,
                weight: .regular
            )
        }
    }

    // MARK: - Callbacks

    var onBackgroundClick: (() -> Void)?
    var onDisplayModeChanged: ((FloatingDisplayMode) -> Void)?
    var onOpenSettings: (() -> Void)?

    // MARK: - Init

    /// 创建简洁的底部项目状态栏
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Public API

    /// 绑定 ViewModel 并跟踪暂停状态
    func configure(topVM: TopBarViewModel) {
        self.topVM = topVM
        PasteBoard.main.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePauseState() }
            .store(in: &cancellables)
        updateCount()
    }

    /// 刷新项目总数
    func updateCount() {
        let count = PasteDataStore.main.filteredCount
        countLabel.stringValue = String(localized: .itemCount(count))
    }

    // MARK: - Setup

    /// 布置设置入口、项目计数与暂停状态
    private func setup() {
        wantsLayer = true

        setupSettingsButton()
        setupCountLabel()
        setupPauseIndicator()
    }

    /// 设置入口按钮
    private func setupSettingsButton() {
        settingsButton.toolTip = String(localized: .settings)
        settingsButton.setAccessibilityLabel(String(localized: .settings))
        settingsButton.action = { [weak self] in
            self?.onOpenSettings?()
        }
        settingsButton.onRightClick = { [weak self] in
            self?.showDisplayModeMenu()
        }
        addSubview(settingsButton)
        settingsButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(FloatingTheme.horizontalPadding)
            make.centerY.equalToSuperview()
        }
    }

    /// 右键弹出显示模式切换菜单
    private func showDisplayModeMenu() {
        let menu = NSMenu()
        for mode in FloatingDisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = mode.rawValue
            item.state = mode == displayMode ? .on : .off
            menu.addItem(item)
        }
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: settingsButton)
        }
    }

    /// 切换用户从底部菜单选择的显示模式
    @objc private func selectDisplayMode(_ item: NSMenuItem) {
        guard let mode = FloatingDisplayMode(rawValue: item.tag) else { return }
        onDisplayModeChanged?(mode)
    }

    /// 中间项目计数
    private func setupCountLabel() {
        countLabel.font = FloatingTheme.footerFont
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .center
        addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    /// 暂停指示器
    private func setupPauseIndicator() {
        let pauseIcon = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        pauseIcon.image = NSImage(
            systemSymbolName: "pause.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(iconConfig)
        pauseIcon.contentTintColor = .controlAccentColor
        pauseIcon.imageScaling = .scaleNone
        pauseIcon.snp.makeConstraints { make in
            make.width.height.equalTo(12)
        }

        pauseTimeLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .medium
        )
        pauseTimeLabel.textColor = .secondaryLabelColor

        pauseStack.orientation = .horizontal
        pauseStack.alignment = .centerY
        pauseStack.spacing = Const.space4
        pauseStack.edgeInsets = NSEdgeInsets(
            top: Const.space2, left: Const.space6, bottom: Const.space2, right: Const.space6
        )
        pauseStack.addArrangedSubview(pauseIcon)
        pauseStack.addArrangedSubview(pauseTimeLabel)
        pauseStack.wantsLayer = true
        pauseStack.layer?.cornerRadius = Const.btnRadius
        pauseStack.layer?.cornerCurve = .continuous
        pauseStack.isHidden = true

        pauseButton.isBordered = false
        pauseButton.title = ""
        pauseButton.isHidden = true
        pauseButton.setAccessibilityLabel(String(localized: .resume))
        pauseButton.target = self
        pauseButton.action = #selector(resumePasteboard)

        addSubview(pauseStack)
        addSubview(pauseButton)
        pauseStack.snp.makeConstraints { make in
            make.leading.equalTo(settingsButton.snp.trailing).offset(Const.space4)
            make.centerY.equalToSuperview()
            make.height.equalTo(18)
        }
        pauseButton.snp.makeConstraints { make in
            make.edges.equalTo(pauseStack)
        }
    }

    // MARK: - Pause

    /// 刷新暂停态与计时
    private func updatePauseState() {
        guard let topVM else { return }
        let isPaused = PasteBoard.main.isPaused
        pauseStack.isHidden = !isPaused
        pauseButton.isHidden = !isPaused

        if isPaused {
            pauseTimeLabel.stringValue = topVM.formattedRemainingTime
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.pauseTimeLabel.stringValue = self?.topVM?.formattedRemainingTime ?? ""
                }
        } else {
            timerCancellable = nil
        }
        updatePauseBackground()
    }

    /// 刷新暂停胶囊底色
    private func updatePauseBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pauseStack.layer?.backgroundColor = NSColor.controlAccentColor
                .withAlphaComponent(0.1).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePauseBackground()
    }

    override func mouseDown(with _: NSEvent) {
        onBackgroundClick?()
    }

    @objc private func resumePasteboard() {
        topVM?.resume()
    }
}
