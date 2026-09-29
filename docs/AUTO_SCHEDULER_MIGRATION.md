# Auto Scheduler migration plan

2026-09-28 user-authorized product change. New specification takes precedence over the old MVP restrictions on priorities and automatic scheduling. No server, LLM, external package, or calendar provider API is introduced.

## Safety checkpoints

1. Finish the uncommitted card-deck / time-wheel work on `feature/mvp-complete`, build and test, and push a legacy recovery point.
2. Create a separate branch. Implement Foundation-only work-window / packing / selection policies and tests before changing the default UI.
3. Add storage without reinterpreting or deleting TaskOccurrence / ReviewRecord. Test opening an old on-disk schema and reopening after actions.
4. Integrate backlog creation, one-card Home, actions, and Calendar reconciliation. Only then remove old scheduling and Review from the default navigation.
5. Validate full build, unit/UI/launch tests and narrow Japanese screenshots; commit and push milestones.

## Intended data compatibility

- Keep the original Task entity, IDs, TaskOccurrence and ReviewRecord unchanged where possible. Priority / backlog completion metadata may live in a separate Task-linked entity to avoid changing the original schema's property meaning.
- Existing reusable Task definitions are not automatically declared completed or resurrected as unfinished work based on old occurrences. Preserve old records behind a clearly identified history route; adoption into the new backlog must be explicit.
- New proposals and completed/skipped actions are independent facts. Retain task/category/title/priority snapshots, proposal timestamp, action timestamp and kind. Do not derive work duration from these timestamps.
- Calendar allocation dates are synchronization metadata, not measured execution facts.

## Scheduling rules

- Work ranges are local wall-clock values, selected by the weekday of the range's start day; Friday 21:00–Saturday 02:00 is a weekday range. Previous-day ranges must be checked after midnight.
- Subtract and merge overlapping external busy intervals. Use half-open boundaries.
- Present only a task fitting the contiguous free interval available now. Sort priority descending, creation ascending, UUID as deterministic tie-breaker. Estimates must be 5–180 minutes in steps of 5.
- Keep an already presented task while its current allocation remains valid. Do not compare its full original estimate to the shrinking remainder on every timer tick.
- Completing closes the current proposal and backlog item atomically, then selects again from the actual current time. Skipping closes only that proposal; exclude the last skipped task until another action or another work session.
- Calendar changes, activation, settings edits and foreground time changes trigger recalculation. No unsupported promise of continuous iOS background execution.

## Calendar boundary

- Pass value intervals to the pure core, never EKEvent/EKCalendar.
- Keep CalendarReadPolicy holiday/dedupe/mirror filtering.
- Write/update/delete only explicitly owned Pocket scheduler events. General events must never be adopted by title or overwritten.
- Save local action facts before external writes; failed synchronization remains retryable. Permission denial and read failures must be distinguishable from an empty calendar.

## Verification focus

The required 13:00–16:00 / 180-minute priority-3 scenario and 15:20 completion → 30-minute task must be integration-tested, including persistence, action timestamps and calendar allocation. Also cover skip exclusion, boundary durations, overlapping busy intervals, overnight/weekend rules, restart, old-store preservation, large Japanese text and swipe interaction.

## Current status

Phase 0 validation completed on 2026-09-29: build, 48 unit tests, 15 interaction tests and 4 launch configurations passed across the full run and targeted rerun. The legacy checkpoint is committed separately before creating the scheduler branch. New scheduler phases are not yet implemented.
