# Journal/save review for Sprint 29

Reviewed repository: `herringchrisindependentcons-wq/tidewrack-backup-personal`.
This review describes the checked-in code, not an independently verified shipping build.

## What survived before this change

Pause > Save sets `GameState.current_scene` to the active scene's path, then writes
`version: 1`, `scene`, and the entire `flags` dictionary to `user://save.json`.
Main Menu > Continue checks file existence, loads that dictionary, and changes scenes.

| State | Original behavior | With this change |
|---|---|---|
| Story flags | All flags saved, including false values | Same keys and values; no journal-to-flag conversion |
| Resume scene | Scene path saved; level rebuilt | Same behavior; only known gameplay scenes accepted |
| Journal | Unregistered scaffold; no callers or persistence | Registered facade, ordered unique IDs persisted in v2 |
| New Game | Clears flags; retains disk save | Also clears journal; disk still retained until next Save |
| Position, interactable `_used` | Reset when scene rebuilt | Still reset |
| Active dialogue/choice cursor | Not saved; pause blocked during dialogue | Still not saved |
| Volume/fullscreen | Runtime settings only | Still not persisted |

The stair currently starts the `door` placeholder conversation, not a scene
transition. The lamp room is a placeholder without player/puzzle/save UI. Its path
can round-trip, but this is not evidence of a playable lamp-room Continue flow.
The July devlog's claim that entries are recorded was ahead of the actual wiring.

## Persistence contract

`GameState` owns journal data alongside flags. `Journal` remains the discover,
entries, and has API, returning copies so readers cannot mutate stored state.
Discovering a duplicate or blank ID is a no-op. Stable IDs and discovery order are
preserved; unknown IDs are retained for content compatibility. IDs are case-sensitive.

Dialogue nodes and choices can carry a nonblank `discover_entry` string separately
from `set_flag`. The actual keeper's log text (`logbook_2`) discovers `keeper_log`.
No existing story flag is renamed, consumed, or reinterpreted. The journal reader
and entry-content catalog remain unimplemented.

New saves use version 2 and `journal_entries: ["keeper_log", ...]`. Version 1 and
unversioned saves retain the original default scene/flags when omitted and load an
empty journal when entries are absent. No discoveries are inferred from belief or
trust flags: those are decisions, not reliable discovery history. Reading the log
again records it. Upgrade occurs on the next explicit successful Save, not on load.
If a legacy save already contains a valid journal array, it is retained.

Load validates the full candidate before replacing live state. Invalid JSON,
unsupported/fractional/non-numeric versions, invalid flags/scene types, unknown
scene paths, and invalid journal arrays fail without mutating live state or emitting
change signals. A missing v2 journal is rejected. Duplicate IDs normalize to their
first occurrence. Unknown extra fields are ignored. Future-version saves are
refused rather than silently downgraded. JSON number handling remains the existing
Godot behavior (numbers parse as floats); arbitrary runtime object flags are not a
supported save format.

Load and New Game emit a journal refresh and state change after all state is
consistent; load does not replay `entry_added` notifications. Continue displays an
error on failure; file existence alone still enables its button.

Writes flush a temporary sibling file, check the write result, then rename it over
the save. Open/write/rename failure returns false; the prior save is not explicitly
deleted first. Temporary files are not loaded as saves. This reduces interrupted
write risk, but is not a power-loss durability or backup-recovery guarantee.

## Verification and remaining acceptance checks

Automated: `bash tests/run_save_journal.sh` uses an isolated Linux data directory,
imports the project, runs the real autoloads, then saves and loads in separate Godot
processes. Run `python3 tests/validate_dialogue.py` for content validation.

Covered in the engine suite:

- Unique discovery, blank IDs, stable ordering, defensive copies, unknown IDs.
- New Game reset, repeated loads, refresh without discovery-notification replay.
- True and false story flags, nested JSON-compatible data, both gameplay scene paths.
- Version 1/unversioned migration and upgraded-save reload.
- Malformed/truncated data and future versions; no partial state changes.
- Forced temporary-file open failure and invalid live scene; prior save preserved.
- Actual logbook dialogue, choice flags, and saved discovery.
- A fresh process restoring journal and flags from disk.

Before calling the journal/save path launch-ready:

1. Run the graphical flow: read the log, choose both branches across separate runs,
   Save, return to title, Continue, and repeat after a full quit. Confirm the default
   spawn is intentional. Check error text at shipping resolutions and with controller.
2. Run the suite on minimum-supported Godot 4.3 and each exported target platform.
   This implementation was exercised on Linux Godot 4.7.2, not those targets.
3. Inject disk-full/permission/rename failures and terminate during writes in exported
   builds. Confirm old-save retention and define backup/recovery policy for corruption.
4. Try representative archived player saves, especially false flags and mixed branch
   histories. Confirm empty legacy journals and retained disk save after New Game are
   the desired product behavior. Older game builds cannot promise to preserve v2 data.
5. Finish the reader/catalog and test unknown-ID fallback, entry order, refresh after
   load/reset, long/localized text, focus, scrolling, and controller navigation.
6. Finish lamp-room traversal/content and verify its actual resume path. Decide
   separately whether position, one-shot interactions, settings, autosave, and dialogue
   checkpoints are launch requirements. They are not implemented by this change.
