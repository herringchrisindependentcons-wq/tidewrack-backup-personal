# Journal save regression verification

Scope: journal/save persistence, compatibility, and regression coverage.
`GameState` owns persisted journal IDs; `Journal` delegates discovery and reads.
New saves contain `version: 2`, `scene`, `flags`, and `journal_entries`.

## Running the verification

From the repository root on Linux with Godot on PATH:

```bash
bash tests/run_save_journal.sh
python3 tests/validate_dialogue.py
git diff --check
```

The runner creates a temporary `XDG_DATA_HOME`, so it does not overwrite a player's
save. It imports the project, exercises real autoloads, then seeds a save in one
process and invokes the title menu's Continue handler in another process. Assertions
fail the run with a nonzero exit code. The five cases below are covered by
`tests/save_journal.gd` and `tests/save_journal.tscn`.

## 1. Normal save/Continue

- [x] Discover `keeper_log` and a second ID, set true and false story flags, and Save.
- [x] Restore the exact scene, flags, and journal discovery order from the saved snapshot.
- [x] Add an unsaved in-memory entry before load; confirm it is replaced rather than retained.
- [x] Repeat loading; confirm no accumulated IDs or replayed `entry_added` notifications.
- [x] Quit the seed process. In a new process, invoke `MainMenu._on_continue()` and
  confirm the gameplay scene is instantiated and the saved journal and flags restored.

Expected: IDs, saved scene, and story flags survive save/Continue together. Unknown
nonblank IDs remain intact. Player position and active dialogue are not persisted.
The headless handler test does not verify mouse/controller input or visual layout.

## 2. Existing v1 save without journal data

Fixture shape (no `journal_entries` field):

```json
{
  "version": 1,
  "scene": "res://scenes/lamp_room.tscn",
  "flags": {"trusted_edith": false, "radioed_tom": true}
}
```

- [x] Seed stale journal state, then load a v1 save with a saved scene and flags.
- [x] Confirm that the saved scene and all flags, including false values, survive,
  while the journal becomes empty.
- [x] Also cover v1 with omitted scene and an unversioned save using legacy defaults.
- [x] Save again to upgrade to v2, then reload successfully.

Expected: no invented discovery history and no stale in-memory discoveries. Migration
happens in memory; disk is upgraded only by a successful explicit Save.

## 3. New Game reset

- [x] Discover entries, set flags, change the resume scene, and Save.
- [x] Call `GameState.new_game()` and confirm the journal and flags are empty.
- [x] Confirm the existing disk save remains available until explicitly overwritten;
  the fresh-process seed also verifies New Game uses the default gameplay scene.

Expected: a new playthrough starts without prior journal discoveries. New Game clears
live state, not the existing disk save. Continue can still restore that saved game.

## 4. Duplicate discovery

- [x] Discover `keeper_log` twice; confirm only one copy is stored and only one
  notification is emitted for that ID.
- [x] Confirm blank IDs are ignored and `entries()` returns a defensive copy.
- [x] Load `["b", "a", "b", "unknown"]`; confirm `["b", "a", "unknown"]`.

Expected: IDs are unique in first-discovery order. IDs are case-sensitive. Unknown
nonblank IDs are retained rather than dropped during a content update.

## 5. Malformed journal data

- [x] Reject v2 saves with missing or null `journal_entries`.
- [x] Reject arrays containing a number or a blank string, including a valid ID
  followed by an invalid element (no partial application).
- [x] Confirm rejected loads preserve live scene, flags, and journal and emit no
  state-change notification.
- [x] Also reject truncated JSON, malformed top-level data, and unsupported versions.

Expected: malformed journal data fails the whole load; it does not silently erase
progress. The title menu displays a load error. Missing journal data is accepted for
v1/unversioned saves, as explicitly covered in case 2.

## Verification record and limits

Verified on Linux with Godot 4.7.2: in-engine journal/save suite, separate-process
Continue handler, dialogue graph validation, and whitespace/diff validation.
The suite additionally forces a temporary-file open failure and confirms the old
save remains intact, checks invalid-scene rejection, and exercises real logbook
conversation flags and discovery.

Not yet verified: graphical/controller Continue, exported builds, Godot 4.3, disk-full
or rename failure injection, power loss, and a collection of archived player saves.
The journal reader and playable lamp-room traversal remain separate work; this PR
does not implement them. See `docs/journal-save-review.md` for the broader trace.
