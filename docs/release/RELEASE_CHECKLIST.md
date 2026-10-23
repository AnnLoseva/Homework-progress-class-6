# Release checklist — 1.0 first TestFlight beta

**PASS** verified · **FAIL** confirmed problem · **BLOCKED** needs you or an account ·
**NOT VERIFIED** not checked. Last run 2026-10-23 on Xcode 27.0 (27A266a), iOS SDK 27.0.

Re-run the automated part with `scripts/testflight.sh check`.

## Blocking before external testers

| # | Item | Status | Evidence / action |
|---|---|---|---|
| 1 | Class code set on the hosted project | **BLOCKED** | All 12 PDFs are *restricted* and no code exists, so testers can't open any PDF. Class → Manage lessons → Class code |
| 2 | CloudKit schema deployed to Production | **BLOCKED** | TestFlight builds use CloudKit Production (confirmed in the exported entitlements). CloudKit Console → Deploy Schema Changes |
| 3 | App Store Connect app record | **BLOCKED** | Not checked (no App Store Connect access from here). Create it — guide step 1.2 |
| 4 | Privacy policy published + URL | **BLOCKED** | `PRIVACY.md` is a template |
| 5 | Decide that the project in `Config/Local.xcconfig` is the class's production backend | **BLOCKED** | See SECURITY_REVIEW finding 1 |
| 6 | Upload, Beta App Review, public link | **BLOCKED** | Your Apple account; see TESTFLIGHT_UPLOAD_GUIDE |

## Build and signing

| Item | Status | Evidence |
|---|---|---|
| Native SwiftUI app, iPhone + iPad, iOS 17.0+ | PASS | `TARGETED_DEVICE_FAMILY = 1,2`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0` |
| Bundle ID / team consistent | PASS | `AnnaLoseva.Homework-progress`, `K36SNFAJDS` in all configs, archive and profile |
| Version / build | PASS | 1.0 / build from `--build` or commit count (archive made as 11) |
| Release build, generic iOS | PASS | `xcodebuild build -configuration Release -destination generic/platform=iOS` succeeded, no warnings from project code |
| Signed archive | PASS | `build/HomeworkProgress-1.0-11.xcarchive` |
| App Store export (no upload) | PASS | `build/export-11/Homework progress.ipa`: Apple Distribution cert, App Store profile, `aps-environment=production`, `get-task-allow=false`, `codesign --verify --deep --strict` OK |
| App Store Connect validation | NOT VERIFIED | Needs an App Store Connect record; use Organizer → Validate App, or the upload itself validates |
| Archive refuses bad backend config | PASS | Archive with empty `SUPABASE_URL` fails with a clear error; script tested with HTTP, placeholder, `sb_secret_`, `service_role` JWT |
| Release points at the hosted backend | PASS | Archive Info.plist: the hosted `https://<ref>.supabase.co` URL from `Config/Local.xcconfig` and an `sb_publishable_…` key |
| Export compliance | PASS | `ITSAppUsesNonExemptEncryption = NO` |

## Assets, Info.plist, capabilities

| Item | Status | Evidence |
|---|---|---|
| App icon 1024 px, no alpha, light/dark/tinted slots | PASS | `sips`: 1024×1024 RGB, `hasAlpha: no`; compiled into `Assets.car` |
| Dark / tinted icon variants differ from light | NOT VERIFIED | All three files are identical; acceptable, but iOS will tint the light artwork |
| Home-screen name | ⚠️ | "Homework progress" (from target name) is truncated on the home screen; optional rename in RELEASE_METADATA |
| Launch screen | PASS | Generated (`UILaunchScreen_Generation`); the app shows a storage-error screen instead of crashing |
| Orientations | PASS | iPad all four (multitasking), iPhone portrait + landscape |
| Permission strings | PASS | Only local notifications are requested (no usage string needed); no camera/photos/location/contacts APIs |
| Entitlements match features | PASS | Sign in with Apple (Class tab), CloudKit + KVS (sync), push (CloudKit silent pushes), `remote-notification` background mode for the same |
| Privacy manifest | PASS (fixed) | Added File Timestamp `C617.1`; UserDefaults `CA92.1`; data types UserID + OtherUserContent |
| Fonts and resources bundled | PASS | Lora fonts listed in `UIAppFonts`; build succeeded with all asset references |

## Tests

| Suite | Status | Result |
|---|---|---|
| Secret scan (tracked files + history) | PASS | passed |
| Database security / RLS (PGlite) | PASS | 179 assertions, 9 suites, 0 failed |
| Edge Function (`delete-account` Apple revocation) | PASS | 5/5 |
| StudyKit (domain, offline sync, Supabase mapping) | PASS | `swift test` all passed, incl. new account-switching test |
| ClassroomUI | PASS | 9/9 |
| App unit tests | PASS | 87/87 on iPhone 17 Pro, iOS 26.5 simulator |
| UI flow (create week → assignment → progress) | PASS | iPhone 17 Pro + iPad Air 11" (M4), iOS 26.5 |
| Hosted Supabase: migrations, RLS, advisors | PASS | 5/5 migrations applied, 0 tables without RLS, only the documented advisor warnings |
| On a real device / iOS 17 / iOS 27 | NOT VERIFIED | Simulators only (iOS 26.5). Install the TestFlight build on your own iPhone and iPad first |
| Sign in with Apple, PDF download, account deletion end to end | NOT VERIFIED | Needs a real device + Apple ID; covered by fakes and SQL tests only |
| iCloud sync on TestFlight (Production) | NOT VERIFIED | Needs item 2 and two devices |
| Dynamic Type / VoiceOver pass | NOT VERIFIED | Fonts scale (`relativeTo:`) and icon-only buttons have labels; no full audit was run |
