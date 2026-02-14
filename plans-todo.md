# Pipeline — Feature Expansion Plan

## Context

Pipeline is a SwiftUI + SwiftData job tracker (macOS 14+ / iOS 17+) with AI-powered job posting parsing. Currently it's a single Xcode target with 52 Swift files, no SPM dependencies, and no extension targets.

We're expanding in two directions:
1. **Browser extensions** (Safari + Chrome) that capture job postings from the browser, extract DOM text, and pass it to the app for AI parsing and storage
2. **Core app features** — Kanban board, AI Interview Prep, AI Follow-up Email Drafter, Dashboard/Analytics

The extension architecture: extension handles text extraction (DOM access), app handles AI parsing (has API keys) and storage (SwiftData). Communication via shared SwiftData store (App Groups). Chrome uses a native messaging host (small CLI bundled in the .app).

Implementation gaps (notification permissions, API key validation, interview log editing) are **out of scope** — separate effort.

---

## Phase 1: PipelineKit — Local Swift Package Extraction

Extract shared code so it can be reused by the app, Safari extension, and Chrome native messaging host.

### Task 1.1: Create PipelineKit package skeleton

Create a local SPM package at repo root.

**Create:**
- `PipelineKit/Package.swift` — platforms `.macOS(.v14), .iOS(.v17)`, library `PipelineKit`
- `PipelineKit/Sources/PipelineKit/` and `PipelineKit/Tests/PipelineKitTests/`

---

### Task 1.2: Split Constants.swift

Current `Pipeline/Utilities/Constants.swift` mixes pure data (app IDs, URLs, keys, limits) with SwiftUI code (Color extensions, DesignSystem, view modifiers, CustomValuesStore).

**Create:**
- `PipelineKit/Sources/PipelineKit/Utilities/Constants.swift` — `Constants.App`, `.iCloud`, `.URLs`, `.UserDefaultsKeys`, `.Notifications`, `.Limits`. Pure Foundation, no SwiftUI. Use `#if canImport(SwiftUI)` for anything that needs it.

**Modify:**
- `Pipeline/Utilities/Constants.swift` — keep only SwiftUI-dependent code (Color extensions, DesignSystem, view modifiers, CustomValuesStore). Add `import PipelineKit`.

**Note:** `Constants.App.bundleID` currently uses `Bundle.main` — make it a plain static let in the package, override in app if needed.

**Depends on:** 1.1

---

### Task 1.3: Extract Enums to PipelineKit

Move all 6 enum files. Each currently imports SwiftUI for `Color` — wrap color properties in `#if canImport(SwiftUI)`. Mark all types and members `public`.

**Create:**
- `PipelineKit/Sources/PipelineKit/Models/Enums/ApplicationStatus.swift`
- `PipelineKit/Sources/PipelineKit/Models/Enums/InterviewStage.swift`
- `PipelineKit/Sources/PipelineKit/Models/Enums/Platform.swift`
- `PipelineKit/Sources/PipelineKit/Models/Enums/Priority.swift`
- `PipelineKit/Sources/PipelineKit/Models/Enums/Source.swift`
- `PipelineKit/Sources/PipelineKit/Models/Enums/Currency.swift`

**Delete from app:** `Pipeline/Models/Enums/*.swift` (supplied by `import PipelineKit`)

**Depends on:** 1.1

---

### Task 1.4: Extract Utilities to PipelineKit

**Create:**
- `PipelineKit/Sources/PipelineKit/Utilities/DateFormatters.swift`
- `PipelineKit/Sources/PipelineKit/Utilities/URLHelpers.swift`

`URLHelpers.openInBrowser` uses AppKit/UIKit — wrap in `#if canImport`. Everything else is pure Foundation. Mark public.

**Depends on:** 1.1

---

### Task 1.5: Extract SwiftData Models

Move `JobApplication.swift` and `InterviewLog.swift` to PipelineKit. Mark classes, inits, and properties `public`. Remove any `sampleData` — keep those as extensions in the app target for previews.

`JobApplication` references `URLHelpers` methods — those are already in PipelineKit from Task 1.4.

**Create:**
- `PipelineKit/Sources/PipelineKit/Models/JobApplication.swift`
- `PipelineKit/Sources/PipelineKit/Models/InterviewLog.swift`

**Depends on:** 1.2, 1.3, 1.4

---

