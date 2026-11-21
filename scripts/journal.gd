extends Node
## Journal facade. GameState owns storage so reset/load/save share one snapshot.

signal entry_added(id: String)
## Refresh the reader after discovery, load, or New Game. Load does not replay
## entry_added, which is reserved for new-discovery notifications.
signal entries_changed


func _ready() -> void:
	GameState.journal_changed.connect(func(): entries_changed.emit())


func discover(id: String) -> void:
	if GameState.discover_entry(id):
		entry_added.emit(id)


func entries() -> Array[String]:
	return GameState.journal_entries()


func has(id: String) -> bool:
	return id in GameState.journal_entries()
