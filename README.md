# Homework Progress

A native iPhone and iPad app for five HIT computer-science courses, with two parts:

- **Homework** — your personal tracker, organised by academic week. It works offline and syncs
  between your own iPhone and iPad through your private iCloud. No account, analytics or
  subscription.
- **Class** — lessons and PDFs the class administrator publishes. Each student signs in with
  Apple, follows the lessons they need and tracks their own progress privately. The
  administrator can turn their homework into class lessons in one step (*Publish Homework to
  Class*). Backend: Supabase with Row Level Security on every table.

The two parts keep separate data: homework stays in SwiftData + iCloud, class lessons and
lesson progress live in Supabase. The one bridge is *Subscribe to class* (below), which copies
lessons into your weeks and keeps their progress in step. The app ships with no sample content.

Architecture, data model and security model: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

## Homework: what it does

- **Weeks** are the unit of work. Each week owns its own assignments and progress. You can
  create a week, or copy another week's structure with fresh progress. You can edit names and
  dates, step back and forward between weeks, and browse all weeks by current, upcoming and past.
- **Five seeded courses** keep their original Hebrew names and HIT Moodle links. Each has a
  colour, an icon and an optional Notability or Goodnotes notebook. The courses are seeded once, on first
  launch only, and are never re-inserted after you delete them.
- **Assignments** have a course, a week, an optional due date, an optional exercise total,
  a completed count, a status, notes and one or more PDFs.
- **Dashboard** shows:
  - weekly progress weighted by exercises: `Σ completed / Σ total`, never an average of
    percentages;
  - remaining exercises and finished/open assignment counts;
  - per-course rows;
  - a "Remaining Work" list you can sort by due date, course, most remaining or recently updated.
- **PDFs** are copied into app storage with file coordination, so iCloud files download first.
  They are previewed with PDFKit and can be opened, replaced or removed. Removing a PDF never
  touches the assignment's progress.
- **Moodle app:** the course buttons, and the "Moodle" chip on each assignment, open the course
  directly in the Moodle app. They use the app's documented deep link
  `moodlemobile://https://md.hit.ac.il?redirect=<course page>` (see Moodle Developer Resources →
  Deep linking). If the app isn't installed, the page opens in Safari. In Settings you can switch
  to the browser or set a branded app's link scheme.
- **iPhone ↔ iPad sync** through your private iCloud (SwiftData + CloudKit, container
  `iCloud.AnnaLoseva.Homework-progress`). It syncs weeks, assignments, progress, notes, course
  settings and PDFs. PDFs are stored as iCloud assets, and each device keeps a local copy for
  PDFKit and the share sheet. The app still works fully offline. If iCloud is unavailable, data
  stays on the device and nothing is deleted. After sync, housekeeping merges courses seeded on
  both devices and duplicate records, without losing any data. The Settings screen shows the sync
  status. Device-specific preferences (reminders, sort order, Moodle option) are not synced.
- **Notability or Goodnotes:** pick your notes app in *Settings → Notes App* (Notability by
  default, saved per device). Then use the share-sheet handoff, plus a per-course notebook
  name and optional link. See [docs/NOTABILITY.md](docs/NOTABILITY.md) for what both apps do
  and don't allow.
- **iPad** gets a sidebar for weeks and courses and a side panel for the selected assignment.
  The full-width assignment workspace puts the PDF beside the counters. Keyboard shortcuts:
  ⌘N new assignment, ⇧⌘N new week, ⌘[ / ⌘] previous/next week, ⌘= / ⌘− exercise done/undone,
  ⌘O open PDF, ⌘E edit, Esc close panel.
- **Optional reminders** for deadlines and a weekly review. They are off by default and use
  local notifications only.
- **Backup:** one JSON file with all data and PDFs. Restore merges and never deletes. The format
  is in [docs/BACKUP_FORMAT.md](docs/BACKUP_FORMAT.md).
- **Receiving PDFs:** the app appears as a share target for PDFs (for example from Safari or
  Moodle). A shared PDF starts a new assignment in the selected week.

## Look & feel

The app shares Mood Pomodoro's cozy style:

- warm parchment cards with an inked border over a hand-drawn forest backdrop (iPhone and iPad
  versions);
- Lora serif type and forest-green and rust accents;
- an illustration for each course;
- mushroom friends who react to the week's progress, with no guilt for unfinished work.

The palette, fonts, card and button styles live in `Views/Components/Theme.swift`. Like Mood
Pomodoro, the app always uses the light parchment appearance.

## Class: what it does

