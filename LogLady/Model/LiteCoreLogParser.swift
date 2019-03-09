//
//  LiteCoreLogParser.swift
//  Log Lady
//
//  Created by Jens Alfke on 3/8/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Foundation


class LiteCoreBinaryLogParser : LogParser {

    func parseDirectory(dir: URL) throws -> [LogEntry] {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        var entries = try files.flatMap { (item) in
            return try parse(dir.appendingPathComponent(item))
        }
        entries = entries.sorted(by: { $0.timestamp < $1.timestamp })
        var i = 0
        for e in entries {
            e.index = i
            i += 1
        }
        return entries
    }

    func parse(_ url: URL) throws -> [LogEntry] {
        return try parse(filePath: url.path)
    }

    func parse(filePath: String) throws -> [LogEntry] {
        NSLog("Reading binary log file \(filePath)")
        guard DecodeLogFile(filePath) else {
            throw NSError(domain: "LogLady", code: -1, userInfo: nil)
        }

        var objects = [UInt64:String]()

        var entries = [LogEntry]()
        var index = 0
        var e = BinaryLogEntry()
        while true {
            let status = NextLogEntry(&e)
            guard status >= 0 else {
                throw NSError(domain: "LogLady", code: -1, userInfo: nil)
            }
            if status == 0 {
                break
            }

            let timestamp = Double(e.secs) + Double(e.microsecs) / 1.0e6
            let domain = LogDomain.named(LogEntryDomain())

            var object: Substring? = nil
            if e.objectID > 0 {
                if let desc = objects[e.objectID] {
                    object = Substring(desc)
                } else {
                    let desc = "\(LogEntryObjectDescription()!)#\(e.objectID)"
                    objects[e.objectID] = desc
                    object = Substring(desc)
                }
            }

            let message: String = LogEntryMessage()
            entries.append(LogEntry(index: index, line: Substring(message), timestamp: timestamp,
                                    level: LogLevel(rawValue: e.level + 1)!,
                                    domain: domain, object: object,
                                    message: Substring(message)))
            index += 1
        }
        EndLogDecoder()
        return entries
    }


}
