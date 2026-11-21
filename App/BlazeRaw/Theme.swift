import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.04, blue: 0.09)
    static let card = Color.white.opacity(0.07)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.11)
    static let pink = Color(red: 1.0, green: 0.18, blue: 0.39)

    static var accent: LinearGradient {
        LinearGradient(colors: [orange, pink], startPoint: .leading, endPoint: .trailing)
    }
}

/// 83 seconds -> "1:23"
func mmss(_ seconds: Double) -> String {
    let s = Int(max(0, seconds).rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}
