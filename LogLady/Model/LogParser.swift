//
//  LogParser.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/5/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Foundation


protocol LogParser {
    func parse (_ data: String) throws -> [LogEntry]
}


func LiteCoreLogParser() -> TextLogParser {
    // Sample line:      18:21:02.502713| [Sync] WARNING: {repl#1234} Woe is me
    let regex = "^(\\d\\d:\\d\\d:\\d\\d.\\d+)\\|\\s*(?:(?:\\[(\\w+)\\])(?:\\s(\\w+))?:\\s*(?:\\{(.+)\\})?\\s*)?(.*)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss.SSSSSS"
    dateFormatter.defaultDate = Date()
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter)
}


func CocoaLogParser() -> TextLogParser {
    let regex = "^([\\d-]+ [\\d:.+]+) .*\\[\\d+:\\d+] (?:CouchbaseLite (\\w+) (\\w+): (?:\\{(.*)\\} )?)?(.*)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZ"
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter)
}


class TextLogParser : LogParser {

    init(regexStr: String, dateFormat: DateFormatter) throws {
        self.lineRegex = try NSRegularExpression(pattern: regexStr)
        self.dateFormatter = dateFormat
    }

    func parse (_ data: String) throws -> [LogEntry] {
        index = 0
        var messages = [LogEntry]()
        var matched = false

        var startIndex = data.startIndex
        while startIndex < data.endIndex {
            var xStart = startIndex
            var lineEndIndex = startIndex
            var endIndex = startIndex
            data.getLineStart(&xStart, end: &lineEndIndex, contentsEnd: &endIndex, for: (startIndex...startIndex))
            let line = data[startIndex..<endIndex]
            startIndex = lineEndIndex

            self.index += 1
            let entry = self.parseLine(line)
            messages.append(entry)

            if entry.timestamp > 0 {
                matched = true
            } else if !matched && self.index > 100 {
                throw NSError(domain: "LogLady", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Wrong file format"])
            }
        }
        return messages
    }

    private var index = 0

    private var dateFormatter: DateFormatter

    private var lineRegex: NSRegularExpression

    private func matched(_ match: NSTextCheckingResult, _ group: Int, in str: String) -> Substring? {
        guard let r = Range(match.range(at: group), in: str) else {
            return nil
        }
        return str[r]
    }

    private func parseLine(_ subLine: Substring) -> LogEntry {
        let line = String(subLine)
        guard let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0,length: line.count))
        else {
            return LogEntry(index: index, line: subLine)
        }

        guard let dateStr = matched(m, 1, in: line),
            let date = dateFormatter.date(from: String(dateStr)) else {
                return LogEntry(index: index, line: subLine)
        }

        var domain: LogDomain? = nil
        if let domainStr = matched(m, 2, in: line) {
            domain = LogDomain.named(String(domainStr))
        }

        var level = LogLevel.Info
        if let levelName = matched(m, 3, in: line),
            let lv = TextLogParser.kLevelsByName[levelName.lowercased()] {
            level = lv
        }

        let object = matched(m, 4, in: line)
        let message = matched(m, 5, in: line)!

        return LogEntry(index: index, line: subLine, date: date, level: level,
                        domain: domain, object: object, message: message)
    }

    private static let kLevelsByName : [String:LogLevel] = [
        "debug":LogLevel.Debug,
        "verbose":LogLevel.Verbose,
        "info":LogLevel.Info,
        "warning":LogLevel.Warning,
        "error":LogLevel.Error,
    ]
}
