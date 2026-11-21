extends Node
## Run only with an isolated XDG_DATA_HOME; this suite writes user://save.json.

var failures := 0
var added := 0
var changed := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func write_save(value: Variant) -> void:
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "seed" in args:
		GameState.new_game()
		Journal.discover("keeper_log")
		Journal.discover("unknown_future_entry")
		GameState.set_flag("trusted_edith", false)
		GameState.set_flag("radioed_tom", true)
		check(GameState.save_game(), "Cold-process seed save")
		get_tree().quit(failures)
		return
	if "verify" in args:
		await get_tree().process_frame
		check(Journal.entries().is_empty(), "Fresh process starts empty")
		var menu := preload("res://scenes/main_menu.tscn").instantiate()
		get_tree().root.add_child(menu)
		# Keep this test harness alive while Continue replaces the title scene.
		get_tree().current_scene = menu
		menu._on_continue()
		await get_tree().process_frame
		await get_tree().process_frame
		check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == GameState.DEFAULT_SCENE, "Continue loads the saved gameplay scene")
		check(Journal.entries() == ["keeper_log", "unknown_future_entry"], "Cold-process journal restore")
		check(GameState.flags.has("trusted_edith") and GameState.get_flag("trusted_edith") == false and GameState.get_flag("radioed_tom") == true, "Cold-process flags restore")
		print("Cold-process save/Continue: %s" % ("PASS" if failures == 0 else "FAIL"))
		get_tree().quit(failures)
		return
	Journal.entry_added.connect(func(_id: String): added += 1)
	GameState.state_changed.connect(func(): changed += 1)
	GameState.delete_save()
	check(not GameState.load_game(), "Missing save fails")
	GameState.new_game()
	Journal.discover("keeper_log")
	Journal.discover("keeper_log")
	Journal.discover("")
	Journal.discover("  ")
	Journal.discover("future_entry")
	check(added == 2, "Discovery is unique and ignores blank IDs")
	var copy := Journal.entries()
	copy.clear()
	check(Journal.entries() == ["keeper_log", "future_entry"], "Returned entries cannot mutate state")
	var story := {"trusted_edith": false, "skeptic": true, "radioed_tom": true, "lamp_relit": false, "custom": {"count": 3.0, "text": "fog"}}
	GameState.flags = story.duplicate(true)
	GameState.current_scene = "res://scenes/lamp_room.tscn"
	check(GameState.save_game(), "Save succeeds")
	GameState.new_game()
	check(Journal.entries().is_empty() and GameState.flags.is_empty(), "New Game resets journal and flags")
	check(GameState.has_save(), "New Game preserves disk save until explicitly saved")
	Journal.discover("stale_unsaved_entry")
	var before := added
	check(GameState.load_game(), "v2 reload succeeds")
	check(Journal.entries() == ["keeper_log", "future_entry"], "Journal order survives")
	check(GameState.flags == story and GameState.current_scene == "res://scenes/lamp_room.tscn", "All story values and scene survive")
	check(added == before, "Load does not replay discovery notifications")
	check(GameState.load_game(), "Repeated load succeeds")
	check(Journal.entries().size() == 2, "Repeated load replaces rather than appends")
	check(GameState.save_game(), "Atomic replacement of existing save succeeds")

	for legacy in [{"version": 1, "scene": "res://scenes/lamp_room.tscn", "flags": story}, {"version": 1, "flags": story}, {"flags": story}]:
		Journal.discover("stale_before_legacy")
		write_save(legacy)
		check(GameState.load_game(), "Legacy save loads")
		check(GameState.flags == story and Journal.entries().is_empty(), "Legacy load preserves flags and clears stale journal")
		check(GameState.current_scene == legacy.get("scene", GameState.DEFAULT_SCENE), "Legacy saved scene preserved or missing scene defaults")
		check(GameState.save_game(), "Legacy save upgrades")
		check(GameState.load_game(), "Upgraded legacy save reloads")

	write_save({"version": 2, "flags": story, "journal_entries": ["b", "a", "b", "unknown"]})
	check(GameState.load_game(), "Duplicate IDs normalize")
	check(Journal.entries() == ["b", "a", "unknown"], "First-discovery order and unknown IDs preserved")
	var expected_entries := Journal.entries()
	var invalid: Array = [null, [], "bad", {"version": 3}, {"version": true}, {"version": "2"}, {"version": 1.5}, {"version": 2}, {"flags": []}, {"scene": 3}, {"scene": "res://scenes/main_menu.tscn"}, {"scene": "res://missing.tscn"}, {"version": 2, "journal_entries": null}, {"version": 2, "journal_entries": ["ok", 42]}, {"version": 2, "journal_entries": [" "]}]
	for bad in invalid:
		write_save(bad)
		var signals_before := changed
		check(not GameState.load_game(), "Malformed/future snapshot rejected: %s" % str(bad))
		check(GameState.flags == story and Journal.entries() == expected_entries and GameState.current_scene == GameState.DEFAULT_SCENE, "Failed load leaves complete live state intact")
		check(changed == signals_before, "Failed load emits no state change")
	var broken := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	broken.store_string('{"version":')
	broken.close()
	check(not GameState.load_game(), "Truncated JSON rejected")

	check(GameState.save_game(), "Restore valid disk snapshot")
	var disk_before := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	# A directory at the temporary-file path deterministically forces write failure.
	DirAccess.make_dir_absolute(GameState.SAVE_PATH + ".tmp")
	check(not GameState.save_game(), "Write failure is reported")
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == disk_before, "Failed write preserves previous save")
	DirAccess.remove_absolute(GameState.SAVE_PATH + ".tmp")
	GameState.current_scene = "res://missing.tscn"
	check(not GameState.save_game(), "Invalid live scene cannot overwrite valid save")
	check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == disk_before, "Rejected snapshot preserves disk save")

	GameState.new_game()
	check(DialogueManager.start("res://data/dialogue/keeper_intro.json", "logbook"), "Real logbook starts")
	check(Journal.entries().is_empty(), "Discovery waits for actual entry text")
	DialogueManager.advance()
	check(Journal.has("keeper_log"), "Dialogue discovers keeper log")
	DialogueManager.advance()
	DialogueManager.choose(0)
	DialogueManager.advance()
	DialogueManager.advance()
	DialogueManager.choose(1)
	DialogueManager.advance()
	check(not DialogueManager.is_active, "Dialogue finishes")
	check(GameState.get_flag("skeptic") == true and GameState.flags.has("trusted_edith") and GameState.get_flag("trusted_edith") == false, "Existing true/false choice flags unchanged")
	check(GameState.save_game(), "Save dialogue outcome")
	GameState.new_game()
	check(GameState.load_game() and Journal.has("keeper_log") and GameState.get_flag("skeptic"), "Dialogue outcome survives Continue load")
	GameState.delete_save()
	print("Journal/save tests: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(0 if failures == 0 else 1)
