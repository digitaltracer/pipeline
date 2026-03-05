# Pipeline - Job Application Tracking App

## Overview

Pipeline is a cross-platform (macOS + iOS) job application tracking app built with SwiftUI and SwiftData. It helps users track job applications through various stages, log interviews, and get follow-up reminders.

## Tech Stack

- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData with CloudKit sync
- **Architecture**: MVVM (Model-View-ViewModel)
- **Minimum Targets**: macOS 14.0 (Sonoma), iOS 17.0
- **Language**: Swift 5.9+

## Project Structure

```
pipeline/                              # Git repo root
├── .gitignore
├── CLAUDE.md                          # This file
├── runlocal.md                        # Local development instructions
├── README.md
├── LICENSE
│
└── Pipeline/                          # Xcode project folder
    ├── Pipeline.xcodeproj/            # Xcode project
    ├── PipelineApp.swift              # App entry point, ModelContainer setup
    ├── ContentView.swift              # Root view, platform-specific layout
    ├── Pipeline.entitlements          # iCloud, CloudKit, Keychain, Network
    │
    ├── Models/                        # SwiftData @Model classes
    │   ├── JobApplication.swift       # Main data model
    │   ├── InterviewLog.swift         # Interview history entries
    │   ├── SidebarFilter.swift        # Sidebar filter enum
    │   └── Enums/                     # All enum types
    │
    ├── ViewModels/                    # @Observable business logic
    │   ├── ApplicationListViewModel.swift
    │   ├── ApplicationDetailViewModel.swift
    │   ├── AddEditApplicationViewModel.swift
    │   ├── SettingsViewModel.swift
    │   └── AIParsingViewModel.swift
    │
    ├── Views/
    │   ├── Main/                      # Main navigation views
    │   ├── JobCard/                   # Card components
    │   ├── Detail/                    # Detail panel views
    │   ├── Forms/                     # Add/Edit forms
    │   ├── Settings/                  # Settings views
    │   └── Components/                # Reusable UI components
    │
    ├── Services/                      # Business logic services
    │   ├── AIService/                 # AI provider implementations
    │   │   ├── AIServiceProtocol.swift    # Protocol, error types, debug logger
    │   │   ├── WebContentFetcher.swift    # URL→text extraction (URLSession + WKWebView fallback)
    │   │   ├── AIResponseParser.swift     # JSON recovery, salary parsing, field mapping
    │   │   ├── AIServicePrompts.swift     # Standardized prompts for all providers
    │   │   ├── OpenAIService.swift        # GPT integration
    │   │   ├── AnthropicService.swift     # Claude integration
    │   │   └── GeminiService.swift        # Gemini integration
    │   ├── KeychainService.swift          # Secure API key storage (kSecClassGenericPassword)
    │   ├── PlatformDetectionService.swift # Job board URL detection & job ID extraction
    │   └── NotificationService.swift      # Follow-up reminder scheduling (UNUserNotification)
    │
    ├── Utilities/                     # Helpers and constants
    │   ├── DateFormatters.swift
    │   ├── URLHelpers.swift
    │   └── Constants.swift
    │
    └── Resources/
        └── Assets.xcassets/
```

## Key Patterns

### SwiftData Models

Models use `@Model` macro with private raw value storage for enums:

```swift
@Model
final class JobApplication {
    private var statusRawValue: String  // Store enum as String

    var status: ApplicationStatus {     // Computed property for type safety
        get { ApplicationStatus(rawValue: statusRawValue) ?? .saved }
        set { statusRawValue = newValue.rawValue }
    }
}
```

### ViewModels

ViewModels use `@Observable` macro (not ObservableObject):

```swift
@Observable
final class SomeViewModel {
    var someProperty: String = ""
}
```

In views, use `@State` for local ViewModel instances:
```swift
@State private var viewModel = SomeViewModel()
```

### Platform-Specific Code

Use conditional compilation for platform differences:

```swift
#if os(macOS)
// macOS-specific code
#else
// iOS-specific code
#endif
```

### Enums

All enums conform to `String, Codable, CaseIterable, Identifiable`:

```swift
enum SomeEnum: String, Codable, CaseIterable, Identifiable {
    case optionA = "Option A"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var icon: String { ... }
    var color: Color { ... }
}
```

## Important Files

