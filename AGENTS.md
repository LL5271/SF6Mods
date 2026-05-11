# AGENTS — SF6Mods

## Repo purpose

Lua mods for Street Fighter 6 via REFramework.

## Commit workflow

**Always commit from within this repo** (`~/winhome/Documents/SF6Mods/`). The pre-commit hook at `.githooks/pre-commit` automatically copies the latest content from `reframework/autorun/` for each tracked file before every commit. This ensures autorun edits are always reflected in what gets pushed.

```
cd ~/winhome/Documents/SF6Mods
# edit files in reframework/autorun/
git commit -m "..."    # hook syncs latest autorun content
git push
```

## File status map

| Status | Files | Edit behavior |
|--------|-------|--------------|
| **Tracked** (git), synced from autorun at commit | `attack_info.lua`, `attack_history.lua`, `better_disp_hitboxes.lua`, `better_info_display.lua`, `replay_id_to_clipboard.lua` | Edit in `reframework/autorun/` — hook pulls latest before commit. Direct edits here get overwritten on next commit. |
| **Symlink** (untracked) | Everything else: `random_costume.lua`, `func/`, `Hotkeys/`, `MMDK/`, `test.lua`, etc. | Edits here directly modify `autorun/` originals. |
| **Symlink (tracked on remote)** | `README.md` | Remote has the real file; local copy is a symlink. Dereference (`cp -L`) before editing if you need to commit README changes. |

## Pre-commit hook setup (one-time, per clone)

```bash
git config core.hooksPath .githooks
```

## Gotchas

- `create_links.ps1` re-creates Windows-native symlinks from `autorun/` to here. **Gitignored — never track it.**
- To add a new tracked file: copy content from autorun, don't symlink. `cp -L autorun/new_mod.lua .` then add the hook entry.
- No tests, no CI/CD. Standard git flow, push to `origin/main`.
- Related parent workspace at `reframework/` has its own `AGENTS.md` with SF6 dump/WebSocket/hook guidance (not used by this standalone repo).