### Task 1.6: Extract SidebarFilter

Move `SidebarFilter.swift`. Depends on `ApplicationStatus`. Wrap SwiftUI Color in `#if canImport`.

**Create:**
- `PipelineKit/Sources/PipelineKit/Models/SidebarFilter.swift`

**Depends on:** 1.3

---

### Task 1.7: Decouple ParsedJobData from AIParsingViewModel

`AIServiceProtocol.parseJobPosting` currently returns `AIParsingViewModel.ParsedJobData` — a nested type that couples the protocol to a ViewModel. Extract it as a standalone public struct.

**Create:**
- `PipelineKit/Sources/PipelineKit/Services/AI/ParsedJobData.swift`

**Modify:**
- `Pipeline/ViewModels/AIParsingViewModel.swift` — remove nested struct, use standalone `ParsedJobData` from PipelineKit

**Depends on:** 1.3 (uses `Currency`)

---

### Task 1.8: Extract AI Services to PipelineKit

Move protocol, prompts, parser, and all 3 provider services. **WebContentFetcher stays in the app** (uses WKWebView).

To decouple from WebContentFetcher, introduce a protocol:
```swift
public protocol WebContentProvider {
    func fetchText(from url: String) async throws -> String
}
```
AI services take a `WebContentProvider` in their initializer. App provides `WKWebViewContentProvider`, CLI host provides `BasicWebContentProvider` (URLSession-only path that already exists in WebContentFetcher).

Also extract from `SettingsViewModel.swift`:
- `AIProvider`, `AIProviderDescriptor`, `AIProviderRegistry` — needed by services and extensions
- `ModelCatalogService` — needed for model listing
- `ReminderTiming`, `AppearanceMode` — simple enums used across boundaries

**Create:**
- `PipelineKit/Sources/PipelineKit/Services/AI/AIServiceProtocol.swift` — protocol, errors, debug logger
- `PipelineKit/Sources/PipelineKit/Services/AI/AIServicePrompts.swift`
- `PipelineKit/Sources/PipelineKit/Services/AI/AIResponseParser.swift`
- `PipelineKit/Sources/PipelineKit/Services/AI/OpenAIService.swift`
- `PipelineKit/Sources/PipelineKit/Services/AI/AnthropicService.swift`
- `PipelineKit/Sources/PipelineKit/Services/AI/GeminiService.swift`
- `PipelineKit/Sources/PipelineKit/Services/AI/WebContentProvider.swift`
- `PipelineKit/Sources/PipelineKit/Services/AI/AIProvider.swift` — enum, descriptor, registry
- `PipelineKit/Sources/PipelineKit/Services/AI/ModelCatalogService.swift`
- `PipelineKit/Sources/PipelineKit/Settings/ReminderTiming.swift`
- `PipelineKit/Sources/PipelineKit/Settings/AppearanceMode.swift`

**Modify:**
- `Pipeline/ViewModels/SettingsViewModel.swift` — remove extracted types, add `import PipelineKit`
- `Pipeline/Services/AIService/AIServiceProtocol.swift` — becomes thin file with only `WebContentFetcher` (WKWebView code)

**Depends on:** 1.7

---

### Task 1.9: Extract KeychainService and Supporting Services

**Create:**
- `PipelineKit/Sources/PipelineKit/Services/KeychainService.swift`
- `PipelineKit/Sources/PipelineKit/Services/PlatformDetectionService.swift`
- `PipelineKit/Sources/PipelineKit/Services/NotificationService.swift`

`NotificationService` already has `#if canImport` guards. `PlatformDetectionService` is pure Foundation. Mark all public.

**Depends on:** 1.8 (KeychainService uses `AIProvider.keychainKey`)

---

### Task 1.10: Create SharedContainer for App Group

Factory for creating `ModelContainer` pointing at the App Group shared container.

**Create:**
- `PipelineKit/Sources/PipelineKit/SharedContainer.swift`

```swift
public enum SharedContainer {
    public static let appGroupID = "group.io.github.digitaltracer.pipeline"

    public static func makeModelContainer(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
    ) throws -> ModelContainer { ... }
}
```

Falls back to `applicationSupportDirectory` if App Group unavailable (development/testing).

**Depends on:** 1.5

---

### Task 1.11: Add App Groups Entitlement

Add `com.apple.security.application-groups` with `group.io.github.digitaltracer.pipeline` to all 3 entitlements files. Additive — does not disturb existing CloudKit config.

