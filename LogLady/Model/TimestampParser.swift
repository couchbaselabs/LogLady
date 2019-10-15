//
//  TimestampParser.swift
//  Log Lady
//
//  Created by Jens Alfke on 10/15/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Foundation


struct TimestampParser {

    init(_ regexStr: String, _ formatStr: String) {
        try! regex = NSRegularExpression(pattern: "^\\s*" + regexStr + "\\b")
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = formatStr
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.defaultDate = Date(timeIntervalSince1970: round(Date().timeIntervalSince1970))
    }

    func parse(_ line: String) -> (TimeInterval, Substring)? {
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.count)),
            let timestamp = timestamp(fromMatch: m, in: line)
            else { return nil }
        let dateRange = Range(m.range(at: 0), in: line)!
        return (timestamp, line[dateRange.upperBound...])
    }

    func timestamp(fromMatch m: NSTextCheckingResult, in line: String) -> TimeInterval? {
        // It's necessary to parse the fractional seconds separately, because DateFormatter will
        // only parse 3 decimal digits, i.e. to the nearest millisecond, but we need full accuracy.
        guard let dateStr = matched(m, 1, in: line),
            let date = dateFormatter.date(from: String(dateStr)),
            let subSecondsStr = matched(m, 2, in: line),
            let subSeconds = Double(subSecondsStr)
            else { return nil }
        return date.timeIntervalSince1970 + subSeconds
    }

    private func matched(_ match: NSTextCheckingResult, _ group: Int, in str: String) -> Substring? {
        guard let r = Range(match.range(at: group), in: str)
            else { return nil }
        return str[r]
    }

    let regex: NSRegularExpression
    let dateFormatter: DateFormatter
}
