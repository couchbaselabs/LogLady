//
//  LogEntry.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/5/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Foundation


enum LogLevel : Int8 {
    case None
    case Debug
    case Verbose
    case Info
    case Warning
    case Error
}


class LogDomain {
    let name: String

    class func named(_ name :String) -> LogDomain {
        if let domain = _domains[name] {
            return domain
        }
        let domain = LogDomain(name)
        _domains[name] = domain
        return domain
    }

    private init(_ name: String) {
        self.name = name
    }

    private static var _domains = [String:LogDomain]()
}

extension LogDomain : Hashable {
    static func == (lhs: LogDomain, rhs: LogDomain) -> Bool {
        return lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}


struct LogFilter {
    var onlyMarked = false
    var minLevel: LogLevel = LogLevel.None
    var domains: Set<LogDomain?>? = nil
    var string: String? = nil
}


class LogEntry {
    init(index: Int, line: Substring, date: Date?, level: LogLevel, domain: LogDomain?, object: Substring?, message: Substring) {
        self.sourceLine = line
        self.index = index
        if let date = date {
            self.timestamp = date.timeIntervalSince1970
        } else {
            self.timestamp = 0
        }
        self.level = level
        self.domain = domain
        self.object = object
        self.message = message
    }

    convenience init(index: Int, line: Substring) {
        self.init(index: index, line: line, date: nil, level: LogLevel.None, domain: nil, object: nil, message: line)
    }

    var date: Date? {
        if timestamp == 0 {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    let index:      Int
    let timestamp:  Double
    let level:      LogLevel
    let domain:     LogDomain?
    let object:     Substring?
    let message:    Substring
    let sourceLine: Substring

    var flagged =   false

    func matches(_ filter: String) -> Bool {
        return message.localizedStandardContains(filter) || (object?.localizedStandardContains(filter) ?? false)
    }

    func matches(_ filter: LogFilter) -> Bool {
        if filter.onlyMarked && !flagged {
            return false
        } else if level.rawValue < filter.minLevel.rawValue {
            return false
        } else if let domains = filter.domains, !domains.contains(domain) {
            return false
        } else if let str = filter.string, !matches(str) {
            return false
        } else {
            return true
        }
    }
}

extension LogEntry : Equatable {
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        return lhs.index == rhs.index    // only works for entries in the same document
    }
}

extension LogEntry : Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
    }
}