**Modify:**
- `Pipeline/Pipeline.CloudKit.entitlements`
- `Pipeline/Pipeline.CloudKit.iOS.entitlements`
- `Pipeline/Pipeline.entitlements`

**Depends on:** Nothing (parallel with other Phase 1 tasks)

---

### Task 1.12: Integrate PipelineKit into main app

- Add PipelineKit as local package dependency in Xcode project
- Update `PipelineApp.swift` to use `SharedContainer.makeModelContainer()`
- Add `import PipelineKit` to all files referencing extracted types
- Remove extracted `.swift` files from the app build phase

**Depends on:** 1.2–1.10

---

### Task 1.13: Verify build and run

Build for macOS + iOS. Verify: app launches, add application works, grid displays, sidebar filters, AI parsing, settings persist.

**Depends on:** 1.12

---

## Phase 2: Core App Features

### Task 2.1: Kanban Board — ViewModel

**Create:** `Pipeline/ViewModels/KanbanViewModel.swift`

Groups applications by status columns (Saved, Applied, Interviewing, Offered, Rejected). Handles `moveApplication(_:to:context:)` for drag-and-drop status changes. Auto-sets `appliedDate` when moving to Applied/Interviewing.

**Depends on:** Phase 1

---

### Task 2.2: Kanban Board — Compact Card

**Create:** `Pipeline/Views/Kanban/KanbanCardView.swift`

Compact card: company avatar (32pt), role (1 line), company (1 line), priority flag. Uses existing `CompanyAvatar` and `PriorityFlag`. Supports `.onDrag` returning `NSItemProvider` with UUID string.

**Depends on:** 2.1

---

### Task 2.3: Kanban Board — Column View

**Create:** `Pipeline/Views/Kanban/KanbanColumnView.swift`

Status header with icon + name + count badge. Colored top border. Vertical `ScrollView` + `LazyVStack` of cards. `.onDrop(of: [.plainText])` handler that looks up application by UUID and calls `moveApplication`.

**Depends on:** 2.2

---

### Task 2.4: Kanban Board — Full Board + Toggle

**Create:** `Pipeline/Views/Kanban/KanbanBoardView.swift`

`ScrollView(.horizontal)` with `HStack` of columns. Card tap sets selection (same as grid).

**Modify:** `Pipeline/Views/Main/MainView.swift` — add `ViewMode` enum (`.grid`, `.kanban`), toolbar picker to toggle, conditionally show `ApplicationListView` or `KanbanBoardView`.

**Depends on:** 2.3

---

### Task 2.5: AI Interview Prep — Prompts + Service

**Create:** `PipelineKit/Sources/PipelineKit/Services/AI/InterviewPrepService.swift`

`InterviewPrepResult` struct (likelyQuestions, talkingPoints, companyResearchSummary). Prompt takes role, company, JD, interview stage, existing notes. Returns structured JSON.

**Depends on:** 1.8

---

### Task 2.6: AI Interview Prep — ViewModel

**Create:** `Pipeline/ViewModels/InterviewPrepViewModel.swift`

`@Observable` class. Takes `JobApplication` + `SettingsViewModel`. Calls AI service with interview prep prompt. Parses response into `InterviewPrepResult`.

**Depends on:** 2.5

---

### Task 2.7: AI Interview Prep — View

**Create:** `Pipeline/Views/Detail/InterviewPrepView.swift`

Sheet with sections: Likely Questions (numbered), Talking Points (bulleted), Company Research (prose). Copy-all and regenerate buttons. Loading + error states.

**Modify:** `Pipeline/Views/Detail/JobDetailView.swift` — add "Interview Prep" button to bottom action bar (visible when status is `.interviewing`). Wire sheet presentation.

**Depends on:** 2.6

---

### Task 2.8: AI Follow-up Email Drafter — Prompts + Service

**Create:** `PipelineKit/Sources/PipelineKit/Services/AI/FollowUpDrafterService.swift`

`FollowUpEmailResult` struct (subject, body). Prompt takes company, role, stage, notes, days since last contact. Returns professional 150-250 word email.

**Depends on:** 1.8

---

### Task 2.9: AI Follow-up Email Drafter — ViewModel + View

**Create:**
- `Pipeline/ViewModels/FollowUpDrafterViewModel.swift`
- `Pipeline/Views/Detail/FollowUpDrafterView.swift`

