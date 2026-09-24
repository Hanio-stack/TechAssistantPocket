# UI Mockups

Approved MVP direction, repaired and refreshed on 2026-09-19.

- `today.svg` — simplified Today screen. Tasks use checkboxes; normal events do not.
- `insights.svg` — simplified Insights landing page with only weekly success rate and task list.
- `task-insight-detail.svg` — task detail view showing success rate by weekday/time band and a schedule suggestion.

The previous PNG files were removed because their binary data was corrupted. SVG is used here so the reference assets remain human-readable in Git, render directly on GitHub, and are less likely to be corrupted by text-oriented repository tooling.

These images are visual references, not pixel-perfect implementation requirements. During implementation, prioritize native iOS usability, clarity, accessibility, and consistency with the product design documented in `docs/DESIGN.md`.

## Home v2 — 2026-09-22

- `TechSecretaryPocket_Today_Home_v2.jpg` — user-supplied official Home reference for the second device-test revision. The attachment is JPEG, preserved without conversion. It supersedes `today.svg` for Home composition.
- Keep the native navigation and tab bars. Use a prominent current Task card, skip/complete actions, a chronological upcoming list, and initially collapsed history. No category emoji, pause action, note field, or invented location data. Larger text may stack vertically.