- **Students:** a dashboard (what to study, what's required, what's done, what's left), a
  catalog with **Required (חובה)** and **Optional (רשות)** lessons, *My Lessons* for
  subscriptions, exercise counters, private notes, PDFs that work offline, and the share sheet
  to send them to Notability or Goodnotes. Hebrew and right-to-left layout are supported.
- **Subscribe to class** (Class Home, or *Settings → Class*): copies every published class
  lesson, required and optional, into your homework weeks: the week with the same number
  (or the one containing the due date, created if needed), the matching course, the exercise
  total and the PDFs. New and changed lessons follow automatically, and optional lessons are
  followed in Class too. **Progress is shared:** ticking exercises or finishing a copy in
  Homework updates the class lesson and the other way round (whichever side changed wins; if
  both did, the newer change). Your notes stay in Homework, a copy you delete isn't brought
  back, and turning the switch off keeps what was added. Restricted PDFs arrive once you've
  joined the class with its code.
- **Administrator:** create, edit, publish, unpublish and archive lessons; upload, preview and
  replace PDFs; manage courses; set the class join code. *Settings → Class → Publish Homework
  to Class* publishes chosen assignments as lessons: course, title, week, due date, exercise
  total and PDFs. Your completed counts, status and notes are never sent. Publishing again
  updates the same lessons (they reuse the assignment ids), and a changed PDF becomes a new
  version of the same attachment, so students keep their progress.
- **Security:** every rule is enforced in the database (RLS, triggers, `SECURITY DEFINER`
  functions) and covered by SQL tests. Students can't see each other's data; the
  administrator can't see students' progress or notes. Restricted PDFs need the class code.
- **Privacy:** no email or name requested, no trackers. Students can export or delete their
  class data at any time. Template: [PRIVACY.md](PRIVACY.md).

Where it appears: a **Class** tab on iPhone, and a **Class** section in the iPad sidebar.

## Project layout

```
Homework progress/
  Models/      SwiftData models (Course, AcademicWeek, HomeworkAssignment,
               HomeworkAttachment, NotabilityNotebookAssociation) + iCloud/local store setup
  Domain/      Pure logic: progress math & count rules, week dates, filename/bidi helpers
  Services/    HomeworkStore (all multi-step mutations), AttachmentFileStore (PDF files),
               NoteAppIntegration (Notability/Goodnotes), BackupService, ReminderScheduler, CourseSeeder
  Views/       SwiftUI screens: Dashboard, Course, Assignment, Week, Settings, Components
  Services/ClassPublisher.swift   homework → class lessons (administrator only)
Packages/ClassroomUI/   the Class tab: sign-in, catalog, lessons, My Lessons, admin screens
Packages/StudyKit/      below the Class UI: StudyDomain (rules), StudyData (offline cache,
                        outbox, sync), StudySupabase (supabase-swift)
supabase/               migrations (schema, RLS, storage, functions), the delete-account Edge
                        Function, SQL security tests + their made-up fixtures, empty seed.sql
tools/db-tests/         runs the SQL suites on PGlite (Postgres in WebAssembly) or a local DB
scripts/                secret scan, string catalog update, git hooks
Config/Info.plist       PDF document type, fonts, background push, Supabase keys from xcconfig
Config/Base.xcconfig    shared settings; your values go in Config/Local.xcconfig (git-ignored)
Config/HomeworkProgress.entitlements   iCloud (CloudKit + key-value), push, Sign in with Apple
docs/                   architecture, admin guide, distribution, assets, Notability/Goodnotes, backup format
```

### Invariants

- Every assignment has exactly one course and one week. `HomeworkStore.createAssignment` takes
  both.
- Deleting a week deletes only its own assignments and their PDF files. Deleting a course
  deletes its assignments (the app warns first).
- Copying a week creates new records with zero progress and no PDFs. The source week is never
  modified.
- Only a PDF's relative stored name (`<uuid>.pdf`) is persisted. Picker URLs are never stored.
  A missing file shows a "replace to fix" state instead of crashing.
- All progress math lives in `Domain/Progress.swift`:
  - an assignment with no total or a total of 0 is excluded from exercise sums (no division by
    zero) but still counts in assignment statistics;
  - when the total drops below the completed count, the user chooses whether to lower the
    completed count or keep it and flag the inconsistency.

## Setup

Requirements: Xcode 26 or later, iOS/iPadOS 17. For the Class tab and the SQL tests also
Node.js 20+ and a Supabase account (free tier is enough). Sign in with Apple and iCloud on
devices need a paid Apple Developer membership.

1. **Clone and open** `Homework progress.xcodeproj`. The homework tracker runs right away.
   Without a Supabase configuration the Class tab explains how to connect it.
2. **Your identifiers.** A classmate building their own copy changes the bundle identifier and
   team in the target settings, and the iCloud container (`iCloud.AnnaLoseva.Homework-progress`
   in `Config/HomeworkProgress.entitlements` and `Models/Schema.swift`) to their own.
3. **Supabase project.** Create a project just for this app (or run `npx supabase start`
   locally). Note the Project URL and the **Publishable** key. The secret / service-role key
   never goes in the app, this repository or chat.
4. **Database.** Apply the migrations:

   ```bash
   npx supabase link --project-ref <your-project-ref>
   ```

   ```bash
   npx supabase db push
   ```

   Then deploy the account-deletion function:

   ```bash
   npx supabase functions deploy delete-account --no-verify-jwt
   ```

   (Optional, so deleting an account also revokes Apple's authorization: put the four
   `APPLE_*` values from `.env.example` in `supabase/functions/.env` and run
   `npx supabase secrets set --env-file supabase/functions/.env`.)
5. **Sign in with Apple in Supabase.** Dashboard → Authentication → Sign In / Providers →
   **Apple**: enable it and put the app's bundle identifier (`AnnaLoseva.Homework-progress`, or
   yours) in **Client IDs**. Turn the Email provider off and keep anonymous sign-ins off.
