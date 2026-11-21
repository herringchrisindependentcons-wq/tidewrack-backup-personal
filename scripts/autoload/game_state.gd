extends Node
## GameState owns the complete persisted snapshot. Journal is its public facade.

signal state_changed
signal journal_changed

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
const DEFAULT_SCENE := "res://scenes/game.tscn"
const RESUME_SCENES := [DEFAULT_SCENE, "res://scenes/lamp_room.tscn"]

var flags: Dictionary = {}
var current_scene: String = DEFAULT_SCENE
var _journal_entries: Array[String] = []


func set_flag(name: String, value: Variant) -> void:
	flags[name] = value
	state_changed.emit()


func get_flag(name: String, default: Variant = false) -> Variant:
	return flags.get(name, default)


func journal_entries() -> Array[String]:
	return _journal_entries.duplicate()


func discover_entry(id: String) -> bool:
	if id.strip_edges().is_empty() or id in _journal_entries:
		return false
	_journal_entries.append(id)
	journal_changed.emit()
	state_changed.emit()
	return true


func new_game() -> void:
	flags.clear()
	current_scene = DEFAULT_SCENE
	_journal_entries.clear()
	journal_changed.emit()
	state_changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"scene": current_scene,
		"flags": flags,
		"journal_entries": _journal_entries,
	}
	# Never publish a snapshot that Continue cannot read.
	if _validated_snapshot(payload).is_empty():
		return false
	var temporary := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return false
	# Same-directory rename keeps the previous save intact until replacement.
	if DirAccess.rename_absolute(temporary, SAVE_PATH) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true


func load_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return false
	var snapshot := _validated_snapshot(parser.data)
	if snapshot.is_empty():
		return false

	# Validate everything before replacing anything. Observers see one snapshot.
	current_scene = snapshot["scene"]
	flags = snapshot["flags"]
	_journal_entries.assign(snapshot["journal_entries"])
	journal_changed.emit()
	state_changed.emit()
	return true


func _validated_snapshot(parsed: Variant) -> Dictionary:
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	# Unversioned saves use the original v1 defaults. Future versions are refused.
	var version: Variant = data.get("version", 1)
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	if version != 1 and version != SAVE_VERSION:
		return {}
	var scene: Variant = data.get("scene", DEFAULT_SCENE)
	if not scene is String or scene not in RESUME_SCENES or not ResourceLoader.exists(scene):
		return {}
	var loaded_flags: Variant = data.get("flags", {})
	if not loaded_flags is Dictionary:
		return {}
	# v1 has no journal. Missing v2 journal data is corruption, not an empty journal.
	var entries: Variant = data.get("journal_entries", [] if version == 1 else null)
	if not entries is Array:
		return {}
	var normalized: Array[String] = []
	for entry in entries:
		if not entry is String or entry.strip_edges().is_empty():
			return {}
		# Preserve discovery order and unknown IDs for content compatibility.
		if entry not in normalized:
			normalized.append(entry)
	return {"scene": scene, "flags": loaded_flags.duplicate(true), "journal_entries": normalized}


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
