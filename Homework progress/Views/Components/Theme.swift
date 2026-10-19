//
//  Theme.swift
//  Homework progress
//

import SwiftUI
import UIKit

/// Course colors. Each has a tuned light and dark variant so all five stay distinguishable and
/// readable on neutral backgrounds in both appearances.
enum CoursePalette: String, CaseIterable, Identifiable {
    case indigo, teal, coral, green, plum, blue, amber, slate

    var id: String { rawValue }

    var name: String {
        switch self {
        case .indigo: String(localized: "Indigo")
        case .teal: String(localized: "Teal")
        case .coral: String(localized: "Coral")
        case .green: String(localized: "Green")
        case .plum: String(localized: "Plum")
        case .blue: String(localized: "Blue")
        case .amber: String(localized: "Amber")
        case .slate: String(localized: "Slate")
        }
    }

    private var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .indigo: (0x5856D6, 0x8E8CF5)
        case .teal: (0x168A8A, 0x4FC9C4)
        case .coral: (0xD9573B, 0xFF8A6B)
        case .green: (0x3A8A3F, 0x6FCF73)
        case .plum: (0xA0479B, 0xE08AD9)
        case .blue: (0x1F6FD1, 0x6AA8FF)
        case .amber: (0xB7791F, 0xF2B544)
        case .slate: (0x5B6577, 0x9AA5B8)
        }
    }

    var color: Color {
        let (light, dark) = hex
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

enum CourseIcons {
    static let choices = [
        "square.grid.3x3", "function", "sum", "x.squareroot", "chevron.left.forwardslash.chevron.right",
        "cpu", "memorychip", "point.3.connected.trianglepath.dotted", "chart.xyaxis.line", "books.vertical",
        "book.closed", "graduationcap", "brain.head.profile", "terminal", "atom", "pencil.and.ruler",
    ]
}

extension Color {
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let track = Color(uiColor: .tertiarySystemFill)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}
