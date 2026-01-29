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
- `screenshots/`: UI screenshots for PRs/docs.

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

## Testing Guidelines

- No automated test target is set up yet; validate changes via a quick manual smoke test:
  - Launch app on macOS and an iOS Simulator.
  - Add/edit an application; verify list, filters, and detail view update correctly.
  - If touching AI parsing, test with a real key and confirm failures are handled gracefully.

## Commit & Pull Request Guidelines

- Commit messages in this repo are short and action-oriented (e.g., “move files to repo root”); keep them concise and specific.
- PRs should include: summary of user-visible changes, manual test notes (macOS/iOS), and screenshots for UI changes (store in `screenshots/` when helpful).

## Security & Configuration Tips

- Do not commit API keys. The app stores keys in Keychain; configuration is done via in-app Settings.
- iCloud/CloudKit sync is optional; if changing container identifiers, update `Pipeline/PipelineApp.swift` and document it in the PR.
