---
name: docker-credential-helper-macos-headless
description: Resolve Docker credential helper lockout on macOS headless sessions
pattern_type: error_resolution
learned_at: 2026-06-22T21:51:56
source_session: 701c6df9-3e57-48d3-83b1-c6853651133e
---

## When to use
When `docker pull` fails with error `keychain cannot be accessed because the current session does not allow user interaction` on macOS in non-interactive environments (scripts, background processes, headless shells).

## How
**Option 1 (one-time unlock):** Unlock the keychain in an interactive terminal before running Docker commands:
```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

**Option 2 (avoid pulls entirely):** Build images from locally cached base images and avoid `docker pull` in headless scripts. Pre-pull any needed images interactively first.

**Option 3 (for CI/cloud):** Run Docker builds in a cloud environment or CI system where registry auth is configured independently (not tied to local macOS keychain).

## Why
Docker Desktop on macOS stores registry credentials in the login keychain via `credsStore: desktop` in `~/.docker/config.json`. The credential helper runs server-side in the Docker daemon and cannot unlock the keychain interactively in headless sessions. CLI-level workarounds (env vars, `--config` flags) don't help because the lockout happens in the daemon, not the CLI layer.
