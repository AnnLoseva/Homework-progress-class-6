# Homework Progress

A native iPhone and iPad homework tracker for five HIT computer-science courses, organised by
academic week. It runs offline and stores everything locally. There is no backend, account,
analytics or subscription.

## What it does

- **Weeks** are the unit of work. Each week owns its own assignments and progress. You can
  create a week, or copy another week's structure with fresh progress. You can edit names and
  dates, step back and forward between weeks, and browse all weeks by current, upcoming and past.
- **Five seeded courses** keep their original Hebrew names and HIT Moodle links. Each has a
  colour, an icon and an optional Notability notebook. The courses are seeded once, on first
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
- **Notability:** the share-sheet handoff, plus a per-course notebook name and optional link.
  See [docs/NOTABILITY.md](docs/NOTABILITY.md) for what Notability does and doesn't allow.
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

## Project layout

```
Homework progress/
  Models/      SwiftData models (Course, AcademicWeek, HomeworkAssignment,
               HomeworkAttachment, NotabilityNotebookAssociation) + versioned schema
  Domain/      Pure logic: progress math & count rules, week dates, filename/bidi helpers
  Services/    HomeworkStore (all multi-step mutations), AttachmentFileStore (PDF files),
               NotabilityIntegration, BackupService, ReminderScheduler, CourseSeeder
  Views/       SwiftUI screens: Dashboard, Course, Assignment, Week, Settings, Components
Config/Info.plist   PDF document type (merged with the generated Info.plist)
docs/               Notability findings, backup format
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

## Build & test

Requirements: Xcode 26 or later. Deployment target: iOS/iPadOS 17.

Run the unit tests (52 Swift Testing tests):

```bash
xcodebuild test -project "Homework progress.xcodeproj" -scheme "Homework progress" -only-testing:"Homework progressTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Run the UI flow test on iPhone and iPad:

```bash
xcodebuild test -project "Homework progress.xcodeproj" -scheme "Homework progress" -only-testing:"Homework progressUITests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)'
```

Launch arguments:

- `-uiTesting` uses an in-memory store.
- `-demoData` (DEBUG builds only) fills an in-memory store with an example week. Your real
  data is not touched.

## Localization

The UI strings are in `Localizable.xcstrings` (English source). To add Russian or Hebrew,
add the language in the project's Localizations and translate the catalog. Course names are
user data and are shown exactly as stored. Hebrew renders right-to-left automatically, and
`BidiText.isolate` keeps it from scrambling punctuation in mixed sentences.

## Known limitations

- Notability can't be told which notebook to open or where to import, so that last step is
  manual. Details in docs/NOTABILITY.md.
- The share sheet can't confirm that Notability finished importing. The app says so instead of
  claiming success.
- PDFs are not parsed: you enter exercise counts by hand, as specified.
- The PDF viewer is read-only. Handwriting belongs in Notability.
