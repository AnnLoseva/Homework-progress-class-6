import Foundation
import Testing
@testable import StudyDomain

@Suite("Catalog filters and sorting")
struct LessonQueryTests {
    let a1 = Fixture.lesson("Vectors", .required, due: 5 * Fixture.day, week: 1)
    let a2 = Fixture.lesson("Matrices", .required, due: 2 * Fixture.day, week: 2)
    let a3 = Fixture.lesson("Determinant drills", .optional, week: 2)
    let b1 = Fixture.lesson("Propositional logic", .required, week: 1, course: Fixture.otherCourse)
    let draft = Fixture.lesson("Eigenvalues", .required, status: .draft, week: 6)
    let archived = Fixture.lesson("Old notes", .optional, status: .archived, week: 0)

    var catalog: Catalog {
        Catalog(courses: [Fixture.course, Fixture.otherCourse], lessons: [a1, a2, a3, b1, draft, archived])
    }

    @Test func studentsDefaultToPublishedLessonsOnly() {
        let titles = LessonQuery().apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title)
        #expect(!titles.contains("Eigenvalues"))
        #expect(!titles.contains("Old notes"))
        // Course order, then week, then position, then title.
        #expect(titles == ["Vectors", "Determinant drills", "Matrices", "Propositional logic"])
    }

    @Test func filterByCategory() {
        #expect(LessonQuery(category: .optional).apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title) == ["Determinant drills"])
        #expect(LessonQuery(category: .required).apply(to: catalog, subscriptions: [:], now: Fixture.now).count == 3)
    }

    @Test func filterByCourseAndWeek() {
        let query = LessonQuery(courseID: Fixture.course.id, week: 2)
        #expect(query.apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title) == ["Determinant drills", "Matrices"])
    }

    @Test func administratorsCanFilterByPublicationStatus() {
        let query = LessonQuery(statuses: [.draft])
        #expect(query.apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title) == ["Eigenvalues"])
    }

    @Test func filterByWorkloadMembership() {
        let subs = [a3.id: LessonSubscription(lessonID: a3.id, isActive: true)]
        let inWorkload = LessonQuery(subscription: .inMyWorkload).apply(to: catalog, subscriptions: subs, now: Fixture.now)
        #expect(inWorkload.count == 4)
        let notIn = LessonQuery(subscription: .notInMyWorkload).apply(to: catalog, subscriptions: [:], now: Fixture.now)
        #expect(notIn.map(\.title) == ["Determinant drills"])
    }

    @Test func sortByDueDate() {
        let titles = LessonQuery(sort: .dueDate).apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title)
        #expect(titles.prefix(2) == ["Matrices", "Vectors"])
    }

    @Test func searchMatchesTitleAndCourseIgnoringCase() {
        #expect(LessonQuery(searchText: "LOGIC").apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title) == ["Propositional logic"])
        #expect(LessonQuery(searchText: "discrete").apply(to: catalog, subscriptions: [:], now: Fixture.now).map(\.title) == ["Propositional logic"])
    }

    @Test func newLessonsAreThosePublishedSinceLastVisit() {
        let fresh = Fixture.lesson("Fresh", .optional, publishedAt: Fixture.now.addingTimeInterval(-60))
        let catalog = Catalog(courses: [Fixture.course], lessons: [a1, fresh])
        #expect(NewLessons.ids(in: catalog, since: Fixture.now.addingTimeInterval(-3600), now: Fixture.now) == [fresh.id])
        #expect(NewLessons.ids(in: catalog, since: nil, now: Fixture.now).isEmpty, "first launch shows nothing as new")
    }

    @Test func weeksListedForTheFilter() {
        #expect(LessonQuery.weeks(in: catalog, statuses: [.published]) == [1, 2])
    }
}

@Suite("Attachment validation")
struct AttachmentValidationTests {
    let pdfHeader = Data("%PDF-1.7\n".utf8)

