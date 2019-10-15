//
//  LogParser.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/5/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Foundation


// Top level log parsing function.
func ParseLogFile(_ url: URL) throws -> [LogEntry] {
    let entries : [LogEntry]?
    if url.hasDirectoryPath {
        entries = try LiteCoreBinaryLogParser().parseDirectory(dir: url)
    } else if url.pathExtension == "cbllog" {
        entries = try LiteCoreBinaryLogParser().parse(url)
    } else {
        entries = try LiteCoreLogParser().parse(url) ?? CocoaLogParser().parse(url) ?? AndroidLogParser().parse(url) ?? AndroidOlderLogParser().parse(url) ?? SyncGatewayLogParser().parse(url)
    }
    guard let gotEntries = entries else {
        throw NSError(domain: "LogLady", code: -1,
                      userInfo: [NSLocalizedFailureReasonErrorKey: "The file does not appear to be a recognized Couchbase Lite or Sync Gateway log type."])
    }
    return gotEntries
}


func ParseLogText(_ text: String) throws -> [LogEntry] {
    let entries = try LiteCoreLogParser().parse(text) ?? CocoaLogParser().parse(text) ?? AndroidLogParser().parse(text) ?? AndroidOlderLogParser().parse(text) ?? SyncGatewayLogParser().parse(text)
    guard let gotEntries = entries else {
        throw NSError(domain: "LogLady", code: -1,
                      userInfo: [NSLocalizedFailureReasonErrorKey: "The text does not appear to be Couchbase Lite or Sync Gateway logs."])
    }
    return gotEntries
}


protocol LogParser {
    func parse(_: URL) throws -> [LogEntry]?
}

protocol TextLogParser : LogParser {
    func parse(_: String) throws -> [LogEntry]?
}


func LiteCoreLogParser() -> TextLogParser {
    print("Trying LiteCore...")
    // Logs from LiteCore itself, or its LogDecoder:
    //     | [Sync] WARNING: {repl#1234} Woe is me
    let regex = "\\|\\s(?:(?:\\[(\\w+)\\])(?:\\s(\\w+))?:\\s*(?:\\{(.+?)\\})?\\s*)?(.*)$"
    return TextLogParserImpl(regexStr: regex,
                              groups: TextLogParserImpl.Groups(domain: 1, level: 2, object: 3, message: 4))
}


func CocoaLogParser() -> TextLogParser {
    print("Trying Cocoa...")
    // Logs from iOS/Mac apps.
    //     My App[2694:52664] CouchbaseLite BLIP Verbose: {BLIPIO#2} Finished
    let regex = ".*\\[\\d+:\\d+] (?:CouchbaseLite (\\w+) (\\w+): (?:\\{(.+?)\\} )?)?(.*)$"
    return TextLogParserImpl(regexStr: regex,
                              groups: TextLogParserImpl.Groups(domain: 1, level: 2, object: 3, message: 4))
}


func AndroidOlderLogParser() -> TextLogParser {
    print("Trying Android(old)...")
    // Logs from Android apps (logcat), pre CBL-2.5
    //    11558-11575/com.couchbase.todo I/LiteCore [Sync]: {Repl#1} activityLevel=busy: connectionState=2
    let regex = "\\s\\d+-\\d+/\\S+\\s(\\w)\\/(?:LiteCore\\s\\[)?(\\w+)\\]?:\\s(?:\\{(.+?)\\}\\s)?(.+)$"
    return TextLogParserImpl(regexStr: regex,
                              groups: TextLogParserImpl.Groups(domain: 2, level: 1, object: 3, message: 4))
}


func AndroidLogParser() -> TextLogParser {
    print("Trying Android(new)...")
    // Logs from Android apps (logcat), CBL-2.5+
    //    7042-7058/com.couchbase.lite.test D/CouchbaseLite/DATABASE: {N8litecore8DataFile6SharedE#5} adding DataFile 0xd457d980
    let regex = "\\s(?:\\d+-\\d+/\\S+\\s)?(\\w)\\/(?:CouchbaseLite/)?(\\w+):\\s(?:\\{(.+?)\\}\\s)?(.+)$"
    return TextLogParserImpl(regexStr: regex,
                              groups: TextLogParserImpl.Groups(domain: 2, level: 1, object: 3, message: 4))
}


func SyncGatewayLogParser() -> TextLogParser {
    print("Trying SG...")
    // Logs from Sync Gateway
    //    [INF] HTTP: Reset guest user to config
    let regex = "\\s\\[(\\w{3})\\] (?:([\\w+]+): +)?(?:(#\\d+:|c:\\[[0-9a-f]+\\]) )?(.*)$"
    return TextLogParserImpl(regexStr: regex,
                             groups: TextLogParserImpl.Groups(domain: 2, level: 1, object: 3, message: 4))
}


