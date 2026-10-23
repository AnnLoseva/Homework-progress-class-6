import Foundation
@testable import StudyData
import StudyDomain

/// Test fixtures only: a made-up catalog with generated PDFs, mirroring
/// supabase/tests/fixtures.sql. The app itself never shows this content.
enum TestCatalog {
    static func make(now: Date) -> (Catalog, [String: Data]) {
        let day: TimeInterval = 24 * 3600
        let linear = Course(id: UUID(uuidString: "00000000-0000-4000-8000-000000000c01")!, slug: "linear-algebra",
                            title: "Linear Algebra", subtitle: "אלגברה לינארית", iconName: "CourseLinearAlgebra",
                            colorKey: "dusk", sortOrder: 1)
        let discrete = Course(id: UUID(uuidString: "00000000-0000-4000-8000-000000000c02")!, slug: "discrete-math",
                              title: "Discrete Mathematics", subtitle: "מתמטיקה בדידה", iconName: "CourseDiscrete",
                              colorKey: "moss", sortOrder: 2)
        let skills = Course(id: UUID(uuidString: "00000000-0000-4000-8000-000000000c03")!, slug: "study-skills",
                            title: "Study Skills", subtitle: "מיומנויות למידה", iconName: "CourseStudy",
                            colorKey: "honey", sortOrder: 3)

        func lesson(_ suffix: String, _ course: Course, _ title: String, _ description: String,
                    _ category: LessonCategory, week: Int, module: String, order: Int,
                    dueInDays: Double? = nil, minutes: Int?, exercises: Int,
                    status: LessonStatus = .published, publishedDaysAgo: Double = 7) -> Lesson {
            Lesson(id: UUID(uuidString: "00000000-0000-4000-8000-000000000\(suffix)")!, courseID: course.id,
                   title: title, description: description, category: category, status: status, week: week,
                   moduleTitle: module, sortOrder: order, dueAt: dueInDays.map { now.addingTimeInterval($0 * day) },
                   estimatedMinutes: minutes, exerciseCount: exercises,
                   publishedAt: status == .draft ? nil : now.addingTimeInterval(-publishedDaysAgo * day),
                   archivedAt: status == .archived ? now.addingTimeInterval(-day) : nil,
                   createdAt: now.addingTimeInterval(-30 * day), updatedAt: now.addingTimeInterval(-day))
        }

        let vectors = lesson("1a1", linear, "Vectors and linear combinations",
                             "Span, linear combinations and the geometric picture of vectors in ℝ².",
                             .required, week: 1, module: "Foundations", order: 1, dueInDays: 5, minutes: 90, exercises: 8)
        var matrices = lesson("1a2", linear, "Matrices as transformations",
                              "Reading a matrix as a function; composition as multiplication.",
                              .required, week: 2, module: "Foundations", order: 2, dueInDays: 12, minutes: 120, exercises: 10)
        matrices.prerequisiteIDs = [vectors.id]
        let determinants = lesson("1a3", linear, "Extra practice: determinants",
                                  "Optional drills for anyone who wants more determinant practice.",
                                  .optional, week: 2, module: "Foundations", order: 3, minutes: 45, exercises: 12,
                                  publishedDaysAgo: 1)
        let logic = lesson("1b1", discrete, "Propositional logic",
                           "Truth tables, implication and logical equivalence. תרגול בעברית מצורף.",
                           .required, week: 1, module: "Logic", order: 1, dueInDays: 3, minutes: 60, exercises: 6)
        let puzzles = lesson("1b2", discrete, "Puzzle corner: pigeonhole principle",
                             "Optional puzzles. No numbered exercises — mark it complete when you are done.",
                             .optional, week: 3, module: "Combinatorics", order: 1, minutes: 30, exercises: 0)
        let planning = lesson("1c1", skills, "Planning your study week",
                              "A short reading on spaced repetition and weekly planning.",
                              .optional, week: 0, module: "Orientation", order: 1, minutes: 20, exercises: 0)
        let oldNotes = lesson("1c2", skills, "Last semester's orientation notes",
                              "Kept for reference; replaced by \"Planning your study week\".",
                              .optional, week: 0, module: "Orientation", order: 2, minutes: 15, exercises: 0,
                              status: .archived, publishedDaysAgo: 120)
        let eigen = lesson("1d1", linear, "Eigenvalues (draft)", "Not published yet — students must not see this lesson.",
                           .required, week: 6, module: "Spectral theory", order: 1, minutes: 120, exercises: 9, status: .draft)

        var files: [String: Data] = [:]
        func attach(_ id: String, _ lesson: Lesson, _ title: String, _ visibility: AttachmentVisibility, lines: [String]) -> LessonAttachment {
            let data = SamplePDF.make(title: title, lines: lines)
            let attachment = LessonAttachment(id: UUID(uuidString: "00000000-0000-4000-8000-0000000\(id)")!, lessonID: lesson.id,
                                              title: title, description: visibility == .public ? "Open to everyone" : "Class members only",
                                              visibility: visibility, fileName: "\(title).pdf", byteSize: Int64(data.count))
            files[attachment.storagePath] = data
            return attachment
        }

        let attachments = [
            attach("0a001", vectors, "Vectors worksheet", .restricted,
                   lines: ["Exercises 1-8", "Write each vector as a linear combination.", "Synthetic sample content."]),
            attach("0a002", vectors, "Reading guide", .public, lines: ["Read sections 1.1-1.3.", "Synthetic sample content."]),
            attach("0a003", logic, "Truth tables", .restricted, lines: ["Exercises 1-6", "Synthetic sample content."]),
            attach("0a004", planning, "Weekly planner", .public, lines: ["Mon  Tue  Wed  Thu  Fri", "Synthetic sample content."]),
        ]

        return (Catalog(courses: [linear, discrete, skills],
                        lessons: [vectors, matrices, determinants, logic, puzzles, planning, oldNotes, eigen],
                        attachments: attachments), files)
    }
}

/// Builds a tiny, valid one-page PDF with Helvetica text. No dependencies, so it works in
/// tests on any platform.
enum SamplePDF {
    static func make(title: String, lines: [String]) -> Data {
        func escape(_ s: String) -> String {
            // Standard 14 fonts only cover Latin-1; replace anything else for the sample.
            let latin = s.unicodeScalars.map { $0.value < 256 ? String($0) : "?" }.joined()
            return latin.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        }
        var content = "BT /F1 22 Tf 72 740 Td (\(escape(title))) Tj ET\n"
        for (index, line) in lines.enumerated() {
            content += "BT /F1 13 Tf 72 \(700 - index * 22) Td (\(escape(line))) Tj ET\n"
        }
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}