    @Test func acceptsAPDF() throws {
        try AttachmentValidator.validate(fileName: "sheet.pdf", byteSize: 1000, header: pdfHeader)
    }

    @Test func rejectsEmptyOversizedAndNonPDFFiles() {
        #expect(throws: AttachmentValidationError.empty) {
            try AttachmentValidator.validate(fileName: "a.pdf", byteSize: 0, header: pdfHeader)
        }
        #expect(throws: AttachmentValidationError.tooLarge(maximumBytes: AttachmentValidator.maximumBytes)) {
            try AttachmentValidator.validate(fileName: "a.pdf", byteSize: AttachmentValidator.maximumBytes + 1, header: pdfHeader)
        }
        #expect(throws: AttachmentValidationError.notAPDF) {
            try AttachmentValidator.validate(fileName: "evil.pdf", byteSize: 10, header: Data("MZ\u{90}\0".utf8))
        }
    }

    @Test func sanitizesFileNames() throws {
        #expect(try AttachmentValidator.sanitizedFileName("../../etc/passwd") == "passwd.pdf")
        #expect(try AttachmentValidator.sanitizedFileName("תרגיל 1.pdf") == "תרגיל 1.pdf")
        #expect(try AttachmentValidator.sanitizedFileName("notes\u{0}.PDF") == "notes.PDF")
        #expect(throws: AttachmentValidationError.invalidFileName) { try AttachmentValidator.sanitizedFileName("..") }
    }

    @Test func storagePathsMatchTheBucketPolicyLayout() {
        let lesson = UUID(uuidString: "0A0A0A0A-0000-4000-8000-000000000001")!
        let attachment = UUID(uuidString: "0B0B0B0B-0000-4000-8000-000000000002")!
        #expect(StoragePath.lessonMaterial(lessonID: lesson, attachmentID: attachment, version: 3)
                == "0a0a0a0a-0000-4000-8000-000000000001/0b0b0b0b-0000-4000-8000-000000000002/v3.pdf")
    }

    @Test func replacingAFileChangesTheCacheKeyButNotTheID() {
        var attachment = LessonAttachment(lessonID: UUID(), title: "Sheet", fileName: "s.pdf", byteSize: 10)
        let before = attachment.cacheKey
        attachment.version += 1
        #expect(attachment.cacheKey != before)
        #expect(attachment.cacheKey.hasPrefix(attachment.id.uuidString.lowercased()))
    }
}

@Suite("Content drafts")
struct ContentDraftTests {
    @Test func lessonDraftValidation() {
        var draft = LessonDraft()
        #expect(draft.issues.contains(.titleMissing))
        #expect(draft.issues.contains(.courseMissing))
        draft.title = "Vectors"
        draft.courseID = UUID()
        #expect(draft.isValid)
        draft.exerciseCount = 501
        draft.availableFrom = Fixture.now
        draft.dueAt = Fixture.now.addingTimeInterval(-1)
        #expect(Set(draft.issues) == [.exerciseCountOutOfRange, .dueBeforeAvailable])
    }

    @Test func aLessonCannotBeItsOwnPrerequisite() {
        let id = UUID()
        let draft = LessonDraft(id: id, courseID: UUID(), title: "Loop", prerequisiteIDs: [id])
        #expect(draft.issues == [.lessonIsOwnPrerequisite])
    }

    @Test func courseSlugs() {
        #expect(CourseDraft.suggestedSlug(for: "Linear Algebra 2") == "linear-algebra-2")
        #expect(CourseDraft.suggestedSlug(for: "Café  Théorie!") == "cafe-theorie")
        #expect(CourseDraft.suggestedSlug(for: "אלגברה").hasPrefix("course-"))
        #expect(CourseDraft(slug: "Bad Slug", title: "x").issues == [.slugInvalid])
        #expect(CourseDraft(slug: "good-slug", title: "x").issues.isEmpty)
    }
}