View: editable subject + body TextEditor, "Copy to Clipboard", "Open in Mail" (mailto: URL), "Regenerate". Computes `daysSinceLastContact` from latest interview log or `updatedAt`.

**Modify:** `Pipeline/Views/Detail/JobDetailView.swift` — add "Draft Follow-up" button to bottom action bar. Wire sheet.

**Depends on:** 2.8

---

### Task 2.10: Dashboard — ViewModel

**Create:** `Pipeline/ViewModels/DashboardViewModel.swift`

Computes: funnel data (count per status), weekly activity (apps added per week over last 8 weeks), average time-in-stage, response rate trend.

**Depends on:** Phase 1

---

### Task 2.11: Dashboard — View

**Create:** `Pipeline/Views/Main/DashboardView.swift`

Uses Swift Charts (`import Charts`). Sections: summary cards at top, funnel bar chart, weekly activity line chart, time-in-stage bars, response rate display.

**Modify:**
- `Pipeline/Views/Main/SidebarView.swift` — add "Dashboard" item above "All Applications"
- `Pipeline/Views/Main/MainView.swift` — show `DashboardView` when dashboard selected

**Depends on:** 2.10

---

## Phase 3: Safari Extension

### Task 3.1: Shared JavaScript (content script + popup)

Shared between Safari and Chrome. Can be done in parallel with Phase 1.

**Create:**
- `SharedExtensionJS/content.js` — DOM extraction with platform-specific selectors (LinkedIn, Indeed, Glassdoor, Naukri, generic fallback). Strips nav/footer/ads/scripts.
- `SharedExtensionJS/popup.html` — popup UI: extracted data preview, "Save to Pipeline" button, status indicator
- `SharedExtensionJS/popup.js` — popup logic, messages to background script
- `SharedExtensionJS/popup.css` — styles
- `SharedExtensionJS/background.js` — routes messages between content script and native layer

Platform-specific selectors:
```javascript
const SELECTORS = {
    'linkedin.com': { container: '.jobs-description-content__text', title: '.top-card-layout__title', ... },
    'indeed.com': { container: '#jobDescriptionText', ... },
    'glassdoor.com': { container: '.JobDetails_jobDescription__uW_fK', ... },
    'naukri.com': { container: '.styles_JDC__dang-inner-html__h0K4t', ... }
};
```

**Depends on:** Nothing

---

### Task 3.2: Safari Web Extension target

Add Safari Web Extension target to Xcode project.

**Create:**
- `Pipeline/PipelineSafariExtension/SafariWebExtensionHandler.swift`
- `Pipeline/PipelineSafariExtension/Info.plist`
- `Pipeline/PipelineSafariExtension/PipelineSafariExtension.entitlements` — App Group + Keychain access group
- `Pipeline/PipelineSafariExtension/Resources/manifest.json` — Manifest V3
- `Pipeline/PipelineSafariExtension/Resources/` — JS files from SharedExtensionJS

**Xcode changes:** New target, link PipelineKit, set team, add entitlements.

**Depends on:** 1.10, 1.12, 3.1

---

### Task 3.3: Implement SafariWebExtensionHandler

The native handler that receives extracted text from JS, runs AI parsing, saves to shared SwiftData store, responds with result or duplicate warning.

Creates its own `ModelContainer` via `SharedContainer` (runs in separate process). Accesses Keychain for API keys.

**Depends on:** 3.2

---

### Task 3.4: Keychain Access Group for sharing

Configure shared Keychain so extensions and native host can read API keys.

**Modify:**
- All entitlements files — add `keychain-access-groups`
- `PipelineKit/Sources/PipelineKit/Services/KeychainService.swift` — add `kSecAttrAccessGroup` to queries

**Depends on:** 1.9

---

## Phase 4: Chrome Extension + Native Messaging Host

### Task 4.1: Chrome Extension files

**Create:**
- `ChromeExtension/manifest.json` — Manifest V3, nativeMessaging permission
- `ChromeExtension/content.js` — copy/symlink from SharedExtensionJS
- `ChromeExtension/popup.html`, `popup.js`, `popup.css` — copy/symlink from SharedExtensionJS
- `ChromeExtension/background.js` — Chrome-specific, uses `chrome.runtime.sendNativeMessage("io.github.digitaltracer.pipeline", ...)`
- `ChromeExtension/icons/` — 16, 48, 128px

