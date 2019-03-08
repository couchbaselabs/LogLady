//
//  LogDocument+Commands.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/6/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Cocoa


extension LogDocument {

    @IBAction func copy(_ sender: AnyObject) {
        var lines = ""
        for row in _tableView.selectedRowIndexes {
            lines += _entries[row].sourceLine + "\n"
        }
        NSLog("COPIED: \(lines)")

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines, forType: NSPasteboard.PasteboardType.string)
    }


    ///// FLAGGING:


    @IBAction func flag(_ sender: AnyObject) {
        let indexes = _tableView.selectedRowIndexes
        var state: Bool? = nil
        for row in indexes {
            let entry = _entries[row]
            if state == nil {
                state = !entry.flagged
            }
            entry.flagged = state!
            reloadRowBackground(row)
        }
        _tableView.reloadData(forRowIndexes: indexes,
                              columnIndexes: IndexSet(0..<_tableView.tableColumns.count))
    }


    @IBAction func selectAllFlags(_ sender: AnyObject) {
        var flagged = IndexSet()
        var row = 0
        for entry in _entries {
            if entry.flagged {
                flagged.insert(row)
            }
            row += 1
        }
        if flagged.isEmpty {
            NSSound.beep()
            return
        }
        _tableView.selectRowIndexes(flagged, byExtendingSelection: false)
        scrollSelectionIntoView()
    }


    @IBAction func selectNextFlag(_ sender: AnyObject) {
        var row = (_tableView.selectedRowIndexes.last ?? -1) + 1
        for entry in _entries[row..<_entries.endIndex] {
            if entry.flagged {
                selectRow(row)
                return
            }
            row += 1
        }
        NSSound.beep()
    }


    @IBAction func selectPrevFlag(_ sender: AnyObject) {
        var row = (_tableView.selectedRowIndexes.first ?? _entries.count) - 1
        for entry in _entries[0...row].reversed() {
            if entry.flagged {
                selectRow(row)
                return
            }
            row -= 1
        }
        NSSound.beep()
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
        if let first = _tableView.selectedRowIndexes.first {
            self.filterRange = _entries[first].index ..< _filterRange.upperBound
        }
    }

    @IBAction func hideRowsAfter(_ sender: AnyObject) {
        if let last = _tableView.selectedRowIndexes.last {
            self.filterRange = Range(_filterRange.lowerBound ... _entries[last].index)
        }
    }

    @IBAction func clearRowFilter(_ sender: AnyObject) {
        self.filterRange = 0 ..< _allEntries.count
    }


    //////// VALIDATION:


    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(flag(_:)), #selector(filterToSelectedRows(_:)),
        #selector(hideRowsBefore(_:)), #selector(hideRowsAfter(_:)):
            return _tableView.selectedRow >= 0
        case #selector(toggleHideUnmarked(_:)):
            (item as? NSMenuItem)?.state = (_filter.onlyMarked ? NSControl.StateValue.on : NSControl.StateValue.off)
            return true
        case #selector(performTextFinderAction(_:)):
            NSLog("validate TextFinder action \(item.tag)")
            return _textFinder.validateAction(NSTextFinder.Action(rawValue: item.tag)!)
        default:
            return super.validateUserInterfaceItem(item)
        }
    }


}
