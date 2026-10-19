//
//  ProgressComponents.swift
//  Homework progress
//

import SwiftUI

/// A calm, rounded progress bar with an inked outline, like a little vine filling up.
/// `fraction == nil` renders an empty track ("no count").
struct ProgressBar: View {
    var fraction: Double?
    var tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.chipFill)
                if let fraction {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * min(1, max(0, fraction))))
                }
                Capsule().stroke(AppTheme.border, lineWidth: 1)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(fraction.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("No exercise count"))
    }
}

/// Course icon: a hand-drawn illustration when the course uses one, otherwise an SF Symbol
/// on a soft tile in the course color.
struct CourseIconView: View {
    var iconName: String
    var palette: CoursePalette
    var size: CGFloat = 36

    var body: some View {
        Group {
            if CourseIcons.isIllustration(iconName) {
                Image(iconName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(palette.color)
                    .frame(width: size, height: size)
                    .background(palette.color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A mushroom friend (or other illustration) sized for cards and empty states.
struct Illustration: View {
    let name: String
    var size: CGFloat = 88

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Cozy empty state: an illustration, a Lora title, a short message and an optional action.
struct CozyEmptyState<Actions: View>: View {
    let image: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Illustration(name: image, size: 120)
            Text(title)
                .font(.lora(22, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.lora(15))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(26)
        .frame(maxWidth: 380)
        .parchmentSurface(cornerRadius: 28)
        .padding(24)
    }
}

/// Course title that renders a Hebrew name right-to-left, with the English label underneath.
struct CourseTitleView: View {
    var course: Course
    var titleFont: Font = .lora(17, weight: .semibold)
    var showsEnglish = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name)
                .font(titleFont)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsEnglish, !course.englishName.isEmpty {
                Text(course.englishName)
                    .font(.lora(12))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    var status: AssignmentStatus

    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .font(.lora(12, weight: .medium))
            .foregroundStyle(status == .completed ? AppTheme.forest : .secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct DueDateText: View {
    var date: Date

    var body: some View {
        Label {
            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        } icon: {
            Image(systemName: "calendar")
        }
        .font(.lora(12))
        .foregroundStyle(date < .now ? AppTheme.rust : .secondary)
    }
}

/// "6 / 9" with "3 left", or a placeholder when there is no count.
struct ExerciseCountText: View {
    var progress: AssignmentProgress

    var body: some View {
        if let total = progress.total, total > 0 {
            HStack(spacing: 6) {
                Text("\(progress.completed)/\(total)")
                    
                    .contentTransition(.numericText())
                if let remaining = progress.remaining, remaining > 0 {
                    Text("· \(remaining) left").foregroundStyle(.secondary)
                }
            }
        } else if progress.completed > 0 {
            Text("\(progress.completed) done")
        } else {
            Text("No count").foregroundStyle(.secondary)
        }
    }
}
