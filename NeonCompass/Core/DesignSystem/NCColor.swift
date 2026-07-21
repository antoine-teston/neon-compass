import SwiftUI

enum NCColor {
    static let nightSky = Color(RGBA(hex: "#0A081A")!)
    static let sunsetMagenta = Color(RGBA(hex: "#FF3388")!)
    static let sunsetViolet = Color(RGBA(hex: "#8C33F2")!)
    static let sunsetOrange = Color(RGBA(hex: "#FF8C40")!)
    static let neonCyan = Color(RGBA(hex: "#26F2F2")!)

    static let sunset = LinearGradient(
        colors: [sunsetMagenta, sunsetViolet, sunsetOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    struct RGBA: Equatable, Sendable {
        let red: Double, green: Double, blue: Double, alpha: Double

        init?(hex: String) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1.0
        }
    }
}

extension Color {
    init(_ rgba: NCColor.RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