let kTimestampFormats : [TimestampParser] = [
    TimestampParser(       "(\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})(\\.\\d+)",             "MM-dd HH:mm:ss\\s"),   // Android (logcat), pre CBL 2.5: "03-12 18:49:18.980"
    TimestampParser(                     "(\\d{2}:\\d{2}:\\d{2})(\\.\\d+)",             "HH:mm:ss"),            // LiteCore: "18:21:02.502713"
    TimestampParser("(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})(\\.\\d+)[-+][\\d:]+",  "yyyy-MM-dd HH:mm:ss"), // Cocoa: "2019-01-22 00:47:33.200154+0530"
    TimestampParser("(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})(\\.\\d+)",             "yyyy-MM-dd HH:mm:ss"), // Android (logcat): "2019-03-12 13:22:37.660"
    TimestampParser("(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(\\.\\d+)[-+][\\d:]+",  "yyyy-MM-dd'T'HH:mm:ss")// SG: "2019-10-14T14:01:07.006-07:00"
]


class TextLogParserImpl : TextLogParser {

    private var _lineRegex: NSRegularExpression
    private var _groups: Groups
    private var _timestampParser: TimestampParser?

    private var _index = 0


    // This gives the group # in the regex of each feature
    struct Groups {
        var domain : Int
        var level : Int
        var object : Int
        var message : Int
    }


    init(regexStr: String, groups: Groups) {
        self._lineRegex = try! NSRegularExpression(pattern: regexStr)
        self._groups = groups
    }

    func parse(_ url: URL) throws -> [LogEntry]? {
        return parse(try String(contentsOf: url, encoding: .utf8))
    }

    func parse(_ data: String) -> [LogEntry]? {
        // First determine the timestamp format, if any:
        if let parser = (kTimestampFormats.first {$0.parse(data) != nil}) {
            _timestampParser = parser
            let pattern = parser.regex.pattern + _lineRegex.pattern
            _lineRegex = try! NSRegularExpression(pattern: pattern)
            _groups.domain += 2
            _groups.level += 2
            _groups.object += 2
            _groups.message += 2
            print("    using date format \(parser.regex.pattern)")
        }

        self._index = 0
        var messages = [LogEntry]()
        var matched = false

        var startIndex = data.startIndex
        while startIndex < data.endIndex {
            var xStart = startIndex
            var lineEndIndex = startIndex
            var endIndex = startIndex
            data.getLineStart(&xStart, end: &lineEndIndex, contentsEnd: &endIndex, for: (startIndex...startIndex))
            let entry = self.parseLine(text: data, range: startIndex..<endIndex)
            messages.append(entry)

            startIndex = lineEndIndex
            self._index += 1

            if !matched {
                if entry.level != .None {
                    matched = true
                } else if self._index > 100 {
                    break
                }
            }
        }
        if !matched {
            return nil
        }
        return messages
    }

    private func parseLine(text: String, range: Range<String.Index>) -> LogEntry {
        let line: Substring = text[range]
        guard let m = _lineRegex.firstMatch(in: text, range: NSRange(range, in: text))
            else {
                if let (ts, rest) = _timestampParser?.parse(String(line)) {
                    return LogEntry(index: _index, line: line, timestamp: ts, level: .None, domain: nil, object: nil, message: rest)
                } else {
                    return LogEntry(index: _index, line: line)
                }
        }

        var timestamp: TimeInterval
        if let timestampParser = _timestampParser {
            guard let ts = timestampParser.timestamp(fromMatch: m, in: text)
                else { return LogEntry(index: _index, line: line) }
            timestamp = ts
        } else {
            timestamp = TimeInterval(_index + 1)
        }

        var domain: LogDomain? = nil
        if let domainStr = matched(m, _groups.domain, in: text) {
            domain = LogDomain.named(String(domainStr))
        }

        var level = LogLevel.Info
        if let levelName = matched(m, _groups.level, in: text),
            let lv = TextLogParserImpl.kLevelsByName[levelName.lowercased()] {
            level = lv
        }

        let object = matched(m, _groups.object, in: text)
        let message = matched(m, _groups.message, in: text)!

        return LogEntry(index: _index, line: line, timestamp: timestamp, level: level,
                        domain: domain, object: object, message: message)
    }

    private func matched(_ match: NSTextCheckingResult, _ group: Int, in str: String) -> Substring? {
        guard group > 0, let r = Range(match.range(at: group), in: str) else {
            return nil
        }
        return str[r]
    }

    private static let kLevelsByName : [String:LogLevel] = [
        "debug":    .Debug,
        "verbose":  .Verbose,
        "info":     .Info,
        "warning":  .Warning,
        "error":    .Error,

        "d":        .Debug,         // Android logs use a single letter
        "v":        .Verbose,
        "i":        .Info,
        "w":        .Warning,
        "e":        .Error,

        "dbg":      .Debug,         // SG logs use 3 letters
        "trc":      .Verbose,
        "inf":      .Info,
        "wrn":      .Warning,
        "err":      .Error,
    ]
}
