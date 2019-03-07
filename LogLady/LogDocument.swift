//
//  Document.swift
//  LogLady
//
//  Created by Jens Alfke on 3/5/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Cocoa

class LogDocument: NSDocument, NSSearchFieldDelegate {

    @IBOutlet private weak var _tableView : NSTableView!
    @IBOutlet private weak var _dateFormatter : Formatter!
    @IBOutlet private weak var _domainFilter : NSPopUpButton!

    private var _allEntries = [LogEntry]()
    private var _entries = [LogEntry]()
    private var _filter = LogFilter()

    override init() {
        super.init()

        LogDocument.kLevelImages[Int(LogLevel.Debug.rawValue)] = NSImage(named: "stethoscope.pdf")
//        LogDocument.kLevelImages[Int(LogLevel.Verbose.rawValue)] = NSImage(named: "comment.pdf")
//        LogDocument.kLevelImages[Int(LogLevel.Info.rawValue)] = NSImage(named: "info.pdf")
        LogDocument.kLevelImages[Int(LogLevel.Warning.rawValue)] = NSImage(named: "exclamation-triangle.pdf")
        LogDocument.kLevelImages[Int(LogLevel.Error.rawValue)] = NSImage(named: "skull.pdf")
    }

    override class var autosavesInPlace: Bool {
        return true
    }

    override var windowNibName: NSNib.Name? {
        return NSNib.Name("Document")
    }

    override func read(from url: URL, ofType typeName: String) throws {
        let data = try String(contentsOf: url, encoding: .utf8)

        do {
            _allEntries = try CocoaLogParser().parse(data)
        } catch {
            _allEntries = try LiteCoreLogParser().parse(data)
        }
        _entries = _allEntries
    }

    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        var domains = Set<LogDomain>()
        for e in _allEntries {
            if let domain = e.domain {
                domains.insert(domain)
            }
        }
        for name in (domains.map{$0.name}.sorted()) {
            _domainFilter.addItem(withTitle: name)
        }
    }


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
        }
        _tableView.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet([0]))
    }


    func selectRow(_ row : Int) {
        _tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        _tableView.scrollRowToVisible(row)
    }


    func scrollSelectionIntoView() {
        let sel = _tableView.selectedRowIndexes
        if !sel.isEmpty {
            let r = _tableView.rect(ofRow: sel.first!).union(_tableView.rect(ofRow: sel.last!))
            _tableView.scrollToVisible(r)
        }
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
        let filteredEntries = _allEntries.filter{ $0.matches(_filter) }
        if filteredEntries == _entries {
            if alwaysReload {
                _tableView.reloadData()
            }
            return
        }

        let oldSel = IndexSet( _tableView.selectedRowIndexes.map { _entries[$0].index } )
        _tableView.deselectAll(nil)
        
        _entries = filteredEntries
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


    @IBAction func filter(_ sender: AnyObject) {
        _filter.string = (sender as! NSSearchField).stringValue
        if let f = _filter.string, f.isEmpty {
            _filter.string = nil
        }
        updateFilter(alwaysReload: true)
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


    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(flag(_:)):
            return _tableView.selectedRow >= 0
        case #selector(toggleHideUnmarked(_:)):
            (item as? NSMenuItem)?.state = (_filter.onlyMarked ? NSControl.StateValue.on : NSControl.StateValue.off)
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

}


extension LogDocument: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return _entries.count
    }
}


extension LogDocument: NSTableViewDelegate {
    private static let kLevelNames = ["", "debug", "verbose", "", "Warning", "Error"]
    private static var kLevelImages: [NSImage?] = [nil, nil, nil, nil, nil, nil]

    private static var kTextMatchAttributes = [NSAttributedString.Key:Any]()

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let colID = tableColumn!.identifier
        let view = tableView.makeView(withIdentifier: colID, owner: self)
        if let view = view as? NSTableCellView {
            let entry = _entries[row]
            if let textField = view.textField {
                // Text:
                switch colID.rawValue {
                case "index":
                    var str = String(entry.index)
                    if entry.flagged {
                        str = "🚩 " + str
                    }
                    textField.stringValue = str
                case "time":
                    if textField.formatter == nil {
                        textField.formatter = _dateFormatter
                    }
                    textField.objectValue = entry.date
                case "message":
                    setHighlightedString(entry.message, in: textField)
                case "object":
                    setHighlightedString(entry.object, in: textField)
                case "domain":
                    textField.objectValue = entry.domain?.name
                default:
                    textField.objectValue = nil
                }

                // Text color:
                let color: NSColor?
                switch entry.level {
                case LogLevel.None, LogLevel.Verbose, LogLevel.Debug:
                    color = NSColor(white: 0.5, alpha: 1)
                case LogLevel.Warning, LogLevel.Error:
                    color = NSColor(red: 0.7, green: 0, blue: 0, alpha: 1)
                default:
                    color = NSColor.controlTextColor
                }
                textField.textColor = color
            }
            if let imageView = view.imageView {
                switch colID.rawValue {
                case "level":
                    // Level icon:
                    imageView.image = LogDocument.kLevelImages[Int(entry.level.rawValue)]
                default:
                    break
                }
            }
        }
        return view
    }


    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        let entry = _entries[row]
        rowView.backgroundColor = entry.flagged ? NSColor.yellow : NSColor.clear
    }


    private func setHighlightedString(_ string: Substring?, in textField: NSTextField) {
        textField.objectValue = string
        if let match = _filter.string, string != nil {
            let astr = textField.attributedStringValue.mutableCopy() as! NSMutableAttributedString
            highlight(substring: match, in: astr)
            textField.attributedStringValue = astr
        }
    }


    private func highlight(substring: String, in astr: NSMutableAttributedString) {
        let str = astr.string
        if LogDocument.kTextMatchAttributes.isEmpty {
            LogDocument.kTextMatchAttributes[NSAttributedString.Key.backgroundColor] = NSColor.yellow
        }
        var start = str.startIndex
        while let rMatch = str.range(of: substring, options: String.CompareOptions.caseInsensitive,
                                     range: (start ..< str.endIndex), locale: nil) {
            astr.setAttributes(LogDocument.kTextMatchAttributes, range: NSRange(rMatch, in: str))
            start = rMatch.upperBound
        }
    }
}
