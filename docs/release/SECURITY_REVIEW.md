# Security & privacy review — first TestFlight beta (1.0)

Reviewed 2026-10-23 against `feature/homework-tracker`. The standing security model and
contributor rules are in [SECURITY.md](../../SECURITY.md); this file records what was checked
for this release and what's left.

## Verdict

No release-blocking security issue found. The database is the security boundary and its rules
are covered by tests that pass. Remaining items are operational (who owns the backend, class
code, policy text), not code.

## What was checked and how

| Area | Result | Evidence |
|---|---|---|
| RLS on every `public` table | PASS | Hosted project: 0 tables without RLS (`pg_tables` query); `01_schema_security.sql` |
| Student isolation (progress, notes, subscriptions, profile, enrollment) | PASS | `02_student_isolation.sql`, owner-only policies in `20261022120100_rls.sql`; admins have no policy on personal tables |
| Admin self-promotion | PASS | `administrator_roles` has no client write grant/policy; `private.grant_admin` executable by `service_role` only; `03_roles_and_admin.sql` |
| Lesson visibility (drafts hidden, published readable) | PASS | `lessons: read visible or admin`; `04_catalog_visibility.sql` |
| Only admins write courses / lessons / attachments / lesson files | PASS | Admin-only insert/update/delete policies; storage write policies check `is_admin()` and the object name; `03`, `07` |
| PDFs (Storage) | PASS | Both buckets private; reads require the matching current attachment row, published lesson, and class enrollment for restricted files; `07_storage_access.sql` |
| Unsubscribing keeps progress | PASS | No DELETE grant on subscriptions/progress; `set_lesson_subscription` flips a flag; `05_subscriptions_workload.sql` + StudyKit `subscribeAndUnsubscribeOptionalLessonKeepsProgress` |
| Account deletion | PASS (DB) / NOT VERIFIED (end to end) | Cascades tested in `09_account_lifecycle.sql`; Edge Function `delete-account` v1 is deployed and active; a real deletion through the app wasn't run |
| Switching accounts on one device | PASS | Cache is keyed by user id; sign-out clears it; new test `switchingAccountsOnOneDeviceNeverShowsOrSendsThePreviousStudentsData` |
| Secrets in the app / repo | PASS | Archive contains an `sb_publishable_…` key and an `https://` URL only; `scripts/secret-scan.py` passes on tracked files and full history; `Config/Local.xcconfig` is git-ignored and untracked |
| Secret key guard | PASS | The app refuses `sb_secret_`/`service_role` keys at runtime (`SupabaseConfiguration`); archives now also refuse them at build time (`scripts/check-release-config.sh`) |
| TLS | PASS | Archives require `https://`; ATS only allows local networking (for `supabase start`), which doesn't apply to the hosted project |
| Logging of private data | PASS (fixed) | The only `print` (SwiftData save errors, which can quote record values) now uses `Logger` with `privacy: .private` |
| Privacy manifest | PASS (fixed) | Added the missing File Timestamp reason `C617.1` (the app reads sizes/dates of its own PDF copies). UserDefaults `CA92.1` was already there. swift-crypto ships its own manifest |
| Supabase security advisor | Expected warnings only | 3× "SECURITY DEFINER callable by authenticated" (`join_class`, `set_class_join_code`, `class_join_code_updated_at`) — intentional and documented in SECURITY.md; 1× leaked-password protection — irrelevant while the Email provider is off |

Test runs: database 179/179 assertions (9 suites) + 5 Edge Function tests, StudyKit
`swift test`, ClassroomUI 9/9, app unit tests 87/87, UI flow on iPhone and iPad.

## Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | Medium | **The beta's backend is the Supabase project you set up as your development project** (the one in `Config/Local.xcconfig`). Once classmates sign in it holds real student data. | ⚠️ Decide: keep it and treat it as production (no destructive experiments, no test data resets), or create a separate production project, run `npx supabase db push` + deploy `delete-account` there, and point `Config/Local.xcconfig` at it before archiving. |
| 2 | Medium (functional) | **No class code is set on the hosted project, and all 12 PDFs there are *restricted*.** Testers would see the 12 published lessons but could open none of their PDFs. | ⚠️ Set a code (Class → Manage lessons → Class code) before inviting testers. Give Beta App Review a code you can rotate afterwards. |
| 3 | Low | Published lesson titles and metadata (not restricted PDFs) are readable with only the publishable key (role `anon`), i.e. by anyone who extracts it from the app. | By design (SECURITY.md). Fine unless lesson titles themselves are confidential. |
| 4 | Low | Sign in with Apple token revocation on account deletion needs the four `APPLE_*` function secrets; whether they're set wasn't verified. Without them deletion still works, Apple's link just isn't revoked. | ⚠️ Optional: `npx supabase secrets list` |
| 5 | Info | Hosted Auth settings (Apple provider client IDs, Email/anonymous sign-ins off) can't be read from the database. The one existing account signed in with Apple, so the Apple provider works. | ⚠️ Check Email and anonymous sign-ins are off: Authentication → Sign In / Providers |
| 6 | Info | Privacy policy is still a template with bracketed placeholders. | ⚠️ Fill in and publish (needed for external testing) |

## Data the beta collects (for the privacy label)

Linked to the user, not used for tracking, for app functionality only: Supabase **user ID**;
**other user content** (lesson progress, exercise counts, private notes, subscriptions).
Not collected: homework (on device + user's own iCloud), analytics, crash data, location,
contacts, ad identifiers. Email: the app requests none and the hosted project currently stores
none (0 of 1 accounts); re-check after the first testers join.
