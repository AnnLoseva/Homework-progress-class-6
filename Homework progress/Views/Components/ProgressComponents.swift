//
//  ProgressComponents.swift
//  Homework progress
//

import SwiftUI

/// A calm, rounded progress bar. `fraction == nil` renders an empty dashed track ("no count").
struct ProgressBar: View {
    var fraction: Double?
    var tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                if let fraction {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * min(1, max(0, fraction))))
                }
            }
        }
        .frame(height: height)
        .animation(.snappy(duration: 0.35), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(fraction.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("No exercise count"))
    }
}

/// Small rounded-square course icon.
struct CourseIconView: View {
    var iconName: String
    var palette: CoursePalette
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(palette.color)
            .frame(width: size, height: size)
            .background(palette.color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Course title that renders a Hebrew name right-to-left, with the English label underneath.
struct CourseTitleView: View {
    var course: Course
    var titleFont: Font = .headline
    var showsEnglish = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name)
                .font(titleFont)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsEnglish, !course.englishName.isEmpty {
                Text(course.englishName)
                    .font(.caption)
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
            .font(.caption.weight(.medium))
            .foregroundStyle(status == .completed ? Color.green : .secondary)
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
        .font(.caption)
        .foregroundStyle(date < .now ? Color.orange : .secondary)
    }
}

/// "6 / 9" with "3 left", or a placeholder when there is no count.
struct ExerciseCountText: View {
    var progress: AssignmentProgress

    var body: some View {
        if let total = progress.total, total > 0 {
            HStack(spacing: 6) {
                Text("\(progress.completed)/\(total)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let remaining = progress.remaining, remaining > 0 {
                    Text("· \(remaining) left").foregroundStyle(.secondary)
                }
            }
        } else if progress.completed > 0 {
            Text("\(progress.completed) done").monospacedDigit()
        } else {
            Text("No count").foregroundStyle(.secondary)
        }
    }
}
