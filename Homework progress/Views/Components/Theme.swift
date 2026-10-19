//
//  Theme.swift
//  Homework progress
//
//  The same cozy "goblincore" language as Mood Pomodoro: warm parchment, forest greens,
//  hand-drawn illustrations and mushroom characters, Lora serif type. Every screen pulls
//  from these tokens instead of re-deriving colors.
//

import SwiftUI
import UIKit

enum AppTheme {
    // MARK: Colors

    /// Page background — the warm tan the forest illustration sits on.
    static let parchment = Color(red: 0.925, green: 0.878, blue: 0.773)
    /// Card/sheet surface — a touch lighter than the page so content reads as raised.
    static let parchmentCard = Color(red: 0.965, green: 0.937, blue: 0.867)
    /// Primary text — bark brown, never pure black.
    static let ink = Color(red: 0.290, green: 0.220, blue: 0.149)
    static let inkSoft = Color(red: 0.290, green: 0.220, blue: 0.149).opacity(0.62)
    /// Primary action color — forest green.
    static let forest = Color(red: 0.310, green: 0.400, blue: 0.271)
    static let forestDeep = Color(red: 0.204, green: 0.271, blue: 0.180)
    /// Accent — mushroom-cap rust.
    static let rust = Color(red: 0.659, green: 0.365, blue: 0.208)
    static let rustDeep = Color(red: 0.518, green: 0.271, blue: 0.145)
    static let moss = Color(red: 0.486, green: 0.545, blue: 0.353)
    static let border = Color(red: 0.788, green: 0.722, blue: 0.576)
    static let borderSoft = Color(red: 0.788, green: 0.722, blue: 0.576).opacity(0.55)
    /// Opaque chip/field fill — slightly deeper than the card.
    static let chipFill = Color(red: 0.945, green: 0.906, blue: 0.812)
}

extension Color {
    static let appBackground = AppTheme.parchment
    static let cardBackground = AppTheme.parchmentCard
    static let track = AppTheme.border.opacity(0.45)
}

/// Earthy course colors that sit comfortably on parchment. Keys are stored in the database,
/// so they keep their original names even though the shades changed.
enum CoursePalette: String, CaseIterable, Identifiable {
    case indigo, teal, coral, green, plum, blue, amber, slate

    var id: String { rawValue }

    var name: String {
        switch self {
        case .indigo: String(localized: "Dusk")
        case .teal: String(localized: "Moss")
        case .coral: String(localized: "Rust")
        case .green: String(localized: "Forest")
        case .plum: String(localized: "Berry")
        case .blue: String(localized: "Lake")
        case .amber: String(localized: "Honey")
        case .slate: String(localized: "Bark")
        }
    }

    private var hex: UInt32 {
        switch self {
        case .indigo: 0x5D6A8C
        case .teal: 0x5E7F5A
        case .coral: 0xA85D35
        case .green: 0x3F6650
        case .plum: 0x8C4A5E
        case .blue: 0x4A7088
        case .amber: 0xB38236
        case .slate: 0x7A6450
        }
    }

    var color: Color { Color(uiColor: UIColor(hex: hex)) }
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
    /// Hand-drawn illustrations (asset names) first, then SF Symbols as plain fallbacks.
    static let illustrations = [
        "CourseLinearAlgebra", "CourseComputational", "CourseAnalysis", "CourseSilicon", "CourseDiscrete",
        "CourseStudy", "CourseReading", "CourseWriting", "CourseSoldering", "CourseLaptop",
    ]
    static let symbols = [
        "square.grid.3x3", "function", "sum", "x.squareroot", "chevron.left.forwardslash.chevron.right",
        "cpu", "point.3.connected.trianglepath.dotted", "chart.xyaxis.line", "books.vertical", "graduationcap",
    ]
    static var choices: [String] { illustrations + symbols }

    static func isIllustration(_ name: String) -> Bool { name.hasPrefix("Course") && UIImage(named: name) != nil }
}

