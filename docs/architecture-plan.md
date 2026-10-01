# Architecture improvement plan

The app keeps AppKit and its existing black launcher design. The bundle identifier, saved shortcuts, usage history, and display placement remain compatible.

## Work and acceptance

| Work | Implementation | Required evidence |
| --- | --- | --- |
| Window updates | Small AX adapter and queue-owned operation engine; one frame budget; detect repeated constrained responses | Fake delayed/clamped/rejected windows, restore and permission checks; native fixture |
| Catalog | Publish and save changed snapshots only; separate refresh completion; classify bundle events for icon invalidation | Initial empty/cache-equal completion, unchanged snapshots, metadata-only and icon-only events; real FSEvents |
| Icons | Main-actor cache with bounded pending work; worker loads immutable pixels; path/token checks discard stale completions | Coalescing, invalidation during load, identity, and cache/work limits |
| Launcher | Small main-actor state model; render only changed results; retain native input, placement, and blank opening | Query/filter/selection/history transitions and native launcher checks |
| Concurrency | Testable CielApp library and separate executable; explicit UI ownership and worker boundaries; strict checking | Clean compiler diagnostics and universal compilation |
| Performance | Standard tests; separate release benchmark; signposts and native diagnostic report | Configurable regression budgets, first and repeated query timings, idle CPU and session memory samples |

The integration review checks all boundaries together. No extra framework or database is needed. A full catalog scan remains the fallback for dropped or ambiguous filesystem events. A faster search-selection algorithm is added only if measurements justify it.

## Code structure

`CielCore` contains pure search, discovery, history, geometry, and placement code. `CielApp` contains the AppKit app and its testable state and adapters. `Ciel` is a small executable entry point. `CielBenchmarks` is a separate release benchmark executable. Swift Testing discovers tests in both test targets.

`LauncherState` owns query, category, results, and selection. `LauncherView` applies the reported changes to native controls. A query that produces the same results does not rebuild table rows. Catalog and history updates preserve the selected entry when it remains available.

`AppCatalog` owns the current snapshot on the main actor. `CatalogScanWorker` scans and saves on a serial queue. Refresh completion is independent of changed entries. This permits empty or cache-equal startup to complete without a false change notification. Filesystem events also identify icons that need invalidation. Event bursts have a two-second maximum debounce delay. Full scans retain nested discovery and bundle identifier deduplication.

`IconCache` owns cache entries and request tokens on the main actor. Worker tasks retrieve and draw icons. Only immutable `CGImage` pixels return to the main actor. Default limits are 80 cached icons, 4 MiB of pixel data, 64 pending requests, and two concurrent loads. A cell checks its entry and path before it applies an icon. Invalidated request tokens cannot repopulate the cache.

`WindowController` pins the captured window selection before it awaits work. A custom serial executor confines synchronous AX calls and engine state. The engine uses one 500 ms frame budget for updates, retries, polling, and boundary corrections. Fast commands send size-position-size without an intermediate wait. Delayed and constrained responses are covered by injected adapters and clocks.

## Repeatable checks

```sh
bash scripts/check.sh --unit-only
bash scripts/check.sh
```

The first command checks formatting, metadata, shell syntax, discovered tests, and release search budgets. The second also builds an isolated diagnostic app and runs native launcher, filesystem, screenshot, and performance checks. It does not install the app.

```sh
bash scripts/benchmark.sh --output .build/performance/search-engine.json
bash scripts/benchmark.sh --baseline .build/performance/previous-search-engine.json
```

The release benchmark covers 12 query cases at 1,000 and 10,000 synthetic apps. It includes broad queries, typing errors, multiple words, and no matches. Each case records median, p95, maximum, result validity, and its budget. The default absolute p95 allowance is 100 ms per 1,000 apps. This is a broad guard against severe regressions on shared CI machines. A saved passing report permits a tighter comparison: four times its p95, with a 1 ms floor. Use the same hardware, toolchain, and settings for comparisons. Budget failures return a nonzero status and still write the report. `CIEL_BENCHMARK_P95_MS_PER_1000` changes the absolute allowance.

The local native report is `.build/performance/native-ui.json`. Its defaults cover 300 query changes and five idle seconds. It checks startup, query layout/display submission, idle CPU, and resident growth. `CIEL_NATIVE_CYCLES` and `CIEL_NATIVE_IDLE_SECONDS` extend the workload. `CIEL_NATIVE_MAX_P95_MS`, `CIEL_NATIVE_MAX_STARTUP_MS`, `CIEL_NATIVE_MAX_IDLE_CPU_PERCENT`, and `CIEL_NATIVE_MAX_GROWTH_MIB` set its limits.

In Instruments, select Ciel and inspect the `Performance` signposts for `Search`, `LauncherUpdate`, `CatalogScan`, `WindowOperation`, and `NativeQueryDisplay`. Native checks require a desktop session. Hosted CI runs unit tests with compiler warnings treated as errors, release search budgets, and universal compilation. It saves the search report and development app as artifacts.

## Measurement limits

Search benchmarks measure the engine only. Native diagnostic timing measures app entry to readiness, query to layout/display submission, and settling asynchronous icons. It does not measure physical keypress-to-display latency. Instruments signposts support manual analysis of that full interaction. Resource measurements describe the recorded session; they do not prove an absence of leaks over every workload.

A frame-operation deadline limits retries and polling. Minimize uses a one-second budget. Synchronous Accessibility IPC cannot be cancelled after dispatch. Each message also has a timeout. Enhanced UI restoration has a separate best-effort 50 ms cleanup timeout. A delayed app can be indistinguishable from a constrained intermediate frame, so early classification requires a repeated response. Apps that defer a later frame after a long stable intermediate frame remain a limit of this heuristic.

## Research

- [Swift incremental concurrency migration](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/migrationstrategy/) supports explicit isolation and gradual compiler checking.
- [Swift Testing](https://developer.apple.com/documentation/testing) provides discovered tests and expectation reporting.
- [Apple icon retrieval](https://developer.apple.com/documentation/appkit/nsworkspace/icon%28forfile%3A%29) permits calling `icon(forFile:)` from any thread.
- [Apple image thread safety](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html) permits image creation and drawing on one thread, followed by handoff.
- [Accessibility message timeouts](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) bound individual AX calls.
- [Performance signposts](https://developer.apple.com/documentation/os/recording-performance-data) mark intervals for Instruments.
- [Native display submission](https://developer.apple.com/documentation/appkit/nsview/displayifneeded%28%29) invokes drawing for invalidated views.
