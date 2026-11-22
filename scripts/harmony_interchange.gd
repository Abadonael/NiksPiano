extends Node

signal result(action: String, error: Error, project: Dictionary)

const Store := preload("res://scripts/harmony_store.gd")
const FILTER := "*.nikspiano.json,*.json;Niks Piano (JSON);application/json,application/octet-stream,text/plain"

var store: Store
var pending := false


func choose_export(project: Dictionary) -> void:
	_show("export", project)


func choose_import() -> void:
	_show("import", {})


func _show(action: String, project: Dictionary) -> void:
	if pending:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		result.emit(action, ERR_UNAVAILABLE, {})
		return
	var exporting := action == "export"
	var mode := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if exporting else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
	var caption := "Экспорт композиции" if exporting else "Импорт композиции"
	var filename := "NiksPiano-" + str(project.get("id", "")).left(8) + Store.SUFFIX if exporting else ""
	pending = true
	var error := DisplayServer.file_dialog_show(caption, "", filename, false, mode, [FILTER],
		_selected.bind(action, project.duplicate(true)))
	if error != OK:
		pending = false
		result.emit(action, error, {})


func _selected(accepted: bool, paths: PackedStringArray, _filter: int, action: String, project: Dictionary) -> void:
	pending = false
	if not accepted or paths.is_empty():
		return
	var path := paths[0]
	if action == "export":
		# The Android destination is already named by the SAF provider.
		if not path.begins_with("content://") and not path.to_lower().ends_with(".json"):
			path += Store.SUFFIX
		result.emit(action, Store.export_project(path, project), {})
	else:
		var imported := store.import_project(path)
		result.emit(action, imported.error, imported.project)
