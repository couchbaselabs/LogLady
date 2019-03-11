//
//  LogDocument+Find.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/7/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Cocoa


// https://blog.timschroeder.net/2012/01/12/nstextfinder-magic/


extension LogDocument : NSTextFinderClient {

    func setupTextFinder() {
        _textFinder.isIncrementalSearchingEnabled = true
        _textFinder.addObserver(self, forKeyPath: "incrementalMatchRanges", options: [],
                                context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if context == nil {
            textFinderMatchRangesChanged(changes: change?[NSKeyValueChangeKey.indexesKey] as? NSIndexSet)
        } else {
            //super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    var isSelectable: Bool            { return true }
    var allowsMultipleSelection: Bool { return true }
    var isEditable: Bool              { return false }


    @IBAction func performTextFinderAction(_ sender: AnyObject?) {
        if let item = sender as? NSValidatedUserInterfaceItem {
            NSLog("----- TextFinder action \(item.tag) for '\(item.action)'")
            _textFinder.performAction(NSTextFinder.Action(rawValue: item.tag)!)
        }
    }


    func string(at characterIndex: Int, effectiveRange outRange: NSRangePointer,
                endsWithSearchBoundary outFlag: UnsafeMutablePointer<ObjCBool>) -> String
    {
        guard let (entry, messageRange, _) = entry(atCharacterIndex: characterIndex) else {
            abort()
        }
        outRange.assign(repeating: NSRange(messageRange), count: 1)
        outFlag.assign(repeating: true, count: 1)
        return String(entry.message)
    }


    func stringLength() -> Int {
        NSLog("stringLength = \(startCharOfMessage(_entries.count))")
        return startCharOfMessage(_entries.count)
    }


    var firstSelectedRange: NSRange {
        let row = _tableView.editedRow
        if row >= 0 {
            var sel = _tableView.currentEditor()!.selectedRange
            sel.location += startCharOfMessage(row)
            return sel
        } else if let row = _tableView.selectedRowIndexes.first {
            return NSRange(charRangeOfMessage(row))
        } else {
            return NSRange(location: 0, length: 0)
        }
    }


    var selectedRanges: [NSValue] {
        get {
            let r = self.firstSelectedRange
            NSLog("selectedRanges -> [\(r)]")
            return (r.length > 0) ? [NSValue(range: r)] : []
        }
        set {
            NSLog("setSelectedRanges: \(newValue)")
            var rows = IndexSet()
            for textRange in newValue {
                if let (_, _, row) = entry(atCharacterIndex: textRange.rangeValue.lowerBound) {
                    rows.insert(row)
                }
            }
            _tableView.selectRowIndexes(rows, byExtendingSelection: false)
        }
    }


    func scrollRangeToVisible(_ range: NSRange) {
        NSLog("Scroll to visible (\(range.location) ... \(range.upperBound))")
        guard let (_, _, row) = entry(atCharacterIndex: range.location) else {
            return
        }
        _tableView.scrollRowToVisible(row)
    }


    var visibleCharacterRanges: [NSValue] {
        let rows = _tableView.rows(in: _tableView.visibleRect)
        if rows.length == 0 {
            NSLog("Visible character range: none")
            return []
        }
        let r = startCharOfMessage(rows.lowerBound) ..< charRangeOfMessage(rows.upperBound).upperBound
        NSLog("Visible character range: \(r)")
        return [NSValue(range: NSRange(r))]
    }


    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer)
        -> NSView
    {
        guard let (_, messageRange, row) = entry(atCharacterIndex: index) else {
            abort()
        }
        NSLog("contentView at \(index) (row \(row))")
        outRange.assign(repeating: NSRange(messageRange), count: 1)
        if let view = _tableView.view(atColumn: 5, row: row, makeIfNecessary: false) {
            return view
        }
        return _tableView // no rects, but have to return some view...
    }


    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let (_, _, row) = entry(atCharacterIndex: range.location) else {
            return nil
        }
        if !_tableView.rect(ofRow: row).intersects(_tableView.visibleRect) {
            return nil
        }
        guard let view = _tableView.view(atColumn: 5, row: row, makeIfNecessary: false) else {
            return nil
        }
        let bounds = view.bounds
        NSLog("Rect for range (\(range.location) ... \(range.upperBound)) = \(bounds)")
        return [NSValue(rect: bounds)]
    }


    // Internal support:

    private func entry(atCharacterIndex: Int) -> (LogEntry, Range<Int>, Int)? {
        var searchRange = 0..<_entries.count
        if let hint = _entryTextPosHint, hint < _entries.count {
            if startCharOfMessage(hint) <= atCharacterIndex {
                searchRange = hint..<_entries.count
            } else {
                searchRange = 0..<hint
            }
        }
        var i = searchRange.lowerBound
        for entry in _entries[searchRange] {
            let messageRange = charRangeOfMessage(i)
            if messageRange.contains(atCharacterIndex) {
                _entryTextPosHint = i + 1
                return (entry, messageRange, i)
            }
            i += 1
        }
        return nil
    }

    private func startCharOfMessage(_ i : Int) -> Int {
        assert(i <= _entries.count)
        if let entryTextPos = _entryTextPos {
            return entryTextPos[i]
        }
        // Constrtuct _entryTextPos array:
        var pos = 0
        _entryTextPos = _entries.map({ (entry) -> Int in
            let startPos = pos
            pos += entry.message.count
            return startPos
        })
        _entryTextPos!.append(pos)
        return _entryTextPos![i]
    }

    private func charRangeOfMessage(_ i : Int) -> Range<Int> {
        return startCharOfMessage(i) ..< startCharOfMessage(i+1)
    }


    private func textFinderMatchRangesChanged(changes: NSIndexSet?) {
        let newRanges = _textFinder.incrementalMatchRanges;
        if (newRanges == _curIncrementalMatchRanges) {
            return
        }

        NSLog("textFinderMatchRangesChanged! \(newRanges.count)")
        var changedRows = IndexSet()

        // Handle array indexes that no longer appear in newRanges:
        for index in changes! {
            if index >= newRanges.count,
                let range = Range<Int>(_curIncrementalMatchRanges[index].rangeValue),
                let (entry, _, row) = entry(atCharacterIndex: range.lowerBound) {
                _entryFindHighlightRanges.removeValue(forKey: entry)

                if _tableView.view(atColumn: 5, row: row, makeIfNecessary: false) != nil {
                    changedRows.insert(row)
                }
            }
        }

        // Handle changes that appear in newRanges:
        for index in changes! {
            if index < newRanges.count,
                let range = Range<Int>(newRanges[index].rangeValue),
                let (entry, entryRange, row) = entry(atCharacterIndex: range.lowerBound) {
                let localRange = range.lowerBound - entryRange.lowerBound ..< range.upperBound - entryRange.lowerBound
                var ranges = _entryFindHighlightRanges[entry] ?? []
                ranges.append(localRange)
                _entryFindHighlightRanges[entry] = ranges

                if _tableView.view(atColumn: 5, row: row, makeIfNecessary: false) != nil {
                    changedRows.insert(row)
                }
            }
        }
        _tableView.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 5))
        _curIncrementalMatchRanges = newRanges
        NSLog("...done -- changed \(changedRows.count) rows")
    }

}
