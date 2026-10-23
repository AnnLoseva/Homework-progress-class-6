# Notability and Goodnotes integration — what is verified

Checked **19 October 2026** against Ginger Labs' help centre (support.gingerlabs.com), the App
Store listing (Notability 16.x), and notability.com.

## Verified (official documentation)

| Capability | Source |
|---|---|
| Other apps can send files to Notability through the **iOS share sheet** ("Copy to Notability"). | [Importing Files](https://support.gingerlabs.com/en-us/articles/16300142-importing-files), [Troubleshooting Import Errors](https://support.gingerlabs.com/hc/en-us/articles/226961367-Troubleshooting-Import-Errors) |
| Inside Notability, files can be imported from Files, Dropbox, Google Drive, OneDrive, Box and WebDAV. | Importing Files |
| Since v16, Subjects and Dividers are **Folders** (up to six levels). | [Organize notes with folders](https://support.gingerlabs.com/en-us/articles/16300020-organize-notes-with-folders) |
| Notes can get a **share link** ("Create Link" → "Share Link", needs an account). The links are for viewing in a browser. | [Link Sharing](https://support.gingerlabs.com/en-us/articles/16300173-link-sharing) |
| Home Screen widgets can open a specific note or folder (internal to Notability). | [Widgets](https://support.gingerlabs.com/en-us/articles/16300127-widgets) |

## Not supported / not documented

- **No documented URL scheme** (`notability://`), x-callback-url, or command for importing a file.
- **No documented way to open a specific notebook or folder** from another app.
- **No Shortcuts / App Intents actions.** Ginger Labs has told users that Notability has no
  AppleScript, JavaScript or command-line interface.
- **No watched folder** in Files or iCloud Drive that other apps could write into.
- Notability's `apple-app-site-association` lists `/app/note/*` universal-link paths, which
  suggests internal note links exist. The ID format is **undocumented**, so this app does not
  build such links.

## What needs manual interaction

- After sharing, the user picks the destination inside Notability: a new note, or an existing
  note to add the PDF to. iOS does not let another app choose that.
- Opening the right folder when no saved link exists.

## What the app does

| Action | Behaviour |
|---|---|
| **Add PDF to Notability** | Makes a temporary, nicely named copy of the PDF and presents the share sheet anchored to the button. The app's own copy is never handed out or changed. When the share sheet closes, the app reports only what iOS reported: "Sent to Notability — finish the import there", "handed to another app", or nothing if cancelled. It never says "imported". |
| **Open Course Notebook** | If the user saved a link for the course, the link is handed to iOS and the app reports *that the link was opened*, not that a notebook was. If no link is saved, or iOS refuses it, a sheet explains the limitation. It shows the saved folder name (with a Copy button) and the steps to follow. |
| **Per-course association** | `NotabilityNotebookAssociation` stores the folder name and an optional link (only `https`, `http` or `notability:` are accepted). It is remembered across launches and included in backups. |

The closest reliable workflow is: open assignment → **Add PDF to Notability** → choose
Notability in the share sheet → in Notability choose the note or folder → start writing.

## Goodnotes

Checked **23 October 2026** against Goodnotes' help centre (support.goodnotes.com).

| | |
|---|---|
| **Verified:** other apps send PDFs through the **iOS share sheet** ("Open in Goodnotes"); Goodnotes then imports the file. | [Import documents](https://support.goodnotes.com/hc/en-us/articles/360001187355) |
| **Verified:** links to a notebook page exist only *inside* Goodnotes 6 (typed-text links with *Copy Link*). | [Create external and internal links](https://support.goodnotes.com/hc/en-us/articles/7353743248143) |
| **Not documented:** a `goodnotes://` URL scheme, x-callback-url or API that other apps can use to open a notebook or import a file. Users have asked for one on the Goodnotes feedback board. | — |

So Goodnotes works exactly like Notability here: the share sheet handoff, a per-course folder
name as a reminder, and an optional link the user pastes (`https`, or a `goodnotes:` link they
copied themselves). The app never builds Goodnotes links.

## Choosing the app

*Settings → Notes App* picks **Notability** (default) or **Goodnotes**. It's stored per device
(`noteApp.preferred` in UserDefaults), like the Moodle option. It changes the wording of the
buttons, hints and the "open notebook" sheet. The share sheet always lists every installed app,
and the result message names whichever app iOS reports, Notability or Goodnotes, whatever the
setting. The per-course notebook (`NotabilityNotebookAssociation`) is shared by both apps; the
model keeps its name because renaming it would break the iCloud schema.

## Testing

- **Simulator (automated):** link validation (incl. `goodnotes:`); outcome mapping for share
  completion (cancelled, Notability, Goodnotes, generic "open in app", other); messages never
  claim an import; the fallback never opens anything when no link is saved; handoff copies
  leave the original intact.
- **Real device only (manual):** Notability isn't available in the Simulator. On an iPad with
  Notability installed, check that:
  1. Notability appears in the share sheet.
  2. Choosing it opens Notability's import flow.
  3. The toast says "Sent to Notability…".
  4. The PDF is still in this app afterwards.
  5. Repeat with Goodnotes selected in Settings → Notes App: the button reads "Add PDF to
     Goodnotes", Goodnotes is in the share sheet, and the toast says "Sent to Goodnotes…".
