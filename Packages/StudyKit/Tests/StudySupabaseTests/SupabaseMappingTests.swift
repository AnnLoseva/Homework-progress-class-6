import Foundation
import Testing
import Supabase
@testable import StudySupabase
@testable import StudyData
@testable import StudyDomain

@Suite("Row mapping")
struct RowMappingTests {
    @Test func parsesPostgresTimestamps() throws {
        let microseconds = try #require(PostgresDate.parse("2026-10-22T12:00:00.123456+00:00"))
        #expect(abs(microseconds.timeIntervalSince1970 - 1_792_670_400.123) < 0.001)
        #expect(PostgresDate.parse("2026-10-22T12:00:00Z") != nil)
        #expect(PostgresDate.parse("2026-10-22 15:00:00+03") == PostgresDate.parse("2026-10-22T12:00:00Z"))
        #expect(PostgresDate.parse("not a date") == nil)
    }

    @Test func decodesALessonRowAsReturnedByPostgREST() throws {
        let json = """
        {"id":"00000000-0000-4000-8000-0000000001a1","course_id":"00000000-0000-4000-8000-000000000c01",
         "title":"Vectors","description":"תיאור","category":"required","status":"published","week":1,
         "module_title":null,"sort_order":2,"available_from":null,"due_at":"2026-10-27T21:59:00+00:00",
         "estimated_minutes":90,"exercise_count":8,"published_at":"2026-10-20T08:00:00.5+00:00",
         "archived_at":null,"created_by":"11111111-1111-4111-8111-111111111111",
         "created_at":"2026-10-01T08:00:00+00:00","updated_at":"2026-10-21T08:00:00+00:00"}
        """
        let row = try SupabaseCoding.decoder.decode(LessonRow.self, from: Data(json.utf8))
        let lesson = row.domain(prerequisites: [])
        #expect(lesson.category == .required)
        #expect(lesson.status == .published)
        #expect(lesson.description == "תיאור")
        #expect(lesson.exerciseCount == 8)
        #expect(lesson.dueAt != nil)
        #expect(lesson.moduleTitle == nil)
        #expect(lesson.weekStartsOn == nil, "rows from before the week dates existed still decode")
    }

    @Test func classWeekDatesRoundTripAsCalendarDays() throws {
        let json = """
        {"id":"00000000-0000-4000-8000-0000000001a1","course_id":"00000000-0000-4000-8000-000000000c01",
         "title":"HW1","description":"","category":"optional","status":"published","week":1,
         "module_title":"Week 1","sort_order":0,"available_from":null,"due_at":null,"estimated_minutes":null,
         "exercise_count":9,"published_at":"2026-10-20T08:00:00+00:00","archived_at":null,
         "created_at":"2026-10-01T08:00:00+00:00","updated_at":"2026-10-21T08:00:00+00:00",
         "week_starts_on":"2026-10-18","week_ends_on":"2026-10-23"}
        """
        let lesson = try SupabaseCoding.decoder.decode(LessonRow.self, from: Data(json.utf8)).domain(prerequisites: [])
        #expect(lesson.weekStartsOn == "2026-10-18" && lesson.weekEndsOn == "2026-10-23")

        let data = try JSONEncoder().encode(LessonWrite(draft: LessonDraft(lesson: lesson)))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["week_starts_on"] as? String == "2026-10-18")
        #expect(object["week_ends_on"] as? String == "2026-10-23")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let day = try #require(CalendarDay.date(from: "2026-10-18", calendar: calendar))
        #expect(CalendarDay.string(from: day, calendar: calendar) == "2026-10-18")
        #expect(CalendarDay.date(from: "2026-02-30", calendar: calendar) == nil)
    }

    @Test func decodesProgressAndSubscriptionRows() throws {
        let progress = try SupabaseCoding.decoder.decode(ProgressRow.self, from: Data("""
        {"lesson_id":"00000000-0000-4000-8000-0000000001a1","status":"in_progress","completed_exercises":3,
         "notes":"","last_activity_at":"2026-10-22T10:00:00+00:00","completed_at":null,
         "client_modified_at":"2026-10-22T10:00:00.001+00:00","user_id":"11111111-1111-4111-8111-111111111111"}
        """.utf8))
        #expect(progress.domain.status == .inProgress)
        #expect(progress.domain.completedExercises == 3)

        let sub = try SupabaseCoding.decoder.decode(SubscriptionRow.self, from: Data("""
        {"lesson_id":"00000000-0000-4000-8000-0000000001a3","is_active":false,
         "subscribed_at":"2026-10-20T10:00:00+00:00","unsubscribed_at":"2026-10-21T10:00:00+00:00"}
        """.utf8))
        #expect(sub.domain.isActive == false)
        #expect(sub.domain.unsubscribedAt != nil)
    }

    @Test func progressParametersNeverIncludeAUserID() throws {
        let progress = LessonProgress(lessonID: UUID(), status: .completed, completedExercises: 4, notes: "n",
                                      clientModifiedAt: Date(timeIntervalSince1970: 1_792_670_400.5))
        let data = try JSONEncoder().encode(SetProgressParams(progress))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["p_lesson_id", "p_status", "p_completed_exercises", "p_notes", "p_client_modified_at"])
        #expect(object["p_status"] as? String == "completed")
        #expect((object["p_client_modified_at"] as? String)?.hasSuffix(".500Z") == true)
    }

    @Test func lessonWritesNeverIncludeServerControlledColumns() throws {
        let draft = LessonDraft(courseID: UUID(), title: "  Graphs ", category: .optional, week: nil, moduleTitle: " ",
                                dueAt: nil, exerciseCount: 3)
        let data = try JSONEncoder().encode(LessonWrite(draft: draft))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for column in ["status", "created_by", "published_at", "archived_at", "created_at", "updated_at"] {
            #expect(object[column] == nil, "\(column) is set by the server")
        }
        #expect(object["title"] as? String == "Graphs")
        #expect(object["week"] is NSNull, "cleared optionals are sent as null")
        #expect(object["module_title"] is NSNull)
    }
}

