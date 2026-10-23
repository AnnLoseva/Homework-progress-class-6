# Release metadata (draft)

Copy these into App Store Connect. **Everything marked ⚠️ needs your confirmation** — nothing
here has been submitted anywhere.

## Identity (from the Xcode project)

| Field | Value | Status |
|---|---|---|
| Bundle ID | `AnnaLoseva.Homework-progress` | In use by your development profile. Register it as an explicit App ID if App Store Connect doesn't list it. |
| Team | `K36SNFAJDS` (Anna Loseva) | From the project settings |
| Version | `1.0` | First release |
| Build | `scripts/testflight.sh` uses the commit count on `HEAD`; Xcode Organizer can manage it for you | Must increase with every upload of 1.0 |
| Home-screen name | "Homework progress" (from the target name) | ⚠️ Gets truncated on the home screen ("Homework prog…"). Consider a shorter display name such as "Homework" (target → General → Display Name). |
| Platforms | iPhone and iPad, iOS/iPadOS 17.0+ | |
| Primary language | English (Class tab also Hebrew) | |
| Category | Education | ⚠️ Suggested |
| Age rating | 4+ (no objectionable content; no unrestricted web access; user-generated content is private) | ⚠️ Answer the questionnaire yourself |

## App name (App Store Connect "Name", 30 characters max)

- Suggested: **Homework Progress** ⚠️ (the name must be unique on the App Store; pick an
  alternative such as "Homework Progress – HIT" if it's taken)
- Subtitle (30 max): **Weekly homework, tracked** ⚠️

## Short description / promotional text

> Track every week's homework by course and exercise, keep the PDFs beside your progress, and
> follow your class's shared lessons — privately, on iPhone and iPad.

## Beta App Description (TestFlight → Test Information)

> Homework Progress is a cozy homework tracker for our HIT computer-science courses.
>
> **Homework**: create a week, add assignments with PDFs and exercise counts, and watch your
> weekly progress. Everything stays on your device and in your own iCloud; it syncs between
> your iPhone and iPad.
>
> **Class**: sign in with Apple to see the lessons our class administrator publishes, follow
> the optional ones you want, open their PDFs (also offline) and track your own progress. Nobody
> else — including the administrator — can see your progress or notes.

## What to Test (TestFlight "What to Test", per build)

> Thanks for testing! Please try:
> 1. First launch: the five courses appear, the dashboard is empty and friendly.
> 2. Create a week, add an assignment with a PDF (from Files or Safari → Share → Homework
>    progress), and tap "Exercise Done" a few times.
> 3. If you have an iPhone and an iPad on the same Apple ID: check your homework appears on both.
> 4. Class tab: Sign in with Apple, enter the class code you received, follow an optional
>    lesson, open its PDF, mark exercises done. Unfollow it and follow it again — your progress
>    should still be there.
> 5. Turn on Airplane Mode, change progress in the Class tab, turn it off again — it should sync.
> 6. Class → Class Account → Export my data, then (only if you want to) Delete account and data.
>
> Report problems with a screenshot via TestFlight (take a screenshot → Share Beta Feedback).

## Known limitations (for testers)

- Notability and Goodnotes can't be told which notebook to open; importing a PDF there is a manual last step.
- PDFs aren't parsed — enter exercise counts by hand.
- Homework progress and Class lesson progress are separate; finishing one doesn't finish the other.
- The homework screens are English-only; the Class tab is English and Hebrew.
- The app always uses its light parchment look (no dark mode).

## Contact / support ⚠️

| Field | Value |
|---|---|
| Beta feedback email (required for TestFlight) | ⚠️ `[your email]` |
| Support URL (required for the App Store, not for TestFlight) | ⚠️ `[URL]` — e.g. the GitHub repository's Issues page once it's public |
| Marketing URL (optional) | ⚠️ leave empty |
| Privacy policy URL (required for external TestFlight testing and the App Store) | ⚠️ `[URL]` — publish a filled-in copy of [PRIVACY.md](../../PRIVACY.md) (e.g. as a GitHub Pages page or a public Notion page) |
| Sign-in information for Beta App Review | Sign in with Apple needs no demo account. ⚠️ Give the reviewer the class code (or a separate, rotatable review code) in "Notes", and say that the homework part works without signing in. |

## App Privacy ("nutrition label") — answers to confirm ⚠️

Based on the code and `PrivacyInfo.xcprivacy`:

| Data type | Collected? | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| User ID (Supabase account id from Sign in with Apple) | Yes | Yes | No | App Functionality |
| Other User Content (lesson progress, exercise counts, private notes) | Yes | Yes | No | App Functionality |
| Email address | Not collected today: the app requests **no** email scope and the hosted project stores none (checked 2026-10-23, 1 account). ⚠️ Re-check after testers join; if any account shows an email, declare "Email Address — App Functionality, linked". |
| Homework (weeks, assignments, PDFs) | **Not collected**: stays on device and in the user's own private iCloud database, which you can't access |
| Crash data, analytics, location, contacts, identifiers for ads | Not collected (no SDKs for these) |

Other answers: **no tracking**; no third-party advertising; data is not sold. Supabase (EU,
Frankfurt) and Apple process data on your behalf — say so in the privacy policy.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is already in `Config/Info.plist`: the app only uses
HTTPS/TLS and Apple's system crypto (plus swift-crypto inside the Supabase SDK for sign-in
hashing), which is exempt. App Store Connect therefore won't ask on each build. ⚠️ Confirm
you're not adding any other encryption.

## App Store description (for later — not needed for TestFlight)

> **Homework Progress** keeps your week under control.
>
> • **Weeks first.** Every week has its own assignments and progress. Copy last week's
>   structure with fresh progress in one tap.
> • **Real progress.** Progress is weighted by exercises, not averaged — and assignments
>   without a count still show up.
> • **PDFs beside your work.** Import from Files, Safari or Moodle, preview them, and send
>   them to Notability or Goodnotes.
> • **iPhone and iPad.** Syncs through your own private iCloud. Works offline. iPad gets a
>   sidebar, a side panel and keyboard shortcuts.
> • **Class lessons.** Sign in with Apple to follow the lessons your class shares, with
>   required and optional lessons, offline PDFs and private progress.
> • **Private by design.** No ads, no analytics, no tracking. Export or delete your class
>   data any time.
>
> Made with cozy forest illustrations and gentle mushroom friends who never guilt you for
> unfinished work.

## Screenshots

Not needed for TestFlight. For the App Store you'll need at least one set for **6.9" iPhone**
(1320 × 2868) and **13" iPad** (2064 × 2752). None have been made; take them from the
simulator (⌘S) with real-looking but made-up homework, never real student data.
