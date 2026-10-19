//
//  MoodleTests.swift
//  Homework progressTests
//

import Foundation
import Testing
@testable import Homework_progress

@Suite("Moodle app links")
struct MoodleTests {
    let hitCourse = URL(string: "https://md.hit.ac.il/course/view.php?id=27796")!

    @Test func hitCourseLinkMatchesDocumentedFormat() {
        let link = MoodleIntegration.appLink(for: hitCourse)
        #expect(link?.absoluteString ==
                "moodlemobile://https://md.hit.ac.il?redirect=https://md.hit.ac.il/course/view.php?id=27796")
    }

    @Test func everySeededCourseGetsAnAppLink() {
        for seed in CourseSeeder.defaults {
            let page = URL(string: seed.url)!
            let link = MoodleIntegration.appLink(for: page)?.absoluteString
            #expect(link == "moodlemobile://https://md.hit.ac.il?redirect=\(seed.url)")
        }
    }

    @Test func subdirectoryInstallKeepsItsPath() {
        let page = URL(string: "https://example.edu/moodle/course/view.php?id=5")!
        #expect(MoodleIntegration.siteURL(for: page)?.absoluteString == "https://example.edu/moodle")
    }

    @Test func customSchemeForBrandedApps() {
        let link = MoodleIntegration.appLink(for: hitCourse, scheme: " HITMoodle:// ")
        #expect(link?.absoluteString.hasPrefix("hitmoodle://https://md.hit.ac.il?redirect=") == true)
    }

    @Test func invalidSchemesAreRejected() {
        #expect(MoodleIntegration.validatedScheme("https") == nil)
        #expect(MoodleIntegration.validatedScheme("javascript") == nil)
        #expect(MoodleIntegration.validatedScheme("1abc") == nil)
        #expect(MoodleIntegration.validatedScheme("bad scheme") == nil)
        #expect(MoodleIntegration.validatedScheme("") == nil)
        #expect(MoodleIntegration.validatedScheme("moodlemobile") == "moodlemobile")
    }

    @Test func nonWebPagesGetNoAppLink() {
        #expect(MoodleIntegration.appLink(for: URL(string: "file:///tmp/x.pdf")!) == nil)
    }

    @Test func opensInAppWhenAccepted() async {
        var opened: [String] = []
        let outcome = await MoodleIntegration.open(hitCourse, preferApp: true, scheme: "moodlemobile") { url in
            opened.append(url.absoluteString)
            return true
        }
        #expect(outcome == .openedInApp)
        #expect(opened.count == 1)
        #expect(opened.first?.hasPrefix("moodlemobile://") == true)
    }

    @Test func fallsBackToBrowserWhenAppMissing() async {
        var opened: [String] = []
        let outcome = await MoodleIntegration.open(hitCourse, preferApp: true, scheme: "moodlemobile") { url in
            opened.append(url.absoluteString)
            return url.scheme == "https"
        }
        #expect(outcome == .openedInBrowser(appUnavailable: true))
        #expect(opened.last == hitCourse.absoluteString)
    }

    @Test func browserPreferenceSkipsTheApp() async {
        var opened: [URL] = []
        let outcome = await MoodleIntegration.open(hitCourse, preferApp: false, scheme: "moodlemobile") { url in
            opened.append(url)
            return true
        }
        #expect(outcome == .openedInBrowser(appUnavailable: false))
        #expect(opened == [hitCourse])
    }

    @Test func invalidSchemeSettingFallsBackToDefault() async {
        var first: URL?
        _ = await MoodleIntegration.open(hitCourse, preferApp: true, scheme: "not valid") { url in
            if first == nil { first = url }
            return true
        }
        #expect(first?.scheme == "moodlemobile")
    }
}
