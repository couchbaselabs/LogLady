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
    @IBOutlet internal weak var _domainFilter : NSPopUpButton!
    @IBOutlet internal weak var _levelFilter : NSPopUpButton!
    @IBOutlet internal weak var _textFinder : NSTextFinder!

    internal var _allEntries = [LogEntry]()
    internal var _entries = [LogEntry]()
    internal var _filter = LogFilter()
    internal var _filterRange = 0..<0
    internal var _flagMarker : String?

    // Starting index of each entry's .message string, in concatenation of all the messages
    internal var _entryTextPos : [Int]? = nil
    internal var _entryTextPosHint : Int? = nil
    // Character range to highlight in each Entry
    internal var _entryFindHighlightRanges = [LogEntry:[Range<Int>]]()
    internal var _curIncrementalMatchRanges = [NSValue]()

    override init() {
        super.init()
    }


    override class var autosavesInPlace: Bool {
        return true
    }


    override func read(from url: URL, ofType typeName: String) throws {
        _allEntries = try ParseLogFile(url)
        _entries = _allEntries
        _filterRange = 0 ..< _allEntries.endIndex
        _entryTextPos = nil
        _entryTextPosHint = nil
    }


    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "LogLady", code: -1,
                          userInfo: [NSLocalizedFailureReasonErrorKey: "Data is not UTF-8 text"])
        }
        _allEntries = try ParseLogText(text)
        _entries = _allEntries
        _filterRange = 0 ..< _allEntries.endIndex
        _entryTextPos = nil
        _entryTextPosHint = nil
    }


    func addFiles(_ urls: [URL]) throws {
        var merged = _allEntries
        for url in urls {
            merged.append(contentsOf: try ParseLogFile(url))
        }
        merged.sort(by: { $0.timestamp < $1.timestamp })
        var i = 0
        for e in merged {
            e.index = i
            i += 1
        }
        _allEntries = merged
        _entries = merged
    }


    override var windowNibName: NSNib.Name? {
        return NSNib.Name("Document")
    }


    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        // Initialize domains pop-up:
        var levelCounts = [0, 0, 0, 0, 0, 0]
        var domains = Set<LogDomain>()
        for e in _allEntries {
            if let domain = e.domain {
                domains.insert(domain)
            }
            levelCounts[Int(e.level.rawValue)] += 1
        }

        for name in (domains.map{$0.name}.sorted()) {
            _domainFilter.addItem(withTitle: name)
        }

        _levelFilter.autoenablesItems = false
        for item in _levelFilter.itemArray {
            if item.tag > 0 {
                var count = levelCounts[item.tag]
                if count == 0 {
                    item.isEnabled = false
                } else if item.tag >= LogLevel.Warning.rawValue {
                    if item.tag == LogLevel.Warning.rawValue {
                        count += levelCounts[Int(LogLevel.Error.rawValue)]
                    }
                    item.title +=  " (\(count))"
                }
            }
        }

        setupTextFinder()
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


struct Col {
    static let Index   = NSUserInterfaceItemIdentifier("index")
    static let Time    = NSUserInterfaceItemIdentifier("time")
    static let Level   = NSUserInterfaceItemIdentifier("level")
    static let Domain  = NSUserInterfaceItemIdentifier("domain")
    static let Object  = NSUserInterfaceItemIdentifier("object")
    static let Message = NSUserInterfaceItemIdentifier("message")
}


extension LogDocument: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return _entries.count
    }
}


extension LogDocument: NSTableViewDelegate {
    typealias TextAttributes = [NSAttributedString.Key:Any]

