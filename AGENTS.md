# Repository Guidelines

## Project Structure & Module Organization

- `Pipeline/`: SwiftUI app source (Xcode project lives at `Pipeline/Pipeline.xcodeproj`).
  - `Models/`: SwiftData `@Model` types and enums (stored as raw values when needed).
  - `ViewModels/`: `@Observable` view models (generally owned via `@State` in views).
  - `Views/`: SwiftUI screens/components (see `Views/Main/` for app shell).
  - `Services/`: business logic (AI providers, Keychain, logo fetch, notifications).
  - `Utilities/`: small helpers/constants (date formatters, URL helpers).
  - `Resources/`: assets (`Assets.xcassets`) and other bundled resources.
- `runlocal.md`: detailed local setup (signing, simulator, iCloud).
- `CHANGELOG.md`: public-facing list of notable changes.

## Build, Test, and Development Commands

Primary workflow is Xcode (Cmd+R). Useful CLI equivalents:

```bash
open Pipeline/Pipeline.xcodeproj
cd Pipeline && xcodebuild -scheme Pipeline -destination 'platform=macOS' build
cd Pipeline && xcodebuild -scheme Pipeline clean
xcrun simctl list devices
```

## Coding Style & Naming Conventions

- Indentation: 4 spaces; follow Xcode’s Swift formatting.
- Prefer `final` classes, `guard` for early exits, and `private` for implementation details.
- Keep files/folders aligned with feature type: `FooView.swift`, `FooViewModel.swift`, `FooService.swift`.
- Use `// MARK: -` to group sections; keep SwiftUI views small and compose via `Views/Components/`.

## Panel Layout Guardrails (MainView)

- Do not force `NavigationSplitViewVisibility.doubleColumn` in the main app shell. This repeatedly causes the sidebar to start closed, which is a known regression.
- Do not rely on `columnVisibility` toggling (`.automatic`/`.all`) to show and hide details in `MainView`; this can leave an empty right panel and can still collapse the sidebar.
- Prefer explicit layout switching:
  - No selection: use the 2-column split (sidebar + main content).
  - Selection present: use the 3-column split (sidebar + main content + detail panel).
- Do not wrap `selectedApplication` changes in `withAnimation` when opening or closing details from grid/kanban cards. This causes whole-layout motion ("app shaking") instead of a stable panel reveal.
- Preserve user-facing panel stability: sidebar stays visible by default, main panel resizes predictably, right detail panel opens without shifting the entire shell.

## Testing Guidelines

- No automated test target is set up yet; validate changes via a quick manual smoke test:
  - Launch app on macOS and an iOS Simulator.
  - Add/edit an application; verify list, filters, and detail view update correctly.
  - For panel/layout changes, verify:
    - Sidebar is visible on initial launch (not force-collapsed).
    - Clicking a Job Card opens the right detail panel without "shaking" all panels.
    - Closing details returns to the default split view without hiding the sidebar.
  - If touching AI parsing, test with a real key and confirm failures are handled gracefully.

## Commit & Pull Request Guidelines

- Commit messages in this repo are short and action-oriented (e.g., “move files to repo root”); keep them concise and specific.
- PRs should include: summary of user-visible changes and manual test notes (macOS/iOS).
- When adding, removing, or modifying a user-facing feature, update `CHANGELOG.md` in the same change.
- Add changelog entries under `## [Unreleased]` using `Added`, `Changed`, or `Fixed` sections.
- Keep changelog entries grouped by release context: if multiple edits touch the same feature in one release cycle, update the existing bullet instead of appending near-duplicate bullets.
- Prefer compact, feature-level summaries in `## [Unreleased]` (what changed and why) over step-by-step implementation notes.

## Security & Configuration Tips

- Do not commit API keys. The app stores keys in Keychain; configuration is done via in-app Settings.
- iCloud/CloudKit sync is optional; if changing container identifiers, update `Pipeline/PipelineApp.swift` and document it in the PR.
