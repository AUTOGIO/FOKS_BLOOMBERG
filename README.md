# FOKS Terminal

Fresh Apple-native FoKSTerminal for local read-only operations.

Source of truth:

```bash
/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
```

Target profile:

```text
MacBook Air | Apple M4 | 8 cores | 16 GB | macOS 26.6
```

## Scope

This version is intentionally read-only:

- project inventory from `config/projects.json`
- git health inspection with `/usr/bin/git`, including dirty-file previews
- hardware overview from `sysctl`, `sw_vers`, and `uptime`
- process watchlist from `/bin/ps`
- LaunchAgent watchlist and failure analysis from `/bin/launchctl`
- recent FoKS logs from allowlisted local log paths
- Action Center with prioritized operational issues
- Fix Queue with copy-only manual command cards
- local AI advisor through Ollama's `127.0.0.1:11434` HTTP API for diagnostic analysis and fix planning

No cloud calls, no auto-fix execution, no destructive command buttons, and no stored API keys.
The AI advisor sends a compact local diagnostic bundle to an installed Ollama model and renders advice only.

## Run

```bash
cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
swift run FOKSTerminal
```

## Validate

```bash
cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
./scripts/validate.sh
```

Expected result:

```text
PASS swift build
PASS swift test
```

## Configuration

Edit the local project inventory here:

```bash
/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG/config/projects.json
```

Schema:

```json
{
  "projects": [
    {
      "id": "foks",
      "shortName": "FOKS",
      "displayName": "FOKS Bloomberg Terminal",
      "path": "/absolute/path",
      "group": "OPS",
      "enabled": true
    }
  ]
}
```

Disabled projects are ignored. Missing paths are rendered as explicit `MISSING` states.

## Architecture

```text
Core readers
-> async command runner
-> parser layer
-> dashboard snapshot
-> action center and fix queue
-> SwiftUI read-only interface
-> manual refresh trigger
-> local Ollama advisor
```

Guarded fix execution remains a future phase; the current AI layer is advisory only.