    private static var kDateFont: NSFont {
        // Set font attributes to use lining figures (monospaced digits) for time column:
        // Credit to: <https://www.raizlabs.com/dev/2015/08/advanced-ios-typography/>
        let baseFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .light)
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName.featureSettings: [
                [NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                 NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]
            ],
            ])
        return NSFont(descriptor: descriptor, size: baseFont.pointSize)!
    }

    private static var kFlagFont: NSFont {
        return NSFontManager.shared.convert(kDateFont, toSize: kDateFont.pointSize + 2)
    }

    private static var kDateFormatter : DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "hh:mm:ss"
        return formatter
    }

    private static let kLevelNames = ["", "debug", "verbose", "", "Warning", "Error"]

    private static var kLevelImages: [NSImage?] {
        var images: [NSImage?] = [nil, nil, nil, nil, nil, nil]
        images[Int(LogLevel.Debug.rawValue)] = NSImage(named: "stethoscope.pdf")
//        images[Int(LogLevel.Verbose.rawValue)] = NSImage(named: "comment.pdf")
//        images[Int(LogLevel.Info.rawValue)] = NSImage(named: "info.pdf")
        images[Int(LogLevel.Warning.rawValue)] = NSImage(named: "exclamation-triangle.pdf")
        images[Int(LogLevel.Error.rawValue)] = NSImage(named: "skull.pdf")
        return images
    }

    private static let kTextMatchAttributes: TextAttributes = [
        .backgroundColor : NSColor.yellow]
    private static let kTextFinderAttributes: TextAttributes = [
        .backgroundColor : NSColor.orange]
    private static let kFlagAttributes: TextAttributes = [
        .font : kFlagFont,
        .baselineOffset : -3]

    private static let kWarningErrorColor = NSColor(calibratedRed: 0.7, green: 0, blue: 0, alpha: 1)
    private static let kFlaggedRowBGColor = NSColor(calibratedHue: 0.33, saturation: 0.2, brightness: 1.0, alpha: 1.0)

    // Set up table cell views:
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let colID = tableColumn!.identifier
        let view = tableView.makeView(withIdentifier: colID, owner: self)
        if let view = view as? NSTableCellView {
            let entry = _entries[row]
            if let textField = view.textField {
                // Text color:
                let color: NSColor?
                switch entry.level {
                case .None, .Verbose, .Debug:
                    color = NSColor.disabledControlTextColor
                case .Warning, .Error:
                    color = NSColor(red: 0.7, green: 0, blue: 0, alpha: 1)
                default:
                    color = NSColor.controlTextColor
                }
                textField.textColor = color

                // Font:
                if colID == Col.Index || colID == Col.Time {
                    textField.font = LogDocument.kDateFont
                } else if let font = textField.font {
                    let mask: NSFontTraitMask = entry.flagged ? .boldFontMask : .unboldFontMask
                    textField.font = NSFontManager.shared.convert(font, toHaveTrait: mask)
                }

                // Text:
                switch colID {
                case Col.Index:
                    textField.stringValue = String(entry.index + 1)
                    if entry.flagged {
                        let marker = (entry.flagMarker ?? "🚩 ")
                        let astr = textField.attributedStringValue.mutableCopy() as! NSMutableAttributedString
                        astr.addAttributes([.foregroundColor : NSColor.controlTextColor],
                                           range: NSRange(0..<astr.string.count))
                        astr.replaceCharacters(in: NSRange(0..<0), with: marker)
                        astr.addAttributes(LogDocument.kFlagAttributes, range: NSRange(0..<marker.count))
                        textField.attributedStringValue = astr
                    }
                case Col.Time:
                    if let date = entry.date {
                        let usec = Int64(entry.timestamp * 1e6) % 1000000
                        textField.stringValue = LogDocument.kDateFormatter.string(from: date).appendingFormat(".%06d", usec)
                    } else {
                        textField.stringValue = ""
                    }
                case Col.Domain:
                    textField.objectValue = entry.domain?.name
                case Col.Object:
                    setHighlightedString(entry.object, in: textField)
                case Col.Message:
                    setHighlightedString(entry.message,
                                         foundRanges: _entryFindHighlightRanges[entry],
                                         in: textField)
                default:
                    textField.objectValue = nil
                }
            }
            if let imageView = view.imageView {
                switch colID {
                case Col.Level:
                    // Level icon:
                    imageView.image = LogDocument.kLevelImages[Int(entry.level.rawValue)]
                default:
                    break
                }
            }
        }
        return view
    }


    // Customize row background:
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        let entry = _entries[row]
        let color: NSColor
        if entry.flagged {
            color = LogDocument.kFlaggedRowBGColor
        } else {
            color = NSColor.controlAlternatingRowBackgroundColors[row % 2]
        }
        rowView.backgroundColor = color
    }


    // Make the message column selectable:
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return tableColumn != nil && tableColumn!.identifier == Col.Message
    }



    private func setHighlightedString(_ string: Substring?,
                                      foundRanges: [Range<Int>]? = nil,
                                      in textField: NSTextField)
    {
        textField.objectValue = string
        if _filter.string != nil || foundRanges != nil {
            let astr = textField.attributedStringValue.mutableCopy() as! NSMutableAttributedString
            if let match = _filter.string {
                highlight(substring: match, in: astr)
            }
            if let foundRanges = foundRanges {
                for range in foundRanges {
                    astr.addAttributes(LogDocument.kTextFinderAttributes,
                                       range: NSRange(range))
                }
            }
            textField.attributedStringValue = astr
        }
    }


    private func highlight(substring: String, in astr: NSMutableAttributedString) {
        let str = astr.string
        var start = str.startIndex
        while let rMatch = str.range(of: substring, options: .caseInsensitive,
                                     range: (start ..< str.endIndex), locale: nil) {
            astr.addAttributes(LogDocument.kTextMatchAttributes, range: NSRange(rMatch, in: str))
            start = rMatch.upperBound
        }
    }
}
