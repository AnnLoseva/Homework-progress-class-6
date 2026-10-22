# Architecture

Woodland Study Tracker has three areas, kept apart in code and in the database:

| Area | What it is | Where it lives |
|---|---|---|
| **Student app** | Browse lessons, subscribe, open PDFs, track personal progress | `WoodlandStudy/Features/Student`, `StudyDomain`, `StudyData` |
| **Content management** | The administrator creates, edits, publishes and archives lessons and PDFs | `WoodlandStudy/Features/Admin`, admin RLS policies |
| **Backend** | Auth, access control, storage, sync | `supabase/` (migrations, RLS, storage policies, Edge Function) |

```
┌────────────────────────── iOS / iPadOS app (SwiftUI) ──────────────────────────┐
│  Features/Auth      Features/Student            Features/Admin                  │
│  (Sign in with      Home · Catalog · Lesson ·   Lessons · Editor · Attachments  │
│   Apple)            My Lessons · Settings       · Courses · Class code          │
│        │                     │                           │                      │
│        └──────────── AppModel (session state, DI) ───────┘                      │
├──────────────────────────────── StudyKit (Swift package) ──────────────────────┤
│  StudyDomain   pure models + rules: Workload, ProgressRules, LessonQuery         │
│  StudyData     protocols (AuthService, StudyBackend), OfflineStore, Outbox,      │
│                SyncEngine, PDF cache, InMemoryBackend (demo + tests)             │
│  StudySupabase SupabaseAuthService, SupabaseStudyBackend (supabase-swift SDK)    │
└──────────────────────────────────────┬──────────────────────────────────────────┘
                                       │ HTTPS · publishable key + user JWT
┌──────────────────────────────────────┴───────────── Supabase ──────────────────┐
│  Auth (Sign in with Apple)   Postgres + RLS on every table   Storage (private)   │
│  Edge Function: delete-account (service role lives only here)                    │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Principles

1. **The database is the security boundary.** Every check that matters runs in Postgres:
   RLS policies, `BEFORE` triggers that validate state, and `SECURITY DEFINER` functions
   for the few privileged operations. The app hides admin screens from students for
   convenience only.
2. **Never trust identity from the client.** No table accepts a `user_id` that differs
   from `auth.uid()`. Triggers overwrite `created_by` and `uploaded_by`, and the progress
   RPC never takes a user id at all.
3. **One source of truth.** Supabase owns subscriptions and progress. The device keeps a
   cache and an outbox of pending changes. It never syncs the same records through iCloud
   as well.
4. **Shared content is separate from personal data.** `courses`, `lessons`,
   `lesson_attachments` and `lesson_prerequisites` are shared. `profiles`,
   `lesson_subscriptions`, `lesson_progress` and `class_enrollments` are owned by one user.
5. **Content changes never destroy personal data.** Progress is keyed by
   `(user_id, lesson_id)` only. Editing, replacing a PDF, archiving, republishing or
   changing the category never deletes or resets it.

## Data model

```
auth.users ─┬─ profiles (1:1)
            ├─ administrator_roles (0..1)        ← granted only by trusted SQL
            ├─ class_enrollments (0..1)          ← created only by join_class(code)
            ├─ lesson_subscriptions (user, lesson)   active flag; never deleted on unsubscribe
            └─ lesson_progress (user, lesson)        status, counters, notes, timestamps

courses 1─* lessons 1─* lesson_attachments
             lessons *─* lessons  (lesson_prerequisites)