@Suite("Configuration")
struct ConfigurationTests {
    @Test func acceptsAProjectURLAndPublishableKey() {
        let result = SupabaseConfiguration.fromInfoDictionary([
            "SUPABASE_URL": "https://abcdefghijklmnop.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_abc123",
        ])
        #expect((try? result.get())?.url.host == "abcdefghijklmnop.supabase.co")
    }

    @Test func missingOrPlaceholderValuesMeanNotConfigured() {
        #expect(SupabaseConfiguration.fromInfoDictionary([:]) == .failure(.missing))
        #expect(SupabaseConfiguration.fromInfoDictionary(["SUPABASE_URL": "$(SUPABASE_URL)", "SUPABASE_PUBLISHABLE_KEY": "$(KEY)"]) == .failure(.missing))
        #expect(SupabaseConfiguration.fromInfoDictionary([
            "SUPABASE_URL": "https://your-project.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "YOUR_PUBLISHABLE_KEY",
        ]) == .failure(.placeholder))
    }

    @Test func refusesToRunWithASecretKey() {
        #expect(SupabaseConfiguration.fromInfoDictionary([
            "SUPABASE_URL": "https://abcdefghijklmnop.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "sb_secret_abc",
        ]) == .failure(.secretKeyInClient))
        // Legacy service_role JWT (synthetic, unsigned).
        let payload = Data(#"{"role":"service_role","iss":"supabase"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(SupabaseConfiguration.isSecretKey("eyJhbGciOiJIUzI1NiJ9.\(payload).sig"))
        let anon = Data(#"{"role":"anon"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        #expect(!SupabaseConfiguration.isSecretKey("eyJhbGciOiJIUzI1NiJ9.\(anon).sig"))
    }

    @Test func plainHTTPOnlyForLocalDevelopment() {
        #expect((try? SupabaseConfiguration(url: URL(string: "http://127.0.0.1:54321")!, publishableKey: "sb_publishable_x")) != nil)
        #expect((try? SupabaseConfiguration(url: URL(string: "http://evil.example.org")!, publishableKey: "sb_publishable_x")) == nil)
    }
}

@Suite("Error mapping")
struct ErrorMappingTests {
    @Test func networkErrorsMeanOffline() {
        #expect(ErrorMapping.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(ErrorMapping.map(URLError(.timedOut)) == .offline)
    }

    @Test func databaseErrorsAreClassified() {
        #expect(ErrorMapping.map(PostgrestError(code: "42501", message: "new row violates row-level security policy")) ==
                .forbidden("new row violates row-level security policy"))
        #expect(ErrorMapping.map(PostgrestError(code: "23514", message: "check")) == .rejected("check"))
        #expect(ErrorMapping.map(PostgrestError(code: "PGRST303", message: "JWT expired")) == .unauthorized)
        #expect(ErrorMapping.map(PostgrestError(code: "28000", message: "Sign in required")) == .unauthorized)
        #expect(ErrorMapping.map(PostgrestError(code: "PGRST116", message: "0 rows")) == .notFound)
    }

    @Test func storageAndHTTPStatuses() {
        #expect(ErrorMapping.map(httpStatus: 401, message: "") == .unauthorized)
        #expect(ErrorMapping.map(httpStatus: 404, message: "") == .notFound)
        #expect(ErrorMapping.map(httpStatus: 400, message: "new row violates row-level security policy") ==
                .forbidden("new row violates row-level security policy"))
        #expect(ErrorMapping.map(httpStatus: 413, message: "Payload too large") == .rejected("Payload too large"))
        #expect(ErrorMapping.map(httpStatus: 503, message: "down") == .server("down"))
        #expect(ErrorMapping.map(httpStatus: 503, message: "down").isTransient)
    }
}