| File | Purpose |
|------|---------|
| `Pipeline/PipelineApp.swift` | App entry, ModelContainer with CloudKit config |
| `Pipeline/Models/JobApplication.swift` | Core data model with all job fields |
| `Pipeline/Views/Main/MainView.swift` | Three-column NavigationSplitView layout |
| `Pipeline/Views/JobCard/JobCardView.swift` | Card displayed in the grid |
| `Pipeline/Views/Detail/JobDetailView.swift` | Right panel with full details |
| `Pipeline/Views/Forms/AddApplicationView.swift` | Modal with Manual/AI Parse tabs |
| `Pipeline/Services/KeychainService.swift` | Secure API key storage |
| `Pipeline/Services/AIService/AIServiceProtocol.swift` | AI service interface and helpers |
| `Pipeline/Services/AIService/WebContentFetcher.swift` | Extracts text from job posting URLs |
| `Pipeline/Services/AIService/AIResponseParser.swift` | JSON recovery and salary parsing |
| `Pipeline/Utilities/Constants.swift` | Design system, external URLs, UserDefaults keys, limits |

## Custom Values System

Users can add custom statuses, sources, and interview stages beyond the built-in options. These are stored in UserDefaults via helpers in `Constants.swift` and deduplicated case-insensitively.

## AI Parsing Pipeline

The AI parse flow works as follows:
1. **WebContentFetcher** extracts text from a job URL (URLSession primary, WKWebView fallback for JS-heavy sites)
2. **AIServicePrompts** wraps the content in a structured prompt requesting JSON output
3. Provider service (OpenAI/Anthropic/Gemini) sends request and gets raw response
4. **AIResponseParser** recovers valid JSON from the response (handles truncation, markdown fences, field name variants, salary formats)
5. Parsed data populates `AddEditApplicationViewModel` form fields

## Model Catalog

`SettingsViewModel` contains a nested `ModelCatalogService` that fetches live model lists from each AI provider's API. Results are cached for 24 hours. Models are filtered to only show relevant ones (e.g., GPT/O-series for OpenAI, Claude for Anthropic, Gemini with generateContent support).

## Common Tasks

### Adding a New Field to JobApplication

1. Add property to `Pipeline/Models/JobApplication.swift`
2. Update initializer
3. Add to `AddEditApplicationViewModel` form fields
4. Add to `ManualEntryFormView` form UI
5. Display in `JobDetailFieldsView` or `JobCardView`

### Adding a New Enum

1. Create file in `Pipeline/Models/Enums/`
2. Conform to `String, Codable, CaseIterable, Identifiable`
3. Add `displayName`, `icon`, `color` computed properties
4. If used in JobApplication, add private raw value storage + computed property

### Adding a New AI Provider

1. Create new service in `Pipeline/Services/AIService/` implementing `AIServiceProtocol`
2. Add case to `AIProvider` enum in `SettingsViewModel.swift`
3. Add to switch in `AIParsingViewModel.createAIService()`

### Adding a New View

1. Create in appropriate `Pipeline/Views/` subfolder
2. Use `@Environment(\.modelContext)` for data access
3. Use `@Query` for fetching SwiftData models
4. Pass bindings from parent for shared state

## Build & Run

1. Open `Pipeline/Pipeline.xcodeproj` in Xcode
2. Select signing team in project settings
3. Enable iCloud capability, select CloudKit container
4. Select target (My Mac or iOS Simulator)
5. Build and run (Cmd+R)

## Testing Checklist

- [ ] App launches without crash
- [ ] Can add new application (manual entry)
- [ ] Applications appear in grid
- [ ] Sidebar filters work with correct counts
- [ ] Can select and view application details
- [ ] Can edit application
- [ ] Can add interview log
- [ ] Interview stage indicator updates
- [ ] Status/priority menus work
- [ ] Theme toggle works (Settings)
- [ ] AI Parse works with valid API key

## SwiftData Notes

- Use `@Query` in views to fetch models
- Use `@Environment(\.modelContext)` for insert/delete/save
- Call `context.save()` after modifications (though often auto-saves)
- Relationships use `@Relationship` with delete rules
- CloudKit sync requires iCloud capability enabled

## Code Style

- Use Swift's native types (String, Int, Date, UUID)
- Prefer computed properties over methods for simple getters
- Use `guard` for early returns
- Mark classes as `final` unless inheritance needed
- Use `private` for internal implementation details
- Group related code with `// MARK: -` comments

## Changelog Guidelines

- When updating `CHANGELOG.md`, keep entries under `## [Unreleased]` grouped by feature/release context.
- If multiple commits refine the same feature in one release cycle, update a single existing bullet rather than adding many near-duplicate bullets.
- Write compact, user-facing summaries of outcomes; avoid implementation-by-implementation timeline bullets.