```

| Table | Purpose | Key constraints |
|---|---|---|
| `profiles` | Optional display name. No email or role is stored. | PK = `auth.users.id`, cascade delete |
| `administrator_roles` | Who is an administrator | No client write policy at all |
| `class_enrollments` | Who redeemed the class code. Required for restricted PDFs. | Written only by `join_class()` |
| `courses` | Subject, illustration and color | Unique `slug` |
| `lessons` | Title, description, category (`required`/`optional`), course, week, module, dates, duration, exercise count, status (`draft`/`published`/`archived`), order, author | Category `NOT NULL`. Publishing requires an active course. |
| `lesson_prerequisites` | Optional lesson → lesson references | No self-reference |
| `lesson_attachments` | Stable attachment id, title, description, visibility (`public`/`restricted`), storage path, MIME type, size, version | PDF only, max 50 MB, path must be `lesson/attachment/v<n>.pdf` |
| `lesson_subscriptions` | A student following an optional lesson | PK `(user_id, lesson_id)`: duplicates are impossible |
| `lesson_progress` | Status, completed exercise count, notes, last activity, completion time | PK `(user_id, lesson_id)`. Counts and status are validated by a trigger. |

Private tables (`private` schema, not exposed through the API) hold the class-code hash
and join attempts used for rate limiting.

### Workload rule

A student's **active workload** is:

* every **published required** lesson, plus
* every **published optional** lesson with an **active** subscription.

The same rule is implemented twice and tested in both places:
`public.my_workload` (a security-invoker view) on the server and `Workload` in
`StudyDomain` (used for offline display). Archived and draft lessons are never active
work. Archived lessons still appear in **History** with the student's progress.

### Category changes (documented behavior)

| Change | Subscriptions | Progress |
|---|---|---|
| optional → required | Kept as-is (ignored while required) | Untouched; the lesson enters everyone's workload |
| required → optional | Students with any progress get an active subscription automatically, so their work doesn't disappear. Others can subscribe. | Untouched |
| any edit / PDF replace / archive / republish | Untouched | Untouched |

### Progress rules

* `not_started` ⇒ `completed_exercises = 0`.
* `0 ≤ completed_exercises ≤ lessons.exercise_count`. Lessons without numbered exercises
  must stay at 0 and are completed manually.
* `completed` ⇔ `completed_at` is set. The trigger stamps it, and moving out of `completed`
  clears it.
* **Lesson completion** (status) and **exercise completion** (counter) are separate. A
  student may mark a lesson completed without ticking every exercise. The dashboard shows
  both numbers, labeled separately.
* Progress can only be created for published or archived lessons.
* Writes go through `set_lesson_progress(...)`, which always uses `auth.uid()` and is
  **last-writer-wins by client timestamp**. An offline change replayed late never
  overwrites a newer change from another device, and retries are idempotent.

### Dashboard math

* *Lesson completion* = completed lessons ÷ lessons in the workload.
* *Exercise completion* = Σ completed exercises ÷ Σ exercise counts across the workload.
  This is weighted by exercises, never an average of percentages, so a 2-exercise lesson
  doesn't count as much as a 20-exercise one.
* Unsubscribed optional lessons never count as remaining work.

## Security model

### Roles

| Capability | anon | student | admin |
|---|---|---|---|
| Read published or archived lessons, courses, attachment metadata | ✓ | ✓ | ✓ |
| Read drafts | – | – | ✓ |
| Download a **public** PDF of a published lesson | ✓ | ✓ | ✓ |
| Download a **restricted** PDF | – | enrolled only | ✓ |
| Own subscriptions, progress and notes | – | own rows only | own rows only |
| Other students' progress and notes | – | – | **– (no policy)** |
| Write lessons, courses, attachments, storage objects | – | – | ✓ |
| Grant roles | – | – | – (SQL editor or service role only) |

The administrator can't read any student's progress or notes. No feature needs it.
If one ever does (for example anonymous aggregate counts), it should be a separate,
documented `SECURITY DEFINER` function that returns aggregates only.

### Storage

| Bucket | Public? | Path | Who can read |
|---|---|---|---|
| `lesson-materials` | **private** | `<lesson_id>/<attachment_id>/v<version>.pdf` | Checked against the matching `lesson_attachments` row: public ⇒ anyone; restricted ⇒ enrolled students; drafts ⇒ admin only |
| `student-private` | **private** | `<user_id>/…` | The owner only. Reserved for future student uploads; the policies are already in place and tested. |

Files are fetched through short-lived signed URLs (5 minutes) or authenticated
downloads. A file name being hard to guess is never treated as authorization: the
storage policy joins the object name to the attachment row and checks the lesson's
status and visibility. Bucket limits enforce `application/pdf` and 50 MB, and the app
also checks the `%PDF-` header before upload.

### Privileged operations

| Operation | How |
|---|---|
| First administrator | `select private.grant_admin('<uuid>')` in the SQL editor (see README). The function can't be executed by `anon` or `authenticated`. |
| Set class join code | `set_class_join_code(code)`: `SECURITY DEFINER`, admin-checked, stores a salted SHA-256 hash only |
| Join class | `join_class(code)`: `SECURITY DEFINER`, at most 10 failed attempts per hour |
| Delete account | Edge Function `delete-account`. It verifies the JWT, removes the user's private files, optionally revokes the Sign in with Apple token, and then deletes the auth user. All personal rows cascade. |
| Export data | `export_my_data()`: security invoker, returns only the caller's rows as JSON |

## iOS app

* **SwiftUI, iOS/iPadOS 17+.** `NavigationSplitView` with a sidebar on iPad, `TabView`
  on iPhone.
* **Auth:** `AuthenticationServices` gets an Apple ID token with a SHA-256 nonce, and
  `supabase.auth.signInWithIdToken` exchanges it. The SDK keeps the session in the
  Keychain and restores and refreshes it on launch. On launch the app also checks the Apple
  credential state, so a revoked Apple ID signs the user out. The app never reads or stores
  an email address.
* **Offline:** `OfflineStore` keeps a per-user JSON snapshot (catalog, subscriptions,
  progress) in Application Support with complete file protection. Changes are applied
  optimistically and queued in a persistent **outbox**. `SyncEngine` flushes the outbox when
  the network returns, retries with backoff, and then pulls fresh state. Downloaded PDFs are
  cached by `attachment id + version`, so a replaced PDF is fetched again. Everything is
  wiped on sign-out and account deletion.
* **Recently opened** lessons are stored on the device only.
* **PDFs:** viewed with PDFKit and shared through `ShareLink` / `UIActivityViewController`.
  Notability shows up there as "Open in Notability". Notability has no public import API,
  so the standard share sheet is the supported path.
* **Demo mode:** without a Supabase configuration, or with `-demo`, the app runs on
  `InMemoryBackend` with synthetic data. It's used for previews, UI tests and classmates
  who just want to look around.
* **Accessibility:** Dynamic Type (Lora scales relative to body text), VoiceOver labels on
  rings, badges and counters, adaptive light and dark palettes, and right-to-left layout
  for Hebrew.

## Testing strategy

| Layer | Tool | What it proves |
|---|---|---|
| Database / RLS | `supabase/tests/*.sql` run by `tools/db-tests` (PGlite, i.e. real Postgres 17 in WebAssembly, with a minimal `auth`/`storage` shim) or against `supabase start` | Isolation between students, role escalation, draft visibility, storage access, category changes, idempotency |
| Domain | `swift test` (StudyDomainTests) | Workload, progress validation, dashboard math, filters |
| Data | `swift test` (StudyDataTests) | Outbox, retries, offline/reconnect, two-device sync, upload validation, auth state machine |
| Supabase mapping | `swift test` (StudySupabaseTests) | Row JSON ↔ domain mapping |
| UI | XCUITest in demo mode, iPhone and iPad | Core flows render and work |

A passing UI test is **not** evidence of backend security. Only the SQL suites are.
