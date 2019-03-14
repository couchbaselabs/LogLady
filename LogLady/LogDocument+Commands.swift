//
//  LogDocument+Commands.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/6/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Cocoa


extension LogDocument {

    var targetedRowIndexes : IndexSet {
        let clickedRow = _tableView.clickedRow
        let sel = _tableView.selectedRowIndexes
        if clickedRow < 0 || sel.contains(clickedRow) {
            return sel
        } else {
            return IndexSet(integer: clickedRow)
        }
    }

    var firstTargetedRow : Int? {
        var row = _tableView.clickedRow
        if row >= 0 {
            return row
        }
        row = _tableView.selectedRow
        if row >= 0 {
            return row
        }
        return nil
    }

    var firstTargetedEntry : LogEntry? {
        guard let row = self.firstTargetedRow else {
            return nil
        }
        return _entries[row]
    }

    var hasTargetedRows : Bool {
        return _tableView.selectedRow >= 0 || _tableView.clickedRow >= 0
    }


    //////// ACTIONS:


    @IBAction func copy(_ sender: AnyObject) {
        var lines = ""
        for row in self.targetedRowIndexes {
            lines += _entries[row].sourceLine + "\n"
        }
        NSLog("COPIED: \(lines)")

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines, forType: .string)
    }


    func selectNext(_ condition: (LogEntry)->Bool) {
        var row = (_tableView.selectedRowIndexes.last ?? -1) + 1
        for entry in _entries[row..<_entries.endIndex] {
            if condition(entry) {
                selectRow(row)
                return
            }
            row += 1
        }
        NSSound.beep()
    }

    func selectPrev(_ condition: (LogEntry)->Bool) {
        var row = (_tableView.selectedRowIndexes.first ?? _entries.count) - 1
        for entry in _entries[0...row].reversed() {
            if condition(entry) {
                selectRow(row)
                return
            }
            row -= 1
        }
        NSSound.beep()
    }

    func selectAll(_ condition: (LogEntry)->Bool) {
        var selected = IndexSet()
        var row = 0
        for entry in _entries {
            if condition(entry) {
                selected.insert(row)
            }
            row += 1
        }
        if selected.isEmpty {
            NSSound.beep()
            return
        }
        _tableView.selectRowIndexes(selected, byExtendingSelection: false)
        scrollSelectionIntoView()
    }



    ///// FLAGGING & SELECTING:


    @IBAction func flag(_ sender: AnyObject) {
        var state: Bool? = nil
        if let menu = sender as? NSMenuItem {
            if menu.title.count == 1 {
                _flagMarker = menu.title + " "
                state = true
            }
        }

        let indexes = self.targetedRowIndexes
        for row in indexes {
            let entry = _entries[row]
            if state == nil {
                state = !entry.flagged
            }
            entry.flagged = state!
            entry.flagMarker = state! ? _flagMarker : nil
            reloadRowBackground(row)
        }
        _tableView.reloadData(forRowIndexes: indexes,
                              columnIndexes: IndexSet(0..<_tableView.tableColumns.count))
    }

    var selectionIsFlagged : Bool {
        return self.firstTargetedEntry?.flagged ?? false
    }


    @IBAction func selectAllFlags(_ sender: AnyObject) {
        selectAll {$0.flagged}
    }

    @IBAction func selectNextFlag(_ sender: AnyObject) {
        selectNext {$0.flagged}
    }

    @IBAction func selectPrevFlag(_ sender: AnyObject) {
        selectPrev {$0.flagged}
    }


    @IBAction func selectNextWarning(_ sender: AnyObject) {
        selectNext {$0.level >= LogLevel.Warning}
    }

    @IBAction func selectPrevWarning(_ sender: AnyObject) {
        selectPrev {$0.level >= LogLevel.Warning}
    }


    @IBAction func jumpToSelection(_ sender: AnyObject) {
        scrollSelectionIntoView()
    }


    ///// FILTERING:


    func updateFilter(alwaysReload: Bool = false) {
        let filteredEntries = _allEntries[_filterRange].filter{ $0.matches(_filter) }
        if filteredEntries == _entries {
            if alwaysReload {
                _tableView.reloadData()
            }
            return
        }

        NSLog("Updating filtered rows!")
        let oldSel = IndexSet( _tableView.selectedRowIndexes.map { _entries[$0].index } )
        _tableView.deselectAll(nil)
        _textFinder.noteClientStringWillChange()

        _entries = filteredEntries
        _entryTextPos = nil
        _entryTextPosHint = nil
        _tableView.reloadData()

        var newSel = IndexSet()
        var row = 0
        for entry in _entries {
            if oldSel.contains(entry.index) {
                newSel.insert(row)
            }
            row += 1
        }
        _tableView.selectRowIndexes(newSel, byExtendingSelection: false)
        scrollSelectionIntoView()
    }


    @IBAction func clearFilters(_ sender: AnyObject) {
        _filter = LogFilter()
        _filterRange = 0 ..< _allEntries.count
        updateFilter()
    }


    @IBAction func filter(_ sender: AnyObject) {
        _filter.string = (sender as! NSSearchField).stringValue
        if let f = _filter.string, f.isEmpty {
            _filter.string = nil
        }
        updateFilter(alwaysReload: true)        // always update message highlight
    }


    @IBAction func toggleHideUnmarked(_ sender: AnyObject) {
        _filter.onlyMarked = !_filter.onlyMarked
        updateFilter()
    }


    @IBAction func toggleFocusObject(_ sender: AnyObject) {
        if _filter.object == nil {
            guard let row = self.targetedRowIndexes.first else {
                return
            }
            let entry = _entries[row]
            if let object = entry.object {
                _filter.object = Substring(object)
                updateFilter()
            }
        } else {
            _filter.object = nil
            updateFilter()
        }
    }


    @IBAction func filterLevels(_ sender: AnyObject) {
        let item = (sender as! NSPopUpButton).selectedItem!
        _filter.minLevel = LogLevel(rawValue: Int8(item.tag))!
        updateFilter()
    }


    @IBAction func filterDomain(_ sender: AnyObject) {
        let item = (sender as! NSPopUpButton).selectedItem!
        if item.tag == -2 {
            _filter.domains = nil
        } else {
            var domain: LogDomain? = nil
            if item.tag >= 0 {
                domain = LogDomain.named(item.title)
            }
            _filter.domains = [domain]
        }
        updateFilter()
    }


    //////// ROW RANGE FILTER:


    var filterRange : Range<Int> {
        get { return _filterRange }
        set {
            if newValue != _filterRange {
                _filterRange = newValue
                updateFilter()
            }
        }
    }


    @IBAction func filterToSelectedRows(_ sender: AnyObject) {
        let sel = _tableView.selectedRowIndexes
        guard !sel.isEmpty else {
            NSSound.beep()
            return
        }
        self.filterRange = Range(_entries[sel.first!].index ... _entries[sel.last!].index)
        _tableView.deselectAll(nil)
    }

    @IBAction func hideRowsBefore(_ sender: AnyObject) {
        if let first = self.targetedRowIndexes.first {
            self.filterRange = _entries[first].index ..< _filterRange.upperBound
        }
    }

    @IBAction func hideRowsAfter(_ sender: AnyObject) {
        if let last = self.targetedRowIndexes.last {
            self.filterRange = Range(_filterRange.lowerBound ... _entries[last].index)
        }
    }

    @IBAction func clearRowFilter(_ sender: AnyObject) {
        self.filterRange = 0 ..< _allEntries.count
    }


    //////// VALIDATION:


    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)),
             #selector(hideRowsBefore(_:)),
             #selector(hideRowsAfter(_:)):
            return self.hasTargetedRows
        case #selector(filterToSelectedRows(_:)),
             #selector(jumpToSelection(_:)):
            return _tableView.selectedRow >= 0
        case #selector(flag(_:)):
            titleMenuItem(item, title: self.selectionIsFlagged ? "Unflag" : "Flag")
            return self.hasTargetedRows
        case #selector(toggleHideUnmarked(_:)):
            checkMenuItem(item, checked: _filter.onlyMarked)
            return true
        case #selector(toggleFocusObject(_:)):
            let object = _filter.object ?? self.firstTargetedEntry?.object
            checkMenuItem(item, checked: _filter.object != nil)
            titleMenuItem(item, title: (object != nil ? "Focus On Object “\(object!)”" : "Focus On Object"))
            return object != nil
        case #selector(clearRowFilter(_:)):
            return (self.filterRange != 0 ..< _allEntries.count)
        case #selector(clearFilters(_:)):
            return (self.filterRange != 0 ..< _allEntries.count) || !_filter.isEmpty
        case #selector(performTextFinderAction(_:)):
            return _textFinder.validateAction(NSTextFinder.Action(rawValue: item.tag)!)
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    private func checkMenuItem(_ item: NSValidatedUserInterfaceItem, checked: Bool) {
        if let item = (item as? NSMenuItem) {
            item.state = (checked ? .on : .off)
        }
    }

    private func titleMenuItem(_ item: NSValidatedUserInterfaceItem, title: String) {
        if let item = (item as? NSMenuItem) {
            item.title = title
        }
    }

}
