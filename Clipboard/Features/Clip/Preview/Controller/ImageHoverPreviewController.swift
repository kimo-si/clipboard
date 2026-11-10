import AppKit

/// 在两种历史列表中共用图片悬停预览，独立管理延迟与自动收起。
final class ImageHoverPreviewController: NSResponder {
    private static let showDelay: Duration = .milliseconds(300)
    private static let dismissDelay: Duration = .milliseconds(180)

    private weak var collectionView: NSCollectionView?
    private let modelAt: (IndexPath) -> PasteboardModel?
    private let showPreview: (IndexPath) -> ClipPreviewPopover?
    private weak var popover: ClipPreviewPopover?
    private var collectionTracking: NSTrackingArea?
    private var previewTracking: NSTrackingArea?
    private var eventMonitor: Any?
    private var pendingTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var hoveredID: String?

    var isShowingPreview: Bool { popover?.isShown == true }

    /// 注入列表、实时模型查询与既有空格预览入口。
    init(
        collectionView: NSCollectionView,
        modelAt: @escaping (IndexPath) -> PasteboardModel?,
        showPreview: @escaping (IndexPath) -> ClipPreviewPopover?
    ) {
        self.collectionView = collectionView
        self.modelAt = modelAt
        self.showPreview = showPreview
        super.init()
    }

    /// 悬停控制器仅支持注入依赖创建。
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// 释放异步等待和事件监听，避免控制器销毁后继续响应。
    isolated deinit {
        pendingTask?.cancel()
        dismissTask?.cancel()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let collectionTracking { collectionView?.removeTrackingArea(collectionTracking) }
        if let previewTracking { popover?.contentViewController?.view.removeTrackingArea(previewTracking) }
    }

    /// 窗口显示时开始追踪；非激活浮窗也支持鼠标悬停。
    func start() {
        guard collectionTracking == nil, let collectionView else { return }
        collectionTracking = addTracking(to: collectionView)
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown, .leftMouseDragged]
        ) { [weak self] event in
            self?.handleInteraction(event)
            return event
        }
    }

    /// 窗口隐藏时撤销等待、悬停预览和事件监听。
    func stop() {
        reset()
        if let collectionTracking { collectionView?.removeTrackingArea(collectionTracking) }
        collectionTracking = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// 列表刷新时取消旧目标，只关闭由悬停打开的预览。
    func reset() {
        pendingTask?.cancel()
        pendingTask = nil
        cancelDismissal()
        hoveredID = nil
        // 释放悬停所有权后关闭，保留手动打开的预览。
        let previous = releasePreview()
        previous?.close()
    }

    /// 鼠标进入列表或预览时重新判断悬停目标。
    override func mouseEntered(with _: NSEvent) { updateHover() }

    /// 鼠标在列表中移动时按条目身份切换目标。
    override func mouseMoved(with _: NSEvent) { updateHover() }

    /// 离开列表时留出进入预览窗口的时间。
    override func mouseExited(with _: NSEvent) { updateHover() }

    /// 给列表或预览添加自动随可见区域更新的鼠标追踪。
    private func addTracking(to view: NSView) -> NSTrackingArea {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        return area
    }

    /// 仅接受鼠标下可见的图片，避免把文本或已复用条目自动展开。
    private func imageIndexPathUnderPointer() -> IndexPath? {
        guard let collectionView, let window = collectionView.window,
              window.isVisible, !collectionView.isHiddenOrHasHiddenAncestor,
              NSEvent.pressedMouseButtons == 0 else { return nil }
        let point = collectionView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard collectionView.visibleRect.contains(point),
              let path = collectionView.indexPathForItem(at: point),
              modelAt(path)?.type == .image else { return nil }
        return path
    }

    /// 判断鼠标是否进入当前悬停预览，便于继续查看和操作图片。
    private var isPointerInsidePreview: Bool {
        guard let popover, popover.isShown,
              let window = popover.contentViewController?.view.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    /// 切换图片时复用现有预览入口，离开时延迟关闭以跨过窗口间隙。
    private func updateHover() {
        if isPointerInsidePreview {
            cancelDismissal()
            return
        }
        guard let path = imageIndexPathUnderPointer(), let model = modelAt(path) else {
            scheduleDismissal()
            return
        }
        guard hoveredID != model.uniqueId else {
            if isShowingPreview { cancelDismissal() }
            return
        }
        reset()
        hoveredID = model.uniqueId
        // 延迟结束后再次查询当前位置和模型，防止滚动、搜索或复用导致错图。
        schedulePreview(at: path, expectedID: model.uniqueId)
    }

    /// 短暂停留后打开图片，快速划过时不会弹窗。
    private func schedulePreview(at path: IndexPath, expectedID: String) {
        pendingTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.showDelay) } catch { return }
            guard let self, imageIndexPathUnderPointer() == path,
                  modelAt(path)?.uniqueId == expectedID else { return }
            popover = showPreview(path)
            if let view = popover?.contentViewController?.view {
                previewTracking = addTracking(to: view)
            }
            pendingTask = nil
        }
    }

    /// 离开图片和预览后收起；进入预览时取消收起。
    private func scheduleDismissal() {
        pendingTask?.cancel()
        pendingTask = nil
        guard isShowingPreview else {
            hoveredID = nil
            return
        }
        guard dismissTask == nil else { return }
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.dismissDelay) } catch { return }
            guard let self else { return }
            dismissTask = nil
            guard !isPointerInsidePreview else { return }
            reset()
        }
    }

    /// 返回原图或进入预览时取消收起，避免窗口反复关闭与重开。
    private func cancelDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// 键盘与拖动取消待弹窗；在预览内点击后交给既有手动预览交互。
    private func handleInteraction(_ event: NSEvent) {
        if event.type == .keyDown {
            pendingTask?.cancel()
            return
        }
        if isPointerInsidePreview {
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                pendingTask?.cancel()
                cancelDismissal()
                _ = releasePreview()
            }
            return
        }
        reset()
    }

    /// 移除预览追踪并归还窗口，调用方决定关闭还是保留手动交互。
    private func releasePreview() -> ClipPreviewPopover? {
        let previous = popover
        if let previewTracking { previous?.contentViewController?.view.removeTrackingArea(previewTracking) }
        previewTracking = nil
        popover = nil
        return previous
    }
}
