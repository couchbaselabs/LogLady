import Cocoa

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "HH:mm:ss.SSSSSS"
dateFormatter.defaultDate = Date()

var kLineRegexStr = "^(\\d\\d:\\d\\d:\\d\\d.\\d+)\\|\\s*(\\[(\\w+)\\](\\s\\w+)?:\\s*(\\{.*\\})?)?\\s+(.*)$"
var lineRegex = try! NSRegularExpression(pattern: kLineRegexStr)

var line = "18:21:02.502713| [Sync] WARNING: {repl#1234} now busy"

var m = lineRegex.firstMatch(in: line, range: NSRange(location: 0,length: line.count))!

let r = Range(m.range(at: 4), in: line)

let timeStr = line[r!]

let date = dateFormatter.date(from: String(timeStr))
