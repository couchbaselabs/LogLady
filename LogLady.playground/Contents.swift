import Foundation

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "HH:mm:ss.SSSSSS"
dateFormatter.defaultDate = Date()
let timeStr = "00:47:33.135791"
let date = dateFormatter.date(from: String(timeStr))
date?.timeIntervalSince1970
