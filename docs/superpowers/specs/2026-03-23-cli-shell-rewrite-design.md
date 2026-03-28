# ActiveRabbit CLI — Pure Shell Rewrite

## Overview

Replace the Ruby gem CLI (`activerabbit-cli`) with a pure POSIX shell script that can be installed with a single command:

```
curl -fsSL https://cli.activerabbit.ai/install.sh | sh
```

Zero runtime dependencies beyond `jq` (auto-installed by the installer).

## Goals

- One-command install on macOS, Linux, and WSL
- No Ruby/Node/Go dependency — pure `sh`
- Feature parity with the Ruby gem for v1 commands
- Clean, colorized terminal output

## Installer (`install.sh`)

**Hosted at:** `https://cli.activerabbit.ai/install.sh`

**Steps:**
1. Detect OS (`uname -s`) and arch (`uname -m`)
2. Reject native Windows (detect via `MSYSTEM`, `MINGW`, etc.) → print WSL instructions
3. Check for `curl` or `wget`
4. Install `jq` if missing:
   - macOS: `brew install jq`
   - Debian/Ubuntu: `apt-get install -y jq`
   - RHEL/Fedora: `yum install -y jq` or `dnf install -y jq`
   - Alpine: `apk add jq`
   - Arch: `pacman -S --noconfirm jq`
5. Determine install path:
   - `/usr/local/bin` if writable or sudo available
   - `~/.local/bin` as fallback (add to PATH if needed)
6. Download `activerabbit` script, set `chmod +x`
7. Print success message prompting `activerabbit login`

## CLI Script (`activerabbit`)

Single POSIX shell script (~600-800 lines).

### Config

- Location: `$XDG_CONFIG_HOME/activerabbit/config` (default: `~/.config/activerabbit/config`)
- Format: key=value
  ```
  api_key=ar_xxxxxxxxxxxx
  base_url=https://app.activerabbit.ai
  app=my-app-slug
  ```
- File permissions: `0600` (owner-only read/write)

### Commands (v1)

| Command | API Endpoint | Description |
|---------|-------------|-------------|
| `login` | POST validate | Interactive API key input, validate, save |
| `apps` | GET /api/v1/cli/apps | List all projects |
| `use-app <slug>` | — | Set default app in config |
| `status` | GET /api/v1/cli/apps/:slug/status | Health snapshot |
| `incidents` | GET /api/v1/cli/apps/:slug/incidents | List recent incidents |
| `show <id>` | GET /api/v1/cli/apps/:slug/incidents/:id | Incident detail |
| `explain <id>` | GET /api/v1/cli/apps/:slug/incidents/:id/explain | AI root cause analysis |
| `deploy-check` | GET /api/v1/cli/apps/:slug/deploy_check | Pre-deploy safety check |
| `doctor` | Multiple | Validate config, connectivity, app access |
| `version` | — | Print CLI version |
| `help` | — | Print usage |

### HTTP Client

- Wrapper around `curl` (preferred) or `wget` (fallback)
- Sets `X-Project-Token` header from config
- Sets `Content-Type: application/json` and `Accept: application/json`
- Timeout: 10s connect, 30s max
- Parses responses with `jq`

### Output Formatting

- Colorized output (ANSI escape codes)
- Auto-disable colors when piped (`! [ -t 1 ]`) or `NO_COLOR` is set
- Status icons: `●` (active), `✓` (pass), `✗` (fail), `◐` (pending)
- Severity badges: critical/high=red, medium=yellow, low=green

### Error Handling

| Condition | Message |
|-----------|---------|
| No API key | "Run `activerabbit login` first" |
| No app set | "Run `activerabbit use-app <slug>` first" |
| Network failure | "Could not connect to ActiveRabbit API" |
| HTTP 401 | "Invalid API key. Run `activerabbit login`" |
| HTTP 404 | "App not found" |
| HTTP 429 | "Rate limited. Try again shortly" |
| HTTP 5xx | "Server error. Try again later" |

## Deferred to v2

- `trace` command
- `--json` / `--md` output format flags
- Auto-update mechanism
- Shell completions (bash/zsh/fish)

## File Structure

```
script/
  cli/
    install.sh       # Installer script
    activerabbit     # CLI script
    test_cli.sh      # Test suite
```

## Testing

Shell-based test suite (`test_cli.sh`) that verifies:
- Config read/write
- Command routing
- Output formatting
- Error handling
- HTTP mocking (local test server or stubbed responses)