6. **Configure the app:** copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig`
   (git-ignored) and fill in `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. If you paste a
   secret key by mistake, the app refuses to use it.
7. **First administrator.** Nobody can become an administrator from the app. Sign in on the
   Class tab once, copy your **User UID** from Dashboard → Authentication → Users, and run in
   the SQL Editor:

   ```sql
   select private.grant_admin('<your-user-uid>', 'Course instructor');
   ```

   Relaunch the app: *Manage lessons* appears in the Class tab, and *Publish Homework to
   Class* in Settings. Remove a role with `select private.revoke_admin('<uuid>');`.
8. **Publish.** Set a class code (Class → Manage lessons → Class code) and share it. Then
   either *Settings → Class → Publish Homework to Class*, or create lessons by hand in
   *Manage lessons*. Details: [docs/ADMIN_GUIDE.md](docs/ADMIN_GUIDE.md).

Release builds, TestFlight and what MIT means: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
Uploading a TestFlight beta step by step, with the release checklist, draft App Store
metadata and security review: [docs/release/](docs/release/TESTFLIGHT_UPLOAD_GUIDE.md)
(`scripts/testflight.sh check | archive | export | upload`).

## Tests

| What | Command |
|---|---|
| Homework + publishing (Swift Testing) | the first `xcodebuild` command below |
| UI flows on iPhone and iPad | the second `xcodebuild` command below |
| Class area wiring | `cd Packages/ClassroomUI && xcodebuild test -scheme ClassroomUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| Class rules, offline sync, Supabase mapping (101 tests) | `cd Packages/StudyKit && swift test` |
| Database security, RLS (179 assertions, no Docker) | `cd tools/db-tests && npm ci && npm test` |
| Secret scan | `python3 scripts/secret-scan.py` |

UI tests prove the screens work; they are **not** evidence of backend security. The SQL
suites are.

Run the app's unit tests:

```bash
xcodebuild test -project "Homework progress.xcodeproj" -scheme "Homework progress" -only-testing:"Homework progressTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Run the UI flow test on iPhone and iPad:

```bash
xcodebuild test -project "Homework progress.xcodeproj" -scheme "Homework progress" -only-testing:"Homework progressUITests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)'
```

Launch argument: `-uiTesting` uses an in-memory store and keeps the Class tab disconnected.
Your real data is never touched by tests.

## Localization

The UI strings are in `Localizable.xcstrings` (English source). The Class tab is also
translated into Hebrew: after adding strings, build once, run
`python3 scripts/update-string-catalog.py <derived-data-path>` and add the translations to
`scripts/localization/he.json`. The homework screens are English-only for now. Course names are
user data and are shown exactly as stored. Hebrew renders right-to-left automatically, and
`BidiText.isolate` keeps it from scrambling punctuation in mixed sentences.

## Known limitations

- Notability and Goodnotes can't be told which notebook to open or where to import, so that
  last step is manual. Details in docs/NOTABILITY.md.
- The share sheet can't confirm that the notes app finished importing. The app says so instead of
  claiming success.
- PDFs are not parsed: you enter exercise counts by hand, as specified.
- The PDF viewer is read-only. Handwriting belongs in Notability or Goodnotes.
- Without *Subscribe to class*, the Class tab's progress is separate from your homework
  progress: publishing alone doesn't link them.
- Sign in with Apple, the delete-account Edge Function and Storage signed URLs need a real
  Supabase project to test end to end; the SQL suites cover the database rules.

## License

Code: **MIT** ([LICENSE](LICENSE)). Lora font: SIL Open Font License 1.1. Illustrations: see
[docs/ASSETS.md](docs/ASSETS.md) — confirm their terms before making the repository public.
Contributing: [CONTRIBUTING.md](CONTRIBUTING.md) · Security: [SECURITY.md](SECURITY.md) ·
Privacy: [PRIVACY.md](PRIVACY.md)
