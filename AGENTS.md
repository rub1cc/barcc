# AGENTS.md

Guide for agentic coding assistants working in this repo.
Keep changes small, idiomatic Swift, and consistent with existing style.

## Project snapshot
- Swift Package Manager executable (macOS menu bar app).
- Minimum macOS: 14.0; Swift tools: 5.9.
- Entry point: `Sources/barcc/main.swift`.
- UI: SwiftUI + AppKit; data parsing in `StatsParser`.
- Resources in `Resources/` (Info.plist, AppIcon.icns).

## Build / Run / Test / Lint
### Build
- Debug build: `swift build`.
- Release build: `swift build -c release`.
- Full app bundle: `./scripts/build.sh bundle`.
- Release binary only: `./scripts/build.sh build`.
- Unsigned DMG: `./scripts/build.sh unsigned`.
- Signed/notarized pipeline: `./scripts/build.sh all`.
- Signing env vars: `SIGNING_IDENTITY`, `APPLE_ID`, `TEAM_ID`, `APP_PASSWORD`.

### Run
- Run from SwiftPM: `swift run barcc` (launches menu bar app).
- Run bundled app: `open dist/barcc.app` (after `./scripts/build.sh bundle`).

### Test
- There are currently no SwiftPM test targets.
- If tests are added: `swift test`.
- List tests: `swift test --list-tests`.
- Single test (SwiftPM): `swift test --filter <TargetName>/<TestCase>/<testName>`.
- Example: `swift test --filter BarccTests/StatsParserTests/testLoadStats`.

### Lint / Format
- No lint or formatter is configured in this repo.
- If you add SwiftLint or SwiftFormat, document the command here.

## Code style and conventions
### Imports
- Import only what you use; no unused imports.
- Prefer one import per line.
- Keep primary UI frameworks first (`SwiftUI` or `AppKit`), then supporting frameworks (`Combine`, `Charts`, `UniformTypeIdentifiers`, etc.).
- Non-UI files typically import `Foundation` only.

### Formatting
- Indentation: 4 spaces.
- Opening brace on the same line as the declaration.
- Use trailing commas in multiline literals and argument lists.
- Keep spaces around binary operators.
- Align chained modifiers vertically in SwiftUI.
- Blank lines separate logical blocks (e.g., state, lifecycle, helpers).
- Use `// MARK: -` sections to group large files.
- Keep SwiftUI view hierarchies readable; split into smaller views when a body grows.

### Types and structure
- `struct` for views and value types; `class` for shared mutable state.
- `StatsParser` is the central `ObservableObject` for usage data.
- Use `@Published` for state that drives UI updates.
- Prefer `let` over `var` unless mutation is required.
- Favor computed properties for derived values (see `totalTokens`).
- Keep helper types near their usage unless they are reused across files.

### Naming
- Types: UpperCamelCase (`MenuBarView`, `StatsParser`).
- Members: lowerCamelCase (`todayStats`, `loadStats`).
- Enum cases: lowerCamelCase (`summary`, `daily`).
- Keep abbreviations consistent: `id`, `url`, `json`, `iso`.
- Use descriptive names over short/cryptic ones.

### Error handling
- Prefer `guard` with early returns for invalid state or missing data.
- Use `try?` for best-effort parsing where failures are acceptable.
- If an error impacts UI or correctness, surface it (log or user feedback) instead of silently ignoring.
- Avoid throwing across SwiftUI view boundaries.

### Concurrency and UI
- Update UI-related state on the main thread.
- Use `@MainActor` for methods that touch AppKit/SwiftUI.
- Avoid long-running work on the main thread; move heavy parsing off the UI thread if expanded.
- Timed refresh uses a `Timer` (see `setupPolling`).
- Keep Combine subscriptions weak where they capture `self`.

### Data parsing and pricing
- JSONL parsing uses `JSONDecoder` and `ISO8601DateFormatter`.
- Deduplicate by `messageId:requestId` (matches Claude Code behavior).
- Pricing is centralized in `StatsParser` with a default fallback model.
- Keep model pricing tables together and documented.
- Prefer `NumberFormatter` for user-facing token counts.

### SwiftUI patterns used here
- Use `@ObservedObject` for the shared `StatsParser` in views.
- Use `@State` for transient view state (hover, selected tab, animation triggers).
- Prefer `VStack/HStack` with explicit alignment and spacing.
- Keep reusable view components (`CardSection`, `SectionHeader`, etc.) in the same file for now.
- Favor `.font(.system(...))` for consistent typography.
- Use `.foregroundColor(.secondary...)` for supporting text.
- Use `.help(...)` on toolbar-style buttons when appropriate.

### AppKit integration
- The menu bar item and popover are owned by `AppDelegate`.
- Avoid strong reference cycles in Combine subscriptions; use `[weak self]`.
- Use `NSImage` system symbols and `SymbolConfiguration` for icons.
- Provide `accessibilityDescription` for symbols.

### Resources
- `Resources/Info.plist` is copied into the app bundle via `Package.swift`.
- If you add resources, update `Package.swift` with `.copy(...)`.
- App icon lives at `Resources/AppIcon.icns`.

### Distribution notes
- The build script writes to `dist/` and may remove/recreate it.
- Notarization uses `xcrun notarytool`; keep credentials out of git.
- DMG packaging uses `hdiutil` and `xattr` to clear quarantine.
- Treat `dist/` artifacts as generated output unless explicitly releasing.

### File system usage
- Claude logs are read from `~/.claude/projects`.
- Always check path existence before enumerating files.
- Treat file reads as best-effort and keep UI responsive.

### Testing conventions (if added)
- Use XCTest and place tests under `Tests/BarccTests/`.
- Name test classes with `*Tests` and test methods with `test...`.
- Keep tests deterministic; avoid real network or time-dependent data.
- If time is needed, inject dates rather than using `Date()` directly.
- Prefer small unit tests around `StatsParser` helpers.

### Logging and diagnostics
- There is no logging framework configured.
- If logging is needed, consider `Logger` from `os` and keep output minimal.
- Do not log user data or file contents by default.

## Repo layout
- `Sources/barcc/main.swift`: app entry point.
- `Sources/barcc/AppDelegate.swift`: status bar + popover wiring.
- `Sources/barcc/MenuBarView.swift`: SwiftUI UI and subviews.
- `Sources/barcc/StatsParser.swift`: JSONL parsing and stats aggregation.
- `Sources/barcc/StatusBarIcon.swift`: status bar icon helpers.
- `scripts/build.sh`: packaging/signing/notarization script.

## Cursor / Copilot rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.
- If any of these files are added later, mirror their rules here.

## Agent expectations
- Keep changes focused and consistent with existing style.
- Prefer adding tests before refactors that change behavior.
- Do not introduce new dependencies without a clear reason.
- Avoid breaking the macOS 14+ requirement.
- Update this file if build/lint/test commands change.
- When in doubt, follow existing patterns in `Sources/barcc`.