**Depends on:** 3.1

---

### Task 4.2: Native Messaging Host target

macOS command-line tool target in Xcode. Links PipelineKit, does NOT link SwiftUI/WebKit.

**Create:**
- `Pipeline/PipelineNativeHost/main.swift` — Chrome native messaging protocol (4-byte length prefix + JSON over stdin/stdout)
- `Pipeline/PipelineNativeHost/NativeMessageHandler.swift` — routes commands (parse, check-duplicate), creates `ModelContainer` via `SharedContainer`, runs AI parsing, writes `JobApplication`

**Xcode changes:** New "PipelineNativeHost" command-line tool target, link PipelineKit, macOS 14 minimum.

**Depends on:** 1.10, 1.12

---

### Task 4.3: Host manifest + installer

**Create:**
- `ChromeExtension/io.github.digitaltracer.pipeline.json` — host manifest pointing to binary inside .app bundle
- `ChromeExtension/install_host.sh` — copies manifest to `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`

**Depends on:** 4.2

---

### Task 4.4: Duplicate Detection Service

Shared service in PipelineKit used by both extension handlers.

**Create:** `PipelineKit/Sources/PipelineKit/Services/DuplicateDetectionService.swift`

Checks by URL (exact match), then by company+role (case-insensitive).

**Depends on:** 1.5

---

## Dependency Graph

```
Phase 1 (PipelineKit):                     Phase 3 (Safari):
  1.1 ─┬─> 1.2 ──────────────┐              3.1 (shared JS, parallel)
       ├─> 1.3 ─┬─> 1.6      │                │
       ├─> 1.4  │             │              3.2 <── 1.10 + 1.12 + 3.1
       │        │             │                │
       │   1.3 + 1.4 ──> 1.5 │              3.3 <── 3.2
       │                     │
       └─> 1.7 ──> 1.8 ──> 1.9            3.4 <── 1.9
                    │
  1.5 ──> 1.10     │         Phase 4 (Chrome):
                    │           4.1 <── 3.1
  1.2-1.10 ──> 1.12 ──> 1.13   4.2 <── 1.10 + 1.12
                                4.3 <── 4.2
  1.11 (App Groups, parallel)   4.4 <── 1.5

Phase 2 (App Features):
  Phase 1 ──> 2.1 ──> 2.2 ──> 2.3 ──> 2.4  (Kanban)
  1.8 ──> 2.5 ──> 2.6 ──> 2.7              (Interview Prep)
  1.8 ──> 2.8 ──> 2.9                       (Follow-up Drafter)
  Phase 1 ──> 2.10 ──> 2.11                 (Dashboard)
```

## Key Risks & Decisions

1. **Store migration:** Moving from default SwiftData location to App Group container. On first launch after update, check for existing store at old location and migrate data. Handle in `PipelineApp.swift`.

2. **PipelineKit must not unconditionally import SwiftUI.** The Chrome native host is a CLI. All SwiftUI-dependent code (Color properties, view modifiers) must use `#if canImport(SwiftUI)`.

3. **`SettingsViewModel.swift` houses 6+ types** that need extraction (AIProvider, AIProviderDescriptor, AIProviderRegistry, ModelCatalogService, ReminderTiming, AppearanceMode). This is the most complex file to decompose.

4. **Kanban drag-and-drop:** Use `NSItemProvider` with UUID string (not `Transferable`). The drop handler fetches the `JobApplication` by UUID from `ModelContext`. More reliable for SwiftData `@Model` reference types.

5. **Chrome extension ID** isn't known until published to Chrome Web Store. Use a placeholder in the host manifest during development; update after publishing. For local development, use the unpacked extension ID.

## Verification

After each phase:
- **Phase 1:** `xcodebuild -scheme Pipeline -destination 'platform=macOS'` succeeds. App launches, all existing features work.
- **Phase 2:** Kanban toggle works, drag-and-drop changes status. AI Interview Prep and Follow-up Drafter generate results with a valid API key. Dashboard shows charts.
- **Phase 3:** Safari extension appears in Safari preferences. Clicking the extension on a LinkedIn job page extracts content and saves to Pipeline. Duplicate warning shown for existing applications.
- **Phase 4:** Chrome extension loads as unpacked. Native host receives messages. Job saved to same SwiftData store visible in the app.