/// Mushroom friends that react to the week — encouraging, never guilt-inducing.
enum Mascot {
    static func image(for summary: ProgressSummary) -> String {
        if summary.isEmpty { return "MushroomCalm" }
        if summary.openAssignmentCount == 0 { return "MushroomCheer" }
        guard let fraction = summary.fraction else { return "MushroomCurious" }
        switch fraction {
        case ..<0.01: return "MushroomNeutral"
        case ..<0.5: return "MushroomCurious"
        case ..<1: return "MushroomGood"
        default: return "MushroomHappy"
        }
    }
}

// MARK: - Typography

extension Font {
    /// Lora serif, scaling with Dynamic Type.
    static func lora(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Lora-Bold"
        case .semibold: name = "Lora-SemiBold"
        case .medium: name = "Lora-Medium"
        default: name = "Lora-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func loraItalic(_ size: CGFloat) -> Font {
        .custom("LoraItalic-Italic", size: size, relativeTo: .body)
    }
}

// MARK: - Chrome

extension View {
    /// Parchment chrome: light appearance, forest tint, ink text, opaque parchment bars.
    func goblinChrome() -> some View {
        self
            .preferredColorScheme(.light)
            .tint(AppTheme.forest)
            .foregroundStyle(AppTheme.ink)
            .font(.lora(16))
            .toolbarBackground(AppTheme.parchmentCard, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    /// Forms and lists on parchment instead of system gray.
    func parchmentList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.parchment)
    }
}

enum AppChrome {
    static func apply() {
        let ink = UIColor(AppTheme.ink)
        let card = UIColor(AppTheme.parchmentCard)
        let page = UIColor(AppTheme.parchment)
        let border = UIColor(AppTheme.border)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = card
        nav.shadowColor = border
        nav.titleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(name: "Lora-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(name: "Lora-Bold", size: 32) ?? .systemFont(ofSize: 32, weight: .bold),
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.forest)
        UINavigationBar.appearance().overrideUserInterfaceStyle = .light

        UITextField.appearance().textColor = ink
        UITextView.appearance().textColor = ink
        UIDatePicker.appearance().overrideUserInterfaceStyle = .light
        UITableView.appearance().backgroundColor = page
        UISwitch.appearance().onTintColor = UIColor(AppTheme.forest)
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).overrideUserInterfaceStyle = .light
    }
}

// MARK: - Backdrop

/// The illustrated forest frame behind a screen; iPad gets its wider composition.
struct ForestBackdrop: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            Image(horizontalSizeClass == .regular ? "IpadBackground" : "ForestBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .background(AppTheme.parchment)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .parchmentSurface()
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    /// Parchment card background with a hand-inked border and soft shadow.
    func parchmentSurface(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(AppTheme.parchmentCard))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(AppTheme.border, lineWidth: 1.25))
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }
}

/// Section title in Lora, with an optional little leaf.
struct SectionTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.lora(20, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(AppTheme.parchmentCard.opacity(0.85), in: Capsule())
    }
}

// MARK: - Buttons

struct GoblinButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind = .primary
    var fill: Color = AppTheme.forest

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lora(17, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule(style: .continuous).fill(background))
            .overlay(Capsule(style: .continuous).stroke(AppTheme.border, lineWidth: kind == .secondary ? 1.5 : 0))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: fill
        case .secondary: AppTheme.chipFill
        case .destructive: AppTheme.rustDeep
        }
    }

    private var foreground: Color {
        kind == .secondary ? AppTheme.ink : AppTheme.parchmentCard
    }
}

extension ButtonStyle where Self == GoblinButtonStyle {
    static var goblinPrimary: GoblinButtonStyle { GoblinButtonStyle(kind: .primary) }
    static var goblinSecondary: GoblinButtonStyle { GoblinButtonStyle(kind: .secondary) }
    static var goblinDestructive: GoblinButtonStyle { GoblinButtonStyle(kind: .destructive) }
    static func goblinPrimary(_ fill: Color) -> GoblinButtonStyle { GoblinButtonStyle(kind: .primary, fill: fill) }
}

/// Small rounded chip used for status and sort controls.
struct ChipBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppTheme.chipFill))
            .overlay(Capsule().stroke(AppTheme.borderSoft, lineWidth: 1))
    }
}

extension View {
    func chip() -> some View { modifier(ChipBackground()) }
}
