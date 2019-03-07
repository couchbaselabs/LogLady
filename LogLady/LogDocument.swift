//
//  Document.swift
//  LogLady
//
//  Created by Jens Alfke on 3/5/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Cocoa

class LogDocument: NSDocument, NSSearchFieldDelegate {

    @IBOutlet internal weak var _tableView : NSTableView!
    @IBOutlet internal weak var _dateFormatter : Formatter!
    @IBOutlet internal weak var _domainFilter : NSPopUpButton!
    @IBOutlet internal weak var _textFinder : NSTextFinder!

    internal var _allEntries = [LogEntry]()
    internal var _entries = [LogEntry]()
    internal var _filter = LogFilter()
    internal var _filterRange = 0..<0


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
        _filterRange = 0 ..< _allEntries.endIndex
    }


    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        // Initialize domains pop-up:
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


    func selectRow(_ row : Int) {
        _tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        _tableView.scrollRowToVisible(row)
    }


    func reloadRowBackground(_ row : Int) {
        if let rowView = _tableView.rowView(atRow: row, makeIfNecessary: false) {
            self.tableView(_tableView, didAdd: rowView, forRow: row)
        }
    }


    func scrollSelectionIntoView() {
        let sel = _tableView.selectedRowIndexes
        if !sel.isEmpty {
            let r = _tableView.rect(ofRow: sel.first!).union(_tableView.rect(ofRow: sel.last!))
            _tableView.scrollToVisible(r)
        }
    }

}


//////// TABLE VIEW:


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
                    var str = String(entry.index + 1)
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
                    color = NSColor.disabledControlTextColor
                case LogLevel.Warning, LogLevel.Error:
                    color = NSColor(red: 0.7, green: 0, blue: 0, alpha: 1)
                default:
                    color = NSColor.controlTextColor
                }
                textField.textColor = color

                // Font:
                if let font = textField.font {
                    let mask = entry.flagged ? NSFontTraitMask.boldFontMask : NSFontTraitMask.unboldFontMask
                    textField.font = NSFontManager.shared.convert(font, toHaveTrait: mask)
                }
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


    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return tableColumn != nil && tableColumn!.identifier.rawValue == "message"
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


extension LogDocument : NSTextFinderClient {

    @IBAction func performTextFinderAction(_ sender: AnyObject?) {
        if let button = sender as? NSValidatedUserInterfaceItem {
            _textFinder.performAction(NSTextFinder.Action(rawValue: button.tag)!)
        }
    }

}
