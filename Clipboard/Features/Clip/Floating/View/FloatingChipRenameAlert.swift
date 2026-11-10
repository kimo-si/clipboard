//
//  FloatingChipRenameAlert.swift
//  Clipboard
//
//  分类重命名弹窗：轻量内联输入，回车确认、Esc 取消。
//

import AppKit
import SnapKit

/// 分类重命名弹窗
final class FloatingChipRenameAlert: NSObject {
    // MARK: - State

    private let panel: NSPanel
    private let inputField = NSTextField()
    private let onCommit: (String) -> Void
    private let onCancel: () -> Void
    private var isFinished = false

    // MARK: - Init

    /// 创建重命名弹窗
    /// - Parameters:
    ///   - initialName: 初始名称
    ///   - title: 弹窗标题
    ///   - onCommit: 确认回调（已 trim）
    ///   - onCancel: 取消回调
    init(
        initialName: String,
        title: String,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCommit = onCommit
        self.onCancel = onCancel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 96),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel(title: title, initialName: initialName)
    }

    // MARK: - Public API

    /// 相对宿主窗口居中展示
    func present(over hostWindow: NSWindow?) {
        guard let hostWindow else {
            NSApp.activate(ignoringOtherApps: true)
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(inputField)
            return
        }
        let hostFrame = hostWindow.frame
        let origin = NSPoint(
            x: hostFrame.midX - panel.frame.width / 2,
            y: hostFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
        hostWindow.beginSheet(panel)
        panel.makeFirstResponder(inputField)
    }

    // MARK: - Setup

    /// 配置面板外观与输入框
    private func configurePanel(title: String, initialName: String) {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let contentView = NSView()
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Const.space16)
            make.top.equalToSuperview().offset(Const.space14)
        }

        inputField.stringValue = initialName
        inputField.font = .systemFont(ofSize: 13, weight: .regular)
        inputField.isBordered = false
        inputField.drawsBackground = true
        inputField.backgroundColor = .textBackgroundColor.withAlphaComponent(0.6)
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .none
        inputField.delegate = self
        contentView.addSubview(inputField)
        inputField.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Const.space16)
            make.top.equalTo(titleLabel.snp.bottom).offset(Const.space8)
            make.height.equalTo(26)
        }

        let hintLabel = NSTextField(labelWithString: String(localized: .renameHint))
        hintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor
        contentView.addSubview(hintLabel)
        hintLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Const.space16)
            make.top.equalTo(inputField.snp.bottom).offset(Const.space6)
        }
    }

    // MARK: - Finish

    /// 结束并回调结果
    private func finish(commit: Bool) {
        guard !isFinished else { return }
        isFinished = true
        let name = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostWindow = panel.sheetParent
        hostWindow?.endSheet(panel)
        panel.orderOut(nil)
        if commit, !name.isEmpty {
            onCommit(name)
        } else {
            onCancel()
        }
    }
}

// MARK: - NSTextFieldDelegate

extension FloatingChipRenameAlert: NSTextFieldDelegate {
    func control(
        _: NSControl,
        textView _: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finish(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(commit: false)
            return true
        default:
            return false
        }
    }
}

// MARK: - NSWindowDelegate

extension FloatingChipRenameAlert: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        guard !isFinished else { return }
        isFinished = true
        onCancel()
    }
}
