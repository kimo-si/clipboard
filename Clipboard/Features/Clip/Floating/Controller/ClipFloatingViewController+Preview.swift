//
//  ClipFloatingViewController+Preview.swift
//  Clipboard
//
//  Created by crown on 2026/5/5.
//

import AppKit

extension ClipFloatingViewController {
    /// 将当前可见图片映射到实时索引，复用空格预览且保留手动预览。
    func showImageHoverPreview(at indexPath: IndexPath) -> ClipPreviewPopover? {
        let historyView = floatingContentView.historyView
        guard previewPopover == nil,
              let model = historyView.dataSource.itemIdentifier(for: indexPath), model.type == .image,
              let index = historyView.dataList.firstIndex(where: { $0.uniqueId == model.uniqueId }),
              historyView.collectionView.item(at: indexPath) != nil else { return nil }
        // 打开悬停图片时不改变选中项，键盘粘贴目标保持不变。
        openPreview(at: index)
        return previewPopover
    }

    func togglePreview(at index: Int) {
        if previewPopover != nil {
            closePreview()
        } else {
            openPreview(at: index)
        }
    }

    func openPreview(at index: Int) {
        let historyView = floatingContentView.historyView
        guard historyView.dataList.indices.contains(index) else { return }
        let model = historyView.dataList[index]
        let anchorView = historyView.anchorViewForItem(at: index)

        let maxHeight: CGFloat
        let preferredEdge: NSRectEdge
        if let window = anchorView.window, let screen = window.screen {
            maxHeight = screen.visibleFrame.height
            let anchorOnScreen = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
            let spaceRight = screen.visibleFrame.maxX - anchorOnScreen.maxX
            let spaceLeft = anchorOnScreen.minX - screen.visibleFrame.minX
            preferredEdge = spaceRight >= spaceLeft ? .maxX : .minX
        } else {
            maxHeight = Const.maxPreviewHeight
            preferredEdge = .maxX
        }

        closePreview()
        let popover = ClipPreviewPopover(model: model, maxHeight: maxHeight) { [weak self] in
            self?.focusRegion = .popover
        }
        popover.onPinToChip = { [weak self] model, chipId in
            _ = self?.floatingContentView.topVM.assignModelToChip(model: model, chipId: chipId)
        }
        popover.onUnpin = { [weak self] model in
            _ = self?.floatingContentView.topVM.assignModelToChip(model: model, chipId: -1)
        }
        popover.onCreateChip = { [weak self] model in
            self?.closePreview()
            self?.floatingContentView.headerView.startCreatingChip(pinModel: model)
        }
        popover.delegate = self
        previewPopover = popover
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: preferredEdge)
    }

    func closePreview() {
        guard let popover = previewPopover else { return }
        previewPopover = nil
        popover.cleanup()
        popover.close()
        if focusRegion == .popover {
            focusRegion = .collection
        }
    }
}

// MARK: - NSPopoverDelegate

extension ClipFloatingViewController: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        guard let closing = notification.object as? ClipPreviewPopover,
              closing === previewPopover else { return }
        previewPopover = nil
        closing.cleanup()
        if focusRegion == .popover {
            focusRegion = .collection
        }
    }

    func popoverDidClose(_: Notification) {}
}
