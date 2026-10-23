# Administrator guide

You manage content from inside the app: **Class → Manage lessons** (the section menu on
iPhone, the Class sidebar section on iPad). It appears only after the server grants you the
administrator role (see [README → Setup, step 7](../README.md#setup)).

## Publishing your homework

**Settings → Class → Publish Homework to Class** lists your weeks and assignments; all are
selected at first. Pick the category for **new** lessons (Required by default) and who can open
the PDFs (*Class members* by default), then **Publish**.

* Each assignment becomes a published lesson with the same id, in a class course matched to
  your homework course (created on the first publish). Title, week, due date and exercise
  total are copied. Completed counts, status and notes are **not**.
* Publishing again updates those lessons: no duplicates. Lessons published before keep their
  category, and their PDFs keep their visibility. A PDF whose size changed is uploaded as a
  new version of the same attachment; students' progress stays.
* Only share PDFs you're allowed to share. *Class members* limits them to students who joined
  with the class code.
* Lessons you then edit in *Manage lessons* are overwritten by the next publish of the same
  assignment (title, week, due date, exercise total). Archive or edit the homework instead.

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

Set it under **Manage lessons → Class code**. Only a hash is stored, so the app can't show it
again. Changing it doesn't remove students who already joined. Each account gets 10 wrong
attempts per hour.

## What administrators can't see

Students' progress, exercise counts, notes and subscriptions are private: there's no screen,
API or database policy that shows them to you. This is intentional. If an aggregate view
(e.g. "how many students finished lesson 3") is ever needed, add a separate, documented
function that returns counts only.
