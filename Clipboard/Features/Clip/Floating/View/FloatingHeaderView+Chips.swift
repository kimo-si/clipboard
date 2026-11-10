//
//  FloatingHeaderView+Chips.swift
//  Clipboard
//
//  浮动窗口分类 Tab 的重载、重命名与删除逻辑。
//

import AppKit
import SnapKit

extension FloatingHeaderView {
    // MARK: - Reload

    /// 依据 ViewModel 重建分类 Tab
    func reloadChips() {
        guard let topVM else { return }
        tabBarView.reload(
            chips: topVM.chips(),
            selectedId: topVM.getSelectChipId()
        )
    }

    /// 仅同步 Tab 选中态
    func updateChipSelection() {
        guard let topVM else { return }
        tabBarView.updateSelection(topVM.getSelectChipId())
    }

    /// 提交键盘编辑（Enter）
    func commitKeyboardEditing() {
        guard let topVM else { return }
        if topVM.editingNewChip {
            commitNewChip()
        } else if topVM.editingChipId != nil {
            topVM.commitEditingChip()
            reloadChips()
        }
    }

    /// 取消键盘编辑（Esc）
    func cancelKeyboardEditing() {
        guard let topVM else { return }
        if topVM.editingNewChip {
            cancelNewChip()
        } else if topVM.editingChipId != nil {
            topVM.cancelEditingChip()
            reloadChips()
        }
    }

    // MARK: - Create

    /// 新建分类（无预置内容）
    func startCreatingChip() {
        startCreatingChip(pinModel: nil)
    }

    /// 新建分类，并可把某条内容直接归入新分类
    func startCreatingChip(pinModel: PasteboardModel?) {
        guard let topVM else { return }
        if topVM.editingNewChip {
            commitNewChip()
        }
        if topVM.editingChipId != nil {
            topVM.commitEditingChip()
        }
        topVM.editingNewChip = true
        topVM.newChipName = String(localized: .untitled)
        topVM.pendingPinModel = pinModel
        presentInlineRename(name: topVM.newChipName, isNew: true)
    }

    /// 提交新建分类
    func commitNewChip() {
        endNewChip(commit: true)
    }

    /// 取消新建分类
    func cancelNewChip() {
        endNewChip(commit: false)
    }

    /// 结束新建流程
    private func endNewChip(commit: Bool) {
        guard let topVM, topVM.editingNewChip else { return }
        topVM.editingNewChip = false
        topVM.commitNewChipOrCancel(commitIfNonEmpty: commit)
        reloadChips()
        if commit {
            onChipSelected?()
        }
    }

    // MARK: - Rename

    /// 进入分类重命名
    func handleRenameChip(_ chip: CategoryChip) {
        guard let topVM, !chip.isSystem else { return }
        topVM.startEditingChip(chip)
        presentInlineRename(name: chip.name, isNew: false)
    }

    /// 弹出内联重命名输入框
    private func presentInlineRename(name: String, isNew: Bool) {
        // 弹窗需由视图持有，否则 sheet 会随局部变量释放而失效
        renameAlert = FloatingChipRenameAlert(
            initialName: name,
            title: String(localized: isNew ? .untitled : .rename)
        ) { [weak self] newName in
            guard let self, let topVM else { return }
            renameAlert = nil
            if isNew {
                topVM.newChipName = newName
                commitNewChip()
            } else {
                topVM.editingChipName = newName
                topVM.commitEditingChip()
                reloadChips()
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            renameAlert = nil
            if isNew {
                cancelNewChip()
            } else {
                topVM?.cancelEditingChip()
                reloadChips()
            }
        }
        renameAlert?.present(over: window)
    }

    // MARK: - Delete

    /// 删除分类（有内容时二次确认）
    func confirmDeleteChip(_ chip: CategoryChip) {
        guard !chip.isSystem else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let count = await PasteDataStore.main.getCountByGroup(groupId: chip.id)
            if count == 0 {
                topVM?.removeChip(chip)
                reloadChips()
                return
            }
            guard NSAlert.runConfirm(
                title: String(localized: .deleteChipTitle(chip.name)),
                message: String(localized: .deleteChipMessage(chip.name))
            ) else { return }
            topVM?.removeChip(chip)
            reloadChips()
        }
    }
}
