---
name: diagnose-mojibake-utf8-console
description: Decode and diagnose UTF-8 mojibake in console output by mapping bytes through legacy encodings
pattern_type: debugging_techniques
learned_at: 2026-06-23T01:27:48
source_session: 62967f82-4d8e-478a-8c62-ed51c7500dd8
---

## When to use

When terminal/console output shows corrupted characters (`âûê`, `âûÇ`, etc.) from applications that emit UTF-8 — especially TUIs using Unicode block-drawing characters (`█`, `▀`, `▄`, etc.) or bullets (`•`, `○`, etc.).

## How

1. Identify what characters the application is trying to display (from source code, context, or correct output screenshots)
2. Find the UTF-8 byte sequence for the intended character:
   - Example: `█` (U+2588 FULL BLOCK) = bytes `E2 96 88`
3. Map each byte individually through a single-byte encoding (CP437, Latin-1, or Windows-1252):
   - `E2` → `â`, `96` → `û`, `88` → `ê` in Latin-1 / Windows-1252
4. Compare against the broken characters on screen — if they match, UTF-8 bytes are being read as single-byte characters
5. Root cause is always one of:
   - **Kernel/VT not in UTF-8 mode**: add `vt.default_utf8=1` to kernel cmdline or run `stty iutf8`
   - **Console missing Unicode font**: configure `/etc/vconsole.conf` with `FONT=Lat2-Terminus16` or similar, and ensure `kbd` / `kbd-consolefonts` packages are installed
   - **Locale not set to UTF-8**: export `LANG=C.UTF-8` or `en_US.UTF-8` in shell environment

## Example

Opencode TUI splash showed `âûêâûÇ` instead of block-drawing characters. Decoding:
- `â û ê` decodes to UTF-8 bytes `E2 96 88` → U+2588 FULL BLOCK (`█`)
- `â û Ç` decodes to UTF-8 bytes `E2 96 80` → U+2580 UPPER HALF BLOCK (`▀`)

Conclusion: console VT was reading UTF-8 byte streams as CP437/Latin-1 single-byte characters, indicating missing UTF-8 mode, Unicode font, or locale configuration.
