import AppKit
import Combine
import SnapKit

// MARK: - FloatingSearchField

/// 无边框搜索输入框：外观交由外层容器绘制，仅保留文本编辑能力
final class FloatingSearchField: NSSearchField {
    /// 当前输入文本（供外部订阅）
    @Published private(set) var text: String = ""
    /// 获得第一响应者
    var onBecomeFirstResponder: (() -> Void)?
    /// 焦点变化
    var onFocusChange: ((Bool) -> Void)?
    /// 点击系统取消按钮
    var onCancelRequested: (() -> Void)?

    override var stringValue: String {
        didSet {
            if stringValue != text {
                text = stringValue
            }
        }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        text = stringValue
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onBecomeFirstResponder?()
            onFocusChange?(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            onFocusChange?(false)
        }
        return result
    }

    // MARK: - Setup

    /// 去掉系统边框、底色与放大镜，交由容器统一绘制
    private func configureAppearance() {
        placeholderString = String(localized: .search)
        font = FloatingTheme.searchFont
        setAccessibilityLabel(String(localized: .search))
        isBordered = false
        drawsBackground = false
        bezelStyle = .roundedBezel
        focusRingType = .none
        controlSize = .regular
        cell?.usesSingleLineMode = true

        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        (cell as? NSSearchFieldCell)?.cancelButtonCell?.target = self
        (cell as? NSSearchFieldCell)?.cancelButtonCell?.action = #selector(handleCancel)
    }

    @objc private func handleCancel() {
        stringValue = ""
        text = ""
        onCancelRequested?()
    }
}

// MARK: - FloatingDragHandle

/// 顶部拖拽区：居中的短横条，按住可拖动窗口
final class FloatingDragHandle: NSView {
    private let pill = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 2.5
        pill.layer?.cornerCurve = .continuous
        addSubview(pill)
        pill.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(8)
            make.width.equalTo(44)
            make.height.equalTo(5)
        }
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    /// 刷新拖拽条配色
    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pill.layer?.backgroundColor = NSColor.secondaryLabelColor
                .withAlphaComponent(0.45).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - FloatingPinButton

/// 标题栏 Pin 按钮：控制窗口是否常驻
final class FloatingPinButton: NSButton {
    private(set) var isPinned = false {
        didSet { updateAppearance() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// 配置独立置顶按钮的点击区域与行为
    private func setup() {
        isBordered = false
        imageScaling = .scaleNone
        target = self
        action = #selector(togglePinned)
        toolTip = String(localized: .pin)
        updateAppearance()
        snp.makeConstraints { make in
            make.width.height.equalTo(FloatingTheme.headerButtonSize)
        }
    }

    /// 切换窗口常驻状态并同步辅助功能说明
    @objc func togglePinned() {
        isPinned.toggle()
        ClipFloatingWindowController.shared.isPinned = isPinned
        toolTip = String(localized: isPinned ? .unpin : .pin)
        setAccessibilityLabel(toolTip)
    }

    /// 刷新图标与强调色
    private func updateAppearance() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        setAccessibilityLabel(String(localized: isPinned ? .unpin : .pin))
    }
}
