# TinyWin architecture

TinyWin treats each slimming action as an independent Entry. A build is the result of selecting Entry IDs, resolving their dependencies and conflicts, and executing a normalized plan against an offline Windows image.

```text
TinyWin.WinUI (Entry catalog, checkboxes, MVVM)
        |
TinyWin.Host (process boundary and argument forwarding)
        |
scripts/build.ps1 (command adapter)
        |
TinyWin PowerShell module
  Entry catalog -> normalized plan -> handler dispatch
        |
entry-handlers (Appx, Registry, DISM, custom operations)
        |
DISM / offline registry / Windows imaging cmdlets
```

## Boundaries

| Layer | Responsibility | Must not do |
| --- | --- | --- |
| `TinyWin.WinUI` | Discover Entry metadata, let users select entries, show logs and status, invoke `scripts/build.ps1` | Call DISM, modify a WIM, or interpret handler parameters |
| `TinyWin.Host` | Locate the checkout and relay arguments to `pwsh` | Contain slimming policy or UI logic |
| `scripts/build.ps1` | Map process arguments to the module public API | Implement image operations or selection rules |
| `src/TinyWin/Public` | Expose catalog, plan and build APIs | Depend on WinUI types |
| `src/TinyWin/Private` | Load and validate entries, resolve plans, coordinate handlers and media lifecycle | Be called by UI or external automation |
| `entries` | Versioned metadata and declarative parameters | Contain executable code or source paths |
| `entry-handlers` | Implement complex, reusable image mutations | Read arbitrary script paths from Entry JSON |

## Entry contract

Each JSON entry contains:

```text
schemaVersion, id, version, title, description, category, risk,
handler, phase, parameters, optional requires/conflicts
```

`id` is stable and globally unique. `handler` is resolved through a module-owned allowlist. `parameters` is data only. A new item that uses an existing handler requires only a new JSON file; a new behavior adds one handler and its tests without changing the build workflow.

The process-facing adapter accepts comma-separated Entry IDs in one `-EntryId` argument. The module API accepts a `string[]`, so hosts and automation can retain structured selections.

Complex implementations live under `entry-handlers/`. Their metadata remains in `entries/`, preserving the separation between model/data and executable code.

## Desktop delivery

The WinUI application is a self-contained Windows App SDK deployment. Its Release configuration uses Native AOT, trimming, stripped symbols, and speed-oriented native-code optimization. A released MSIX therefore runs without a separately installed .NET SDK, .NET runtime, or Windows App Runtime. The UI launches `pwsh scripts/build.ps1` directly so the optional .NET Host stays an independent command-line adapter rather than a desktop-app dependency.

## Plan lifecycle

1. `Get-TinyWinEntry` scans and validates every Entry JSON.
2. `New-TinyWinBuildPlan` resolves requested Entry IDs, dependencies, conflicts and deterministic operation order.
3. `Invoke-TinyWinBuild` validates the environment, prepares media and mounts a single-index WIM.
4. `Invoke-TinyWinEntryPlan` dispatches each operation to its registered handler and records status.
5. The image is saved, optimized and optionally converted to a bootable ISO.
6. The manifest records selected Entry IDs, versions, source hashes, operation results, events and the final WIM hash.

The plan is generated before the first mutation, so `-WhatIf` can validate selection without creating `out/` or mounting media.

## Extensibility rules

- Keep Entry JSON declarative and small.
- Prefer reusing a handler with different parameters.
- Add a dedicated handler for behavior that cannot be represented safely as data.
- Declare dependencies and conflicts in Entry metadata instead of embedding them in the UI.
- Keep handlers idempotent where Windows servicing allows it and return structured operation details.
- Put source media, workspaces and generated output only under the ignored `raw/` and `out/` directories.
