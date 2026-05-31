# FOKS Bloomberg Terminal

Native macOS SwiftUI MVP for the FoKS private ops dashboard.

The original React prototype is preserved:

- `foks_dashboard.tsx`
- `SWIFT.txt`
- `Screenshot 2026-05-28 at 1.57.04 AM.png`

## Current Scope

Read-only native shell:

- project path and git status inspection
- process watchlist from `ps`
- LaunchAgent watchlist from `launchctl`
- recent FoKS log tail from local log files
- persistent font scaling via `@AppStorage`

No destructive commands are exposed from the UI.

## Run

```bash
cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
swift run FOKSTerminal
```

## Validate

```bash
cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
swift build
```

Expected result:

```text
Build complete!
```

## Architecture

```text
Core Scripts / Readers
-> Swift shell adapter
-> SystemReader
-> SwiftUI interface
-> Manual refresh trigger
-> AI and automation later
```

Manual read-only inspection is the stop condition for this MVP. Script execution, AI command routing, and Home Assistant actions should be added only after the live read layer is stable.
