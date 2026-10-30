import Foundation

/// Decimal units, as Finder shows them: "1.4 GB", "210 MB".
func fmtBytes(_ bytes: Int64) -> String {
    let (value, unit) = splitBytes(bytes)
    return "\(value) \(unit)"
}

/// The number and unit separately, for big numbers with a smaller unit.
func splitBytes(_ bytes: Int64) -> (String, String) {
    let b = Double(max(0, bytes))
    switch b {
    case 1e12...: return (String(format: "%.2f", b / 1e12), "TB")
    case 1e11...: return (String(format: "%.0f", b / 1e9), "GB")
    case 1e9...:  return (String(format: "%.1f", b / 1e9), "GB")
    case 1e6...:  return (String(format: "%.0f", b / 1e6), "MB")
    case 1e3...:  return (String(format: "%.0f", b / 1e3), "KB")
    default:      return ("0", "MB")
    }
}

/// "today", "yesterday", "12 days", "4 months".
func fmtIdle(_ seconds: TimeInterval) -> String {
    let days = Int(seconds / 86_400)
    switch days {
    case ..<1:   return "today"
    case 1:      return "yesterday"
    case ..<60:  return "\(days) days"
    case ..<730: return "\(days / 30) months"
    default:     return "\(days / 365) years"
    }
}

func fmtAgo(_ date: Date, now: Date = Date()) -> String {
    let s = Int(now.timeIntervalSince(date))
    switch s {
    case ..<60:     return "just now"
    case ..<3600:   return "\(s / 60) min ago"
    case ..<86_400: return "\(s / 3600) h ago"
    default:        return "\(s / 86_400) d ago"
    }
}

func abbreviate(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
