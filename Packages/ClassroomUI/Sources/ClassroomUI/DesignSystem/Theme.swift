import SwiftUI
import UIKit
import StudyDomain

// The woodland study look: warm parchment, olive and forest greens, mushroom brown, rust and
// soft lavender, Lora serif type and hand-drawn illustrations. Every color has a light and a
// dark variant, and text colors keep WCAG AA contrast on their surfaces.

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func adaptive(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: alpha) : UIColor(hex: light, alpha: alpha)
        }
    }
}

enum Palette {
    /// Page background: warm parchment / night forest floor.
    static let page = Color(uiColor: .adaptive(light: 0xECE0C5, dark: 0x1C1F18))
    /// Raised card surface.
    static let card = Color(uiColor: .adaptive(light: 0xF6EFDD, dark: 0x272A21))
    /// Opaque chip / field fill.
    static let chip = Color(uiColor: .adaptive(light: 0xF1E7CF, dark: 0x33362B))
    /// Primary text: bark brown / warm cream. Never pure black or white.
    static let ink = Color(uiColor: .adaptive(light: 0x4A3826, dark: 0xEFE5CF))
    static let inkSoft = Color(uiColor: .adaptive(light: 0x6B5843, dark: 0xC9BEA6))
    /// Primary actions: forest green.
    static let forest = Color(uiColor: .adaptive(light: 0x4F6645, dark: 0x8FA77A))
    static let forestDeep = Color(uiColor: .adaptive(light: 0x34452E, dark: 0xB5C9A2))
    static let olive = Color(uiColor: .adaptive(light: 0x6E7240, dark: 0xB3B67F))
    static let mushroom = Color(uiColor: .adaptive(light: 0x7A6450, dark: 0xBFA68E))
    static let rust = Color(uiColor: .adaptive(light: 0xA2532C, dark: 0xE09468))
    static let lavender = Color(uiColor: .adaptive(light: 0x6E5F96, dark: 0xBDAFE0))
    static let border = Color(uiColor: .adaptive(light: 0xC9B893, dark: 0x4C4E3F))
    static let borderSoft = Color(uiColor: .adaptive(light: 0xC9B893, dark: 0x4C4E3F, alpha: 0.55))
    static let track = Color(uiColor: .adaptive(light: 0xC9B893, dark: 0x4C4E3F, alpha: 0.5))
    static let onAccent = Color(uiColor: .adaptive(light: 0xF6EFDD, dark: 0x1C1F18))

    /// Course colors stored in the database (`courses.color_key`).
    static func course(_ key: String) -> Color {
        switch key {
        case "dusk": Color(uiColor: .adaptive(light: 0x5D6A8C, dark: 0x9CA8C8))
        case "moss": Color(uiColor: .adaptive(light: 0x5E7F5A, dark: 0x96B791))
        case "rust": Color(uiColor: .adaptive(light: 0xA85D35, dark: 0xDE9468))
        case "berry": Color(uiColor: .adaptive(light: 0x8C4A5E, dark: 0xD08CA0))
        case "lake": Color(uiColor: .adaptive(light: 0x4A7088, dark: 0x8DB2C8))
        case "honey": Color(uiColor: .adaptive(light: 0x94692A, dark: 0xD9AE68))
        case "bark": Color(uiColor: .adaptive(light: 0x7A6450, dark: 0xBFA68E))
        case "lavender": lavender
        default: forest
        }
    }
}

/// Required (חובה) is rust/terracotta with a pin; optional (רשות) is lavender with a leaf.
/// Shape and text carry the meaning too, never color alone.
extension LessonCategory {
    var color: Color { self == .required ? Palette.rust : Palette.lavender }
    var symbol: String { self == .required ? "pin.fill" : "leaf.fill" }
    var title: LocalizedStringKey { self == .required ? "Required" : "Optional" }
    var titleString: String { self == .required ? String(localized: "Required") : String(localized: "Optional") }
}

extension ProgressStatus {
    var title: LocalizedStringKey {
        switch self {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: Palette.inkSoft
        case .inProgress: Palette.olive
        case .completed: Palette.forest
        }
    }
}

extension LessonStatus {
    var title: LocalizedStringKey {
        switch self {
        case .draft: "Draft"
        case .published: "Published"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .draft: "pencil.circle"
        case .published: "checkmark.seal"
        case .archived: "archivebox"
        }
    }
}

// MARK: - Typography

extension Font {
    /// Lora serif, scaling with Dynamic Type. Hebrew falls back to the system font
    /// automatically (Lora has no Hebrew glyphs).
    static func lora(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String = switch weight {
        case .bold, .heavy, .black: "Lora-Bold"
        case .semibold: "Lora-SemiBold"
        case .medium: "Lora-Medium"
        default: "Lora-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static let woodTitle = Font.lora(28, weight: .bold, relativeTo: .largeTitle)
    static let woodHeadline = Font.lora(19, weight: .semibold, relativeTo: .headline)
    static let woodBody = Font.lora(16, relativeTo: .body)
}

// MARK: - Surfaces

extension View {
    /// A parchment card with an inked border.
    func woodCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    func woodChip(fill: Color = Palette.chip) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Palette.borderSoft, lineWidth: 1))
    }

    /// Lists and forms on parchment instead of system gray.
    func woodList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.page)
    }

    func woodChrome() -> some View {
        self
            .tint(Palette.forest)
            .foregroundStyle(Palette.ink)
            .font(.woodBody)
    }
}

/// The hand-drawn forest behind the main screens. Dimmed in Dark Mode, hidden when the user
/// asks for reduced transparency, so text always stays legible.
struct ForestBackdrop: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Palette.page
            if !reduceTransparency {
                Image(sizeClass == .regular ? "IpadBackground" : "ForestBackground")
                    .resizable()
                    .scaledToFill()
                    .opacity(colorScheme == .dark ? 0.18 : 0.55)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct WoodButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lora(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(kind == .secondary ? Palette.ink : Palette.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(Palette.border, lineWidth: kind == .secondary ? 1.2 : 0))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.forest
        case .secondary: Palette.chip
        case .destructive: Palette.rust
        }
    }
}

extension ButtonStyle where Self == WoodButtonStyle {
    static var woodPrimary: WoodButtonStyle { WoodButtonStyle(kind: .primary) }
    static var woodSecondary: WoodButtonStyle { WoodButtonStyle(kind: .secondary) }
    static var woodDestructive: WoodButtonStyle { WoodButtonStyle(kind: .destructive) }
}

enum CourseIcons {
    /// Hand-drawn illustrations bundled with the app.
    static let illustrations = [
        "CourseLinearAlgebra", "CourseComputational", "CourseAnalysis", "CourseSilicon", "CourseDiscrete",
        "CourseStudy", "CourseReading", "CourseWriting", "CourseSoldering", "CourseLaptop",
    ]

    static func exists(_ name: String) -> Bool { UIImage(named: name) != nil }
}

/// Mushroom friends react to progress: encouraging, never guilt-inducing.
enum Mascot {
    static func image(for summary: DashboardSummary) -> String {
        if summary.isEmpty { return "MushroomCalm" }
        if summary.isAllDone { return "MushroomCheer" }
        switch summary.lessonCompletionFraction ?? 0 {
        case ..<0.01: return "MushroomNeutral"
        case ..<0.5: return "MushroomCurious"
        case ..<1: return "MushroomGood"
        default: return "MushroomHappy"
        }
    }
}
