# Administrator guide

You manage content from inside the app (**Manage** tab on iPhone, **Manage lessons** in the
iPad sidebar). The tab appears only after the server grants you the administrator role (see
[README §10](../README.md#10-create-the-first-administrator-securely)).

## Lesson lifecycle

```
 draft ──Publish──▶ published ──Archive──▶ archived
   ▲                   │  ▲                    │
   └──Unpublish────────┘  └────Publish again───┘
```

| State | Students see it? | In workloads? | Progress |
|---|---|---|---|
| Draft | No (not even its files) | No | Kept if it was published before |
| Published | Yes, once *Available from* has passed | Required: everyone. Optional: subscribers | Editable |
| Archived | Yes, in *History* | No | Kept and still editable for the record |

* A draft that was **never published** can be deleted. A lesson that any student has
  progress on **can't be deleted**, only archived; the database enforces this.
* Republishing an archived lesson reuses the same lesson, so there are no duplicates.

## Fields

| Field | Notes |
|---|---|
| Category | **Required (חובה)** or **Optional (רשות)**. Required lessons are in every student's workload; optional ones only for subscribers. |
| Course, Week, Module, Position | Used for grouping, filters and ordering. |
| Numbered exercises | `0` = no counter; students mark the lesson complete manually. Lowering it later never deletes a student's higher count; the app just caps the display. |
| Available from | Schedules publication: a published lesson stays hidden until this time. |
| Due | Shown on the dashboard and in deadlines. |
| Prerequisites | Shown on the lesson page; informational only. |

## Changing the category

* **Optional → Required:** the lesson enters every student's workload. Subscriptions and
  progress are kept.
* **Required → Optional:** students who already started it (any progress or notes) are
  subscribed automatically, so their work doesn't disappear. Others can subscribe if they want.

## PDFs

* **Add PDF:** PDF only, up to 50 MB; the app checks the file before uploading. You can
  preview it before saving.
* **Class members** (restricted): students who joined with the class code. **Anyone**:
  every signed-in user, and anyone with the link while the lesson is published.
* **Replace PDF** keeps the same attachment (and the same place in students' lists),
  bumps its version, and deletes the old file. Students' progress is untouched, and their
  devices download the new version the next time they open it.
* Files of draft lessons are never readable by students, even if someone guesses the path.

## Class code

Set it under **Manage → Class code**. Only a hash is stored, so the app can't show it
again. Changing it doesn't remove students who already joined. Each account gets 10 wrong
attempts per hour.

## What administrators can't see

Students' progress, exercise counts, notes and subscriptions are private: there's no screen,
API or database policy that shows them to you. This is intentional. If an aggregate view
(e.g. "how many students finished lesson 3") is ever needed, add a separate, documented
function that returns counts only.
