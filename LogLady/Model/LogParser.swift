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
        entries = try LiteCoreLogParser().parse(url) ?? CocoaLogParser().parse(url) ?? AndroidLogParser().parse(url) ?? AndroidOlderLogParser().parse(url)
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
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter,
                              groups: TextLogParser.Groups(dateStr: 1, subSeconds: 2, domain: 3, level: 4, object: 5, message: 6))
}


func CocoaLogParser() -> LogParser {
    // Logs from iOS/Mac apps.
    //     2019-01-22 00:47:33.200154+0530 My App[2694:52664] CouchbaseLite BLIP Verbose: {BLIPIO#2} Finished
    let regex = "^([\\d-]+ [\\d:]+)(\\.\\d+).*\\[\\d+:\\d+] (?:CouchbaseLite (\\w+) (\\w+): (?:\\{(.+?)\\} )?)?(.*)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter,
                              groups: TextLogParser.Groups(dateStr: 1, subSeconds: 2, domain: 3, level: 4, object: 5, message: 6))
}


func AndroidOlderLogParser() -> LogParser {
    // Logs from Android apps (logcat), pre CBL-2.5
    //    03-12 18:49:18.980 11558-11575/com.couchbase.todo I/LiteCore [Sync]: {Repl#1} activityLevel=busy: connectionState=2
    let regex = "^([\\d-]+ [\\d:]+)(\\.\\d+)\\s\\d+-\\d+/\\S+\\s(\\w)\\/(?:LiteCore\\s\\[)?(\\w+)\\]?:\\s(?:\\{(.+?)\\}\\s)?(.+)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MM-dd HH:mm:ss"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter,
                              groups: TextLogParser.Groups(dateStr: 1, subSeconds: 2, domain: 4, level: 3, object: 5, message: 6))
}


func AndroidLogParser() -> LogParser {
    // Logs from Android apps (logcat), CBL-2.5+
    //    2019-03-12 13:22:37.660 7042-7058/com.couchbase.lite.test D/CouchbaseLite/DATABASE: {N8litecore8DataFile6SharedE#5} adding DataFile 0xd457d980
    let regex = "^([\\d-]+ [\\d:]+)(\\.\\d+)\\s\\d+-\\d+/\\S+\\s(\\w)\\/(?:CouchbaseLite/)?(\\w+):\\s(?:\\{(.+?)\\}\\s)?(.+)$"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    return try! TextLogParser(regexStr: regex, dateFormat: dateFormatter,
                              groups: TextLogParser.Groups(dateStr: 1, subSeconds: 2, domain: 4, level: 3, object: 5, message: 6))
}


class TextLogParser : LogParser {

    // This gives the group # in the regex of each feature
    struct Groups {
        let dateStr : Int
        let subSeconds : Int
        let domain : Int
        let level : Int
        let object : Int
        let message : Int
    }


    init(regexStr: String, dateFormat: DateFormatter, groups: Groups) throws {
        self.lineRegex = try NSRegularExpression(pattern: regexStr)
        self.dateFormatter = dateFormat
        self.groups = groups
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
    private let groups: Groups

    private var index = 0

    private func parseLine(_ subLine: Substring) -> LogEntry {
        let line = String(subLine)
        guard let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0,length: line.count))
        else {
            return LogEntry(index: index, line: subLine)
        }

        guard let dateStr = matched(m, groups.dateStr, in: line),
            let date = dateFormatter.date(from: String(dateStr)) else {
                return LogEntry(index: index, line: subLine)
        }
        var timestamp = date.timeIntervalSince1970

        if let subSecondsStr = matched(m, groups.subSeconds, in: line),
            let subSeconds = Double(subSecondsStr) {
            timestamp += subSeconds
        }

        var domain: LogDomain? = nil
        if let domainStr = matched(m, groups.domain, in: line) {
            domain = LogDomain.named(String(domainStr))
        }

        var level = LogLevel.Info
        if let levelName = matched(m, groups.level, in: line),
            let lv = TextLogParser.kLevelsByName[levelName.lowercased()] {
            level = lv
        }

        let object = matched(m, groups.object, in: line)
        let message = matched(m, groups.message, in: line)!

        return LogEntry(index: index, line: subLine, timestamp: timestamp, level: level,
                        domain: domain, object: object, message: message)
    }

    private func matched(_ match: NSTextCheckingResult, _ group: Int, in str: String) -> Substring? {
        guard let r = Range(match.range(at: group), in: str) else {
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
        "d":        LogLevel.Debug,
        "v":        LogLevel.Verbose,
        "i":        LogLevel.Info,
        "w":        LogLevel.Warning,
        "e":        LogLevel.Error,
    ]
}
