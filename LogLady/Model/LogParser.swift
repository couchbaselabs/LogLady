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
        entries = try CocoaLogParser().parse(url) ?? LiteCoreLogParser().parse(url)
    }
    guard let gotEntries = entries else {
        throw NSError(domain: "LogLady", code: -1,
                      userInfo: [NSLocalizedFailureReasonErrorKey: "The file does not appear to be a recognized Couchbase Lite log type."])
    }
    return gotEntries
}


protocol LogParser {
    func parse(_: URL) throws -> [LogEntry]?
}


func LiteCoreLogParser() -> LogParser {
    // Logs from LiteCore itself, or its LogDecoder:
    //     18:21:02.502713| [Sync] WARNING: {repl#1234} Woe is me
    let regex = "^(\\d\\d:\\d\\d:\\d\\d)(\\.\\d+)\\|\\s*(?:(?:\\[(\\w+)\\])(?:\\s(\\w+))?:\\s*(?:\\{(.+?)\\})?\\s*)?(.*)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.defaultDate = Date(timeIntervalSince1970: round(Date().timeIntervalSince1970))
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter)
}


func CocoaLogParser() -> LogParser {
    // Logs from iOS/Mac apps.
    //     2019-01-22 00:47:33.200154+0530 My App[2694:52664] CouchbaseLite BLIP Verbose: {BLIPIO#2} Finished
    let regex = "^([\\d-]+ [\\d:]+)(\\.\\d+).*\\[\\d+:\\d+] (?:CouchbaseLite (\\w+) (\\w+): (?:\\{(.+?)\\} )?)?(.*)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter)
}


class TextLogParser : LogParser {

    init(regexStr: String, dateFormat: DateFormatter) throws {
        self.lineRegex = try NSRegularExpression(pattern: regexStr)
        self.dateFormatter = dateFormat
    }

    func parse(_ url: URL) throws -> [LogEntry]? {
        return parse(data: try String(contentsOf: url, encoding: .utf8))
    }

    func parse(data: String) -> [LogEntry]? {
        self.index = 0
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

            let entry = self.parseLine(line)
            messages.append(entry)
            self.index += 1

            if entry.timestamp > 0 {
                matched = true
            } else if !matched && self.index > 100 {
                break
            }
        }
        if !matched {
            return nil
        }
        return messages
    }

    private let dateFormatter: DateFormatter
    private let lineRegex: NSRegularExpression

    private var index = 0

    private func parseLine(_ subLine: Substring) -> LogEntry {
        let line = String(subLine)
        guard let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0,length: line.count))
        else {
            return LogEntry(index: index, line: subLine)
        }

        guard let dateStr = matched(m, .DateStr, in: line),
            let date = dateFormatter.date(from: String(dateStr)) else {
                return LogEntry(index: index, line: subLine)
        }
        var timestamp = date.timeIntervalSince1970

        if let subSecondsStr = matched(m, .SubSeconds, in: line),
            let subSeconds = Double(subSecondsStr) {
            timestamp += subSeconds
        }

        var domain: LogDomain? = nil
        if let domainStr = matched(m, .Domain, in: line) {
            domain = LogDomain.named(String(domainStr))
        }

        var level = LogLevel.Info
        if let levelName = matched(m, .Level, in: line),
            let lv = TextLogParser.kLevelsByName[levelName.lowercased()] {
            level = lv
        }

        let object = matched(m, .Object, in: line)
        let message = matched(m, .Message, in: line)!

        return LogEntry(index: index, line: subLine, timestamp: timestamp, level: level,
                        domain: domain, object: object, message: message)
    }

    enum Matched : Int {
        case DateStr = 1
        case SubSeconds
        case Domain
        case Level
        case Object
        case Message
    }

    private func matched(_ match: NSTextCheckingResult, _ group: Matched, in str: String) -> Substring? {
        guard let r = Range(match.range(at: group.rawValue), in: str) else {
            return nil
        }
        return str[r]
    }

    private static let kLevelsByName : [String:LogLevel] = [
        "debug":    LogLevel.Debug,
        "verbose":  LogLevel.Verbose,
        "info":     LogLevel.Info,
        "warning":  LogLevel.Warning,
        "error":    LogLevel.Error,
    ]
}
