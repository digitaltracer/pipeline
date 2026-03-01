# Pipeline Workflow

## What the app does

Pipeline is a SwiftUI app for tracking job applications from first save to final outcome. It lets you:

- add applications manually or by AI parsing from a job URL
- track status, priority, source, platform, compensation, and interview stage
- log interview history and notes per application
- schedule local follow-up reminders
- configure AI providers and models for parsing

The app is local-first. Core data is stored with SwiftData, API keys are stored in Keychain, and preferences/custom lists are stored in UserDefaults.

## Architecture at a glance

```mermaid
flowchart LR
    User["User"] --> UI["SwiftUI Views"]
    UI --> VM["Observable ViewModels"]

    VM --> SD[("SwiftData\nJobApplication and InterviewLog")]
    VM --> UD[("UserDefaults\nappearance, filters, models, custom values")]
    VM --> KC[("Keychain\nprovider API keys")]
    VM --> NS["NotificationService"]
    NS --> UNC[("UNUserNotificationCenter")]

    VM --> AIS["AIServiceProtocol"]
    AIS --> WEB["Fetch Job URL HTML"]
    AIS --> API{{"AI Provider APIs\nOpenAI, Anthropic, Gemini"}}
    API --> AIS
```

## Startup and shell workflow

### Lifecycle summary

1. `PipelineApp` creates a `ModelContainer` with schema:
   - `JobApplication`
   - `InterviewLog`
2. Cloud sync mode is read from the saved `cloudSyncEnabled` preference:
   - `true`: private CloudKit database with `iCloud.com.pipeline.app`
   - `false`: local-only store
   - changes are applied on next launch
3. `ContentView` loads applications via `@Query` sorted by `updatedAt` descending.
4. Platform-specific shell renders:
   - macOS: split-view app shell (`Sidebar` -> list content -> detail)
   - iOS: `NavigationStack` list + add sheet flow

```mermaid
flowchart TD
    A["App Launch"] --> B["PipelineApp init"]
    B --> C["Create SwiftData schema and ModelContainer"]
    C --> D{"cloudSyncEnabled preference true?"}
    D -->|"Yes"| E["Use private iCloud container"]
    D -->|"No"| F["Use local-only SwiftData store"]
    E --> G["Render ContentView"]
    F --> G
    G --> H{"Platform"}
    H -->|"macOS"| I["MainView with split navigation"]
    H -->|"iOS"| J["NavigationStack list flow"]
```

## Core user workflow

### Browse, filter, and inspect

- `ApplicationListViewModel` applies:
  - sidebar status filter
  - text search on company/role/location
  - sort order (updated, created, company, applied date, priority)
- Stats are derived on the fly from current in-memory query results.
- Selecting a card opens `JobDetailView` for status/priority edits, interview history, and destructive actions.

### Add or edit application

`AddEditApplicationViewModel` owns form state and validation. On save it:

1. validates required fields and URL/salary rules
2. normalizes URL and auto-detects platform when possible
3. inserts or updates `JobApplication` in SwiftData
4. syncs reminder state via `NotificationService`

```mermaid
flowchart TD
    A["User opens Add Application"] --> B{"Entry mode"}
    B -->|"Manual Entry"| C["Fill form fields"]
    B -->|"AI Parse"| D["Parse URL and review extracted fields"]
    D --> E["Apply parsed data to form"]
    E --> C

    C --> F["Tap Save"]
    F --> G["Validate fields"]
    G --> H{"Valid"}
    H -->|"No"| I["Show validation errors"]
    H -->|"Yes"| J["Create or update JobApplication"]
    J --> K["Save to SwiftData"]
    K --> L["Sync follow-up reminder"]
    L --> M["Dismiss sheet"]
```

## AI parsing workflow

The parsing path is provider-aware and resilient to inconsistent model output.

1. `AIParsingViewModel` refreshes configured providers based on saved API keys.
2. URL is normalized and validated (`http/https` only).
3. API key is loaded from Keychain for the selected provider.
4. Provider service fetches HTML from the job URL, strips markup, truncates content, and sends a strict JSON extraction prompt.
5. `AIResponseParser` repairs/normalizes model output and maps aliases into `ParsedJobData`.
6. User applies parsed data back into the manual form view model.

```mermaid
sequenceDiagram
    actor User
    participant ParseView as AIParseFormView
    participant ParseVM as AIParsingViewModel
    participant Settings as SettingsViewModel
    participant Keychain as KeychainService
    participant Service as Provider Service
    participant Site as Job URL
    participant Provider as AI API
    participant Parser as AIResponseParser
    participant FormVM as AddEditApplicationViewModel

    User->>ParseView: Enter URL and tap Parse
    ParseView->>ParseVM: parseJobURL()
    ParseVM->>Settings: refreshConfiguration()
    ParseVM->>ParseVM: normalize and validate URL
    ParseVM->>Keychain: getAPIKey(parseProvider)
    Keychain-->>ParseVM: API key
    ParseVM->>Service: create provider service
    Service->>Site: GET job posting page
    Site-->>Service: HTML content
    Service->>Provider: Structured extraction prompt
    Provider-->>Service: JSON-like output
    Service->>Parser: parseJobData(output)
    Parser-->>ParseVM: ParsedJobData
    ParseVM-->>ParseView: parsedData or error
    User->>ParseView: Apply and continue
    ParseView->>ParseVM: applyToViewModel(formVM)
    ParseVM->>FormVM: Copy company, role, location, salary, description, URL
```

## Reminder synchronization workflow

Reminders are local notifications keyed by `followup-<application-id>-...`.

- When application data changes, reminder sync runs for that application.
- When notification settings change, reminder sync runs for all applications.
- Archived items, missing follow-up dates, and past dates clear pending reminders.

```mermaid
flowchart TD
    A["Trigger: save app or change notification settings"] --> B["NotificationService sync"]
    B --> C{"Notifications enabled"}
    C -->|"No"| D["Remove pending reminder notifications"]
    C -->|"Yes"| E{"Application eligible for reminder"}
    E -->|"No"| D
    E -->|"Yes"| F{"Reminder timing"}
    F -->|"Day Before"| G["Schedule 9 AM on day before"]
    F -->|"Morning Of"| H["Schedule 9 AM on follow-up day"]
    F -->|"Both"| I["Schedule both notifications"]
```

## Data model relationship

```mermaid
erDiagram
    JOB_APPLICATION ||--o{ INTERVIEW_LOG : has

    JOB_APPLICATION {
        UUID id
        string companyName
        string role
        string location
        string statusRawValue
        string priorityRawValue
        string sourceRawValue
        string platformRawValue
        string interviewStageRawValue
        int salaryMin
        int salaryMax
        date appliedDate
        date nextFollowUpDate
        date createdAt
        date updatedAt
    }

    INTERVIEW_LOG {
        UUID id
        string interviewTypeRawValue
        date date
        string interviewerName
        int rating
        string notes
    }
```

## Settings and persistence behavior

- `SettingsViewModel` persists:
  - appearance mode
  - selected AI provider/model
  - fetched model catalogs per provider (with refresh timestamps)
  - notification switches and reminder timing
- `CustomValuesStore` persists custom statuses, sources, and interview stages.
- Model catalogs are refreshed from provider APIs when needed or on manual refresh.
- API keys are never stored in UserDefaults; only in Keychain.

## Platform UX differences

- **macOS**
  - split-view layout with sidebar filters, card grid, and optional detail column
  - add/edit/settings are presented as sheets with custom desktop styling
- **iOS**
  - list-first `NavigationStack` flow
  - add/edit/settings use native mobile form/navigation patterns
