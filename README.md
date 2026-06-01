# FOKS Terminal

Apple-native operational command center for local read-only diagnostics, project visibility, launchd inspection, logs, daily operations reporting, and advisory AI analysis.

Source of truth:

```bash
/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
```

Runtime hardware:

```text
Read live from sysctl and sw_vers. The app does not display hardcoded hardware or OS metrics.
```

## Scope

This version is intentionally read-only:

- project inventory from `config/projects.json`
- git health inspection with `/usr/bin/git`, including dirty-file previews
- project health scores, last activity, dependency markers, and repository warnings
- system facts from `sysctl`, `sw_vers`, `uptime`, `vm_stat`, `df`, `netstat`, and `ps`
- app-scoped Apple performance payloads from MetricKit, stored locally as JSON
- process watchlist from `/bin/ps`
- LaunchAgent and LaunchDaemon inspection from local launchd/plist state
- FoKS, project, and system log aggregation from allowlisted local paths
- Dashboard, Projects Center, System Center, Logs Center, Action Center, Fix Queue, and Daily Ops Report
- Apple Metrics view for MetricKit subscriber state, stored payloads, diagnostics, launch measurement, and signpost coverage
- Action Center with prioritized operational issues
- in-memory health trend tracking across refreshes in the active session
- Daily Ops Report export as Markdown or plain text
- Fix Queue with copy-only manual command cards and read-only Run Check buttons
- AI provider selector on Analyze, with local Ollama analysis by default and optional cloud analysis through explicit environment configuration

No cloud calls unless Cloud AI is explicitly selected, no auto-fix execution, no destructive command buttons, and no stored API keys.
The AI advisor sends a compact diagnostic bundle to the selected provider and renders advice only.
Run Check buttons execute explicit binaries with explicit arguments through the timeout runner; they do not execute shell snippets.

The command runner rejects non-absolute executables and shell trampolines such as `/bin/zsh`, `/bin/bash`, `/bin/sh`, and `/usr/bin/env`.

## Apple Metrics

FOKS Terminal subscribes to `MXMetricManager` at app launch and stores received MetricKit payloads locally:

```bash
/Users/eduardofgiovannini/Library/Application Support/FOKSTerminal/MetricKit
```

MetricKit payload delivery is system-managed and normally daily. Empty payload counts mean the system has not delivered app-specific reports yet; the app does not fabricate replacement data.

Instrumented signposts:

```text
AppLaunch
FOKSTerminalInitialRefresh
DashboardRefresh
LocalAIAnalysis
ReadOnlyCheck
AutomationRun
AppBundleOpen
ProjectSync
```

## Data Integrity

No fake metrics are allowed:

- no hardcoded runtime hardware profile
- no fallback project inventory if `config/projects.json` is missing or invalid
- no synthetic log entries
- failed metric reads display as `unavailable`, not `0%`
- missing MetricKit payloads display as `WAITING`, not as synthetic performance reports
- health scores come only from the current local snapshot

## Run

```bash
cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
swift run FOKSTerminal
```

## Build .app

```bash
cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG
./scripts/build_app.sh
open /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG/dist/FOKSTerminal.app
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

## AI Analysis

Analyze has a provider dropdown:

- Local AI uses Ollama at `http://127.0.0.1:11434/api/generate` and the selected local model.
- Cloud AI sends the same compact diagnostic bundle to an OpenAI-compatible HTTPS chat completions endpoint only when these environment variables are present:

```bash
export FOKS_CLOUD_AI_ENDPOINT="https://api.example.com/v1/chat/completions"
export FOKS_CLOUD_AI_API_KEY="..."
export FOKS_CLOUD_AI_MODEL="..."
```

Cloud keys are not stored by the app. Missing or invalid cloud configuration fails before a request is sent.

## Architecture

```text
Core models and parsers
-> explicit async command runner
-> system/project/log readers
-> dashboard snapshot and scoring
-> incident aggregation
-> action center and fix queue
-> daily ops report builder
-> MetricKit telemetry collector and local payload store
-> advisory AI provider selector
-> local Ollama advisor or explicit cloud advisor
-> SwiftUI command center
```

See the detailed implementation architecture:

```bash
/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG/docs/NEXT_GENERATION_ARCHITECTURE.md
```

Guarded fix execution is intentionally out of scope. The current AI layer is advisory only.
