import AppKit
import Combine

extension TopBarViewModel {
    // MARK: - Search Methods

    /// 处理查询变化，支持快捷指令（如 @img, @text 等）
    func handleQueryChange() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        if trimmedQuery.hasPrefix("@"), displayModeRaw == 0 {
            let command = String(trimmedQuery.dropFirst()).lowercased()
            if let type = parseShortcutCommand(command) {
                query = ""
                clearQueryRequested.send()
                toggleType(type)
                return
            }
        }

        performSearch()
    }

    func parseShortcutCommand(_ command: String) -> PasteModelType? {
        switch command {
        case "img", "image", "图片": .image
        case "text", "txt", "文本": .string
        case "file", "文件": .file
        case "link", "链接": .link
        case "color", "颜色": .color
        case "rich", "富文本": .rich
        default: nil
        }
    }

    /// 重新呼出时清除本次搜索条件，保留当前分类标签的查询范围。
    func resetSearchForPresentation() {
        query = ""
        selectedTypes.removeAll()
        selectedAppIDs.removeAll()
        selectedDateFilter = nil
        selectedGroupIds.removeAll()
        tags.removeAll()
        if let chip = chipStore.getSelectedChip(), !chip.isSystem {
            selectedGroupIds.insert(chip.id)
            addTagForGroup(chip)
        }

        // 先同步清空输入框，替换尚在等待防抖的旧关键词。
        clearQueryRequested.send()
        filterDidChange.send()
        // 立即恢复当前标签的数据，并取消上次尚未完成的查询。
        performSearch()
    }

    func resetFilterState() {
        isModeResetting = true
        defer { isModeResetting = false }

        query = ""
        tags.removeAll()
        selectedTypes.removeAll()
        selectedAppIDs.removeAll()
        selectedDateFilter = nil
        selectedGroupIds.removeAll()

        if chipStore.selectedChipId != -1 {
            chipStore.selectedChipId = -1
        }

        lastSearchCriteria = nil
    }

    /// 统一构建搜索范围，自动分类与用户手动筛选互不覆盖。
    func makeSearchCriteria() -> SearchCriteria {
        SearchCriteria(
            keyword: query.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedTypes: selectedTypes,
            selectedAppIDs: selectedAppIDs,
            selectedDateFilter: selectedDateFilter,
            selectedGroupIds: selectedGroupIds,
            categoryType: chipStore.getSelectedChip()?.typeFilter
        )
    }

    /// 检查关键词、标签范围或手动筛选是否发生变化。
    func willSearchCriteriaChange() -> Bool {
        makeSearchCriteria() != lastSearchCriteria
    }

    /// 按当前分类范围刷新数据，全部标签使用原有完整历史列表。
    func performSearch() {
        let criteria = makeSearchCriteria()

        if criteria == lastSearchCriteria {
            return
        }
        lastSearchCriteria = criteria

        if criteria.isEmpty {
            store.resetToDefault()
        } else {
            store.searchData(criteria)
        }
    }
}

extension TopBarViewModel {
    // MARK: - Computed

    var pauseMenuTitle: String {
        guard PasteBoard.main.isPaused else { return String(localized: .pause) }
        guard let endTime = PasteBoard.main.pauseEndTime else { return String(localized: .paused) }
        return String(localized: .pauseUntil(pauseTimeString(from: endTime)))
    }

    var formattedRemainingTime: String {
        guard let endTime = PasteBoard.main.pauseEndTime else { return String(localized: .paused) }
        let remaining = max(0, endTime.timeIntervalSinceNow)
        guard remaining > 0 else { return String(localized: .paused) }
        return Duration.seconds(remaining).formatted(.time(pattern: .hourMinuteSecond))
    }

    // MARK: - Actions

    func resume() {
        PasteBoard.main.resume()
    }

    func pauseIndefinitely() {
        PasteBoard.main.pause()
    }

    func pause(for minutes: Int) {
        PasteBoard.main.pause(for: TimeInterval(minutes * 60))
    }

    // MARK: - Private

    func pauseTimeString(from date: Date) -> String {
        date.formatted(
            .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }
}

// MARK: - Drag & Drop

extension TopBarViewModel {
    /// 只允许将记录归入真实分组或取消归组，自动分类保持只读聚合。
    func assignModelToChip(model: PasteboardModel, chipId: Int) -> Bool {
        guard let chip = chipStore.chips.first(where: { $0.id == chipId }),
              chip.acceptsManualAssignment else { return false }
        if model.group == chipId {
            return true
        }

        guard let modelId = model.id else {
            return false
        }

        Task {
            await store.updateItemGroupInDB(id: modelId, groupId: chipId)
        }

        if !selectedGroupIds.isEmpty, !selectedGroupIds.contains(chipId) {
            var list = store.dataList.value
            list.removeAll(where: { $0.id == modelId })
            store.updateData(with: list, changeType: .delete)
        } else {
            if let model = store.dataList.value.first(where: { $0.id == modelId }),
               chipId != model.group {
                model.updateGroup(val: chipId)
            }
            store.updateData(with: store.dataList.value, changeType: .update)
        }

        return true
    }
}
