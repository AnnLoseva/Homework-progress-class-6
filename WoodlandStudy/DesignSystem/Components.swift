import SwiftUI
import StudyDomain
import StudyData

/// "Required" / "Optional" badge. The academic category, not subscription or completion.
struct CategoryBadge: View {
    let category: LessonCategory
    var compact = false

    var body: some View {
        Label {
            Text(category.title)
        } icon: {
            Image(systemName: category.symbol)
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
        .font(.lora(compact ? 12 : 13, weight: .semibold, relativeTo: .caption))
        .foregroundStyle(category.color)
        .woodChip(fill: category.color.opacity(0.13))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Category: \(category.titleString)"))
    }
}

struct ProgressStatusBadge: View {
    let status: ProgressStatus

    var body: some View {
        Label { Text(status.title) } icon: { Image(systemName: status.symbol) }
            .lineLimit(1)
            .fixedSize()
            .font(.lora(12, weight: .medium, relativeTo: .caption))
            .foregroundStyle(status.color)
            .accessibilityElement(children: .combine)
    }
}

struct LessonStatusBadge: View {
    let status: LessonStatus

    var body: some View {
        Label { Text(status.title) } icon: { Image(systemName: status.symbol) }
            .font(.lora(12, weight: .medium, relativeTo: .caption))
            .foregroundStyle(status == .published ? Palette.forest : Palette.mushroom)
            .woodChip()
    }
}

/// Circular progress with the percentage inside. `fraction == nil` shows a dash.
struct ProgressRing: View {
    let fraction: Double?
    var lineWidth: CGFloat = 9
    var tint: Color = Palette.forest
    var label: LocalizedStringKey

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            Text(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
                .font(.lora(18, weight: .bold, relativeTo: .title3))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? String(localized: "No data yet")))
    }
}

struct CourseIcon: View {
    let course: Course?
    var size: CGFloat = 44

    var body: some View {
        let name = course?.iconName ?? "CourseStudy"
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Palette.course(course?.colorKey ?? "forest").opacity(0.16))
            if CourseIcons.exists(name) {
                Image(name).resizable().scaledToFit().padding(size * 0.06)
            } else {
                Image(systemName: "book.closed").foregroundStyle(Palette.course(course?.colorKey ?? "forest"))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A friendly empty state with a mushroom.
struct EmptyStateView: View {
    let image: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(image).resizable().scaledToFit().frame(maxWidth: 120).accessibilityHidden(true)
            Text(title).font(.woodHeadline).multilineTextAlignment(.center)
            Text(message).font(.woodBody).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Shows offline / syncing / pending changes, so the student always knows where their data is.
struct SyncStatusBanner: View {
    let status: SyncStatus
    let pendingChanges: Int
    let lastSynced: Date?

    var body: some View {
        if let content {
            HStack(spacing: 8) {
                Image(systemName: content.symbol)
                Text(content.text).font(.lora(13, relativeTo: .footnote))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Palette.chip))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("syncBanner")
        }
    }

    private var content: (symbol: String, text: String)? {
        switch status {
        case .offline:
            return ("wifi.slash", pendingChanges > 0
                    ? String(localized: "Offline · \(pendingChanges) change(s) will sync when you reconnect")
                    : String(localized: "Offline · showing saved data"))
        case .failed(let message):
            return ("exclamationmark.triangle", String(localized: "Couldn't sync: \(message)"))
        case .syncing where pendingChanges > 0:
            return ("arrow.triangle.2.circlepath", String(localized: "Syncing \(pendingChanges) change(s)…"))
        default:
            return nil
        }
    }
}

/// Label + value pair for metadata rows.
struct MetadataRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.lora(15, relativeTo: .subheadline))
        .accessibilityElement(children: .combine)
    }
}

extension Date {
    var shortDueText: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) }
}
