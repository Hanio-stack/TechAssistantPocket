# Codex Instructions — TechAssistantPocket

## Sources of truth and preparation

- Treat `README.md` and `docs/DESIGN.md` as the current product and specification sources of truth.
- Follow `docs/DEVELOPMENT_KNOWLEDGE.md` as active development rules, including its preparation, implementation, and Knowledge Review workflow.
- Before coding, read those documents in that order, then inspect the relevant Issue, existing code, tests, and Git status. Read `CLAUDE.md` for aligned project guidance and `WORKLOG.md` for previous decisions and verification results.
- For UI work, inspect `docs/ui/README.md` and the relevant reference assets.
- Consult only task-relevant categories in `Hanio-stack/dev-knowledge`; distinguish applicable knowledge from guidance that does not fit this task.
- Resolve conflicts in this order: project-specific specifications and design decisions; current implementation and tests; shared development knowledge; generic guidance. Historical logs do not override current specifications. Do not rewrite existing systems merely to match generic guidance.

## MVP architecture and scope

Keep the iPhone MVP local-first, with zero operating cost and small, reversible changes. Prioritize the Plan → Do → Review → Improve → Plan loop.

Use only thin boundaries around platform dependencies:

```text
SwiftUI
├─ TaskRepository → SwiftData
├─ CalendarService → EventKitAdapter → EventKit
├─ NotificationService → UserNotifications
├─ InsightsEngine → pure Foundation logic
└─ SuggestionEngine → pure Foundation logic
```

- Keep Insights and Suggestions independent of SwiftUI, SwiftData, EventKit, and UserNotifications, with unit-testable, explainable rules.
- Keep platform implementation details behind the repository/service boundaries instead of spreading them through Views.
- SwiftData is authoritative for Pocket Tasks; their calendar events are mirrors. EventKit is authoritative for ordinary Events, which are excluded from Review and success metrics.
- Pocket Task notifications use UserNotifications only; do not attach Calendar Alarms to Task mirrors. Ordinary Event notifications use EventKit Calendar Alarms.
- Apply suggested schedule changes only after the app user approves them.
- Do not add a backend, Firebase, Supabase, CloudKit, direct Google Calendar API integration, OpenAI or other LLM APIs, or unnecessary dependencies. Google calendars are accessed through EventKit and the iPhone's configured accounts.
- Do not add Task priorities, a separate Review tab, chat, natural-language input, complex automatic scheduling, team sharing, or full calendar bidirectional synchronization to the MVP.
- Avoid large Clean Architecture structures, speculative abstractions, and extracting shared libraries before responsibilities and APIs are validated in this project. Future-feature mentions are not authorization to implement them.

## Human Gate

Do not redesign the architecture or expand MVP scope without explicit human approval. Present the concrete proposed change, reason, impact, and smaller alternatives before proceeding with a gated change.

Human approval is also required for new external dependencies, substantial data-model changes, calendar implementations beyond EventKit, CloudKit/server introduction, changes contradicting current specifications, and hard-to-reverse migrations. Approval must explicitly authorize any change to the MVP restrictions above.

## Implementation and verification

1. Inspect relevant documents and code before editing; choose the smallest reversible implementation that satisfies the task.
2. Implement within the existing architecture and current specification.
3. After implementation, run applicable `xcodebuild` build/test commands and relevant unit tests. Discover the actual project/workspace, scheme, and available destination rather than inventing them.
4. Investigate failures, fix their causes, and repeat applicable checks. Do not change the specification merely to make tests pass.
5. For UI changes, verify in Simulator or on a device, including narrow-screen Japanese layouts where applicable.
6. Review the diff against the requested scope and completion criteria. Report checks run, results, and any checks that could not run with their reasons; do not claim unperformed validation.
7. Record meaningful work, decisions, reasons, and validation in `WORKLOG.md` when within the authorized scope. At meaningful milestones, perform Knowledge Review; only sufficiently validated, reusable findings are candidates for shared knowledge or libraries.

Documentation-only changes do not require an app build unless they affect build behavior. Respect requests limiting edits to particular files.

## Git and change discipline

- Preserve existing Git history and user changes. Do not reset, discard, or overwrite unrelated work or rewrite history.
- Do not commit or push unless explicitly asked.
- Keep changes focused; avoid unrelated refactors, dependency additions, and scope expansion.
- Distinguish verified facts from assumptions, and explain material limitations in the completion report.
