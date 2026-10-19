# Backup format (version 1)

**Settings → Export Backup** writes a single UTF-8 JSON file named
`Homework Backup YYYY-MM-DD.json`. It contains all structured data and every PDF.

```jsonc
{
  "format": "hit-homework-backup",   // identifies the file type
  "formatVersion": 1,                // bumped on incompatible changes
  "exportedAt": "2026-10-19T16:30:00Z",
  "appVersion": "1.0",
  "courses": [{
    "id": "UUID", "name": "מתמטיקה בדידה", "englishName": "Discrete Mathematics",
    "courseURL": "https://md.hit.ac.il/course/view.php?id=27652",
    "colorKey": "plum", "iconName": "point.3.connected.trianglepath.dotted",
    "sortOrder": 4, "createdAt": "…",
    "notebookName": "Discrete Math", "notebookLink": null
  }],
  "weeks": [{
    "id": "UUID", "title": "Week 5", "number": 5,
    "startDate": "…", "endDate": "…", "notes": "", "createdAt": "…"
  }],
  "assignments": [{
    "id": "UUID", "courseID": "UUID", "weekID": "UUID", "title": "Homework 5",
    "dueDate": null, "totalExercises": 9, "completedExercises": 6, "notes": "",
    "status": "inProgress",          // notAssigned | notStarted | inProgress | completed | postponed
    "createdAt": "…", "updatedAt": "…"
  }],
  "attachments": [{
    "id": "UUID", "assignmentID": "UUID", "originalFilename": "Sheet 5.pdf",
    "pageCount": 2, "sortIndex": 0, "importedAt": "…",
    "pdf": "JVBERi0xLjcK…"            // base64 PDF bytes; null if the file was missing at export
  }]
}
```

- Dates are ISO 8601. `totalExercises: null` means "not specified".
- **Restore merges.** Records whose `id` already exists are left untouched. Missing ones are
  added, and PDFs are written back into app storage. Restoring never deletes or overwrites
  anything, so restoring the same file twice changes nothing.
- A file with a different `format`, or a higher `formatVersion` than the app understands, is
  rejected.
- Future versions must keep reading version 1 files.
