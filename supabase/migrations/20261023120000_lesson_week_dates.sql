-- The class week's calendar dates on each lesson.
--
-- `week` is only a number. Publishing from the homework tracker now also stores the first and
-- last day of the homework week the lesson came from, so every student's copy lands in the
-- same calendar week (e.g. Week 1 = 18–23 Oct), not in a week guessed from the due date.
--
-- Additive and nullable: existing lessons and older app versions keep working (they neither
-- read nor write these columns). The existing lesson policies cover them; no grant changes.

alter table public.lessons
  add column week_starts_on date,
  add column week_ends_on   date,
  add constraint lessons_week_dates_together check ((week_starts_on is null) = (week_ends_on is null)),
  add constraint lessons_week_dates_order check (week_ends_on is null or week_ends_on >= week_starts_on),
  add constraint lessons_week_dates_length check (week_ends_on is null or week_ends_on - week_starts_on <= 13);

comment on column public.lessons.week_starts_on is
  'First day of the class week the lesson belongs to (the publishing homework week). Null if unknown.';
comment on column public.lessons.week_ends_on is
  'Last day of that week. Set together with week_starts_on.';
