extends RefCounted

const Model := preload("res://scripts/harmony_composition.gd")
const MAX_BYTES := 512 * 1024
const SUFFIX := ".nikspiano.json"

var directory: String


func _init(folder := "user://compositions") -> void:
	directory = folder.trim_suffix("/")


func save(project: Dictionary) -> Error:
	var valid := Model.validate(project)
	if valid.is_empty():
		return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var path := _path(valid.id)
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	# Preserve recovered data and any broken primary before reusing the temporary slot.
	if FileAccess.file_exists(path):
		error = _preserve_if_invalid(path, _read_local(path, valid.id))
		if error != OK:
			return error
	if FileAccess.file_exists(temporary):
		var pending := _read_local(temporary, valid.id)
		if not pending.is_empty() and not FileAccess.file_exists(path):
			error = DirAccess.rename_absolute(temporary, path)
		else:
			error = _preserve_if_invalid(temporary, pending)
		if error != OK:
			return error
	error = _write(temporary, JSON.stringify(valid, "\t"))
	if error != OK or _read_local(temporary, valid.id) != valid:
		return error if error != OK else ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			error = _preserve_if_invalid(backup, _read_local(backup, valid.id))
			if error != OK:
				return error
		error = DirAccess.rename_absolute(path, backup)
		if error != OK:
			return error
	return DirAccess.rename_absolute(temporary, path)


func load_project(id: String) -> Dictionary:
	if not Model.valid_id(id):
		return {}
	var path := _path(id)
	for candidate in [path, path + ".tmp", path + ".bak"]:
		var project := _read_local(candidate, id)
		if not project.is_empty():
			return project
	return {}


func library() -> Dictionary:
	var projects: Array[Dictionary] = []
	var damaged := 0
	var ids := {}
	if not DirAccess.dir_exists_absolute(directory):
		return {"projects": projects, "damaged": damaged}
	for filename in DirAccess.get_files_at(directory):
		var id := filename.get_slice(".", 0)
		if filename in [id + SUFFIX, id + SUFFIX + ".bak", id + SUFFIX + ".tmp"] and Model.valid_id(id):
			ids[id] = true
	for id: String in ids:
		var project := load_project(id)
		if project.is_empty():
			damaged += 1
		else:
			projects.append(project)
	projects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.modified_at > b.modified_at if a.modified_at != b.modified_at else a.id < b.id)
	return {"projects": projects, "damaged": damaged}


func remember(id: String) -> Error:
	if not Model.valid_id(id):
		return ERR_INVALID_PARAMETER
	var path := directory.path_join("last.txt")
	var error := _write(path + ".tmp", id)
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)


func last_id() -> String:
	var file := FileAccess.open(directory.path_join("last.txt"), FileAccess.READ)
	if file == null or file.get_length() != 32:
		return ""
	var id := file.get_as_text()
	return id if Model.valid_id(id) else ""


func delete_project(id: String) -> Error:
	if not Model.valid_id(id):
		return ERR_INVALID_PARAMETER
	var path := _path(id)
	var primary := ""
	# Make the last valid copy the final file removed if deletion is interrupted.
	for candidate in [path, path + ".tmp", path + ".bak"]:
		if primary.is_empty() and not _read_local(candidate, id).is_empty():
			primary = candidate
			continue
		if FileAccess.file_exists(candidate):
			var error := _preserve_if_invalid(candidate, _read_local(candidate, id))
			if error == OK and FileAccess.file_exists(candidate):
				error = DirAccess.remove_absolute(candidate)
			if error != OK:
				return error
	return DirAccess.remove_absolute(primary) if not primary.is_empty() else ERR_FILE_NOT_FOUND


func import_project(path: String) -> Dictionary:
	var result := read_document(path)
	if result.error != OK:
		return result
	var copy := Model.copy_project(result.project, result.project.title)
	var error := save(copy)
	return {"error": error, "project": copy if error == OK else {}}


static func export_project(path: String, project: Dictionary) -> Error:
	var valid := Model.validate(project)
	if valid.is_empty():
		return ERR_INVALID_DATA
	var error := _write(path, JSON.stringify(valid, "\t"))
	if error != OK:
		return error
	var check := read_document(path)
	if check.error != OK:
		return check.error
	return OK if check.project == valid else ERR_FILE_CORRUPT


static func read_document(path: String) -> Dictionary:
	# A SAF URI is passed unchanged to FileAccess, including its provider encoding.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "project": {}}
	var length := file.get_length()
	if length <= 0 or length > MAX_BYTES:
		return {"error": ERR_INVALID_DATA, "project": {}}
	var bytes := file.get_buffer(length)
	if bytes.size() != length:
		return {"error": ERR_FILE_CANT_READ, "project": {}}
	var source := bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes:
		return {"error": ERR_INVALID_DATA, "project": {}}
	var json := JSON.new()
	if json.parse(source) != OK:
		return {"error": ERR_FILE_CORRUPT, "project": {}}
	if json.data is Dictionary and json.data.get("format") == Model.FORMAT and json.data.has("schema_version") and not Model.Chord.integer_in(json.data.schema_version, Model.OLDEST_SCHEMA, Model.SCHEMA):
		return {"error": ERR_UNAVAILABLE, "project": {}}
	var project := Model.validate(json.data)
	return {"error": OK if not project.is_empty() else ERR_INVALID_DATA, "project": project}


static func _read_local(path: String, id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var result := read_document(path)
	return result.project if result.error == OK and result.project.id == id else {}


static func _preserve_if_invalid(path: String, parsed: Dictionary) -> Error:
	if not parsed.is_empty():
		return OK
	return DirAccess.rename_absolute(path, path + ".corrupt-" + Model.new_id())


static func _write(path: String, data: String) -> Error:
	var bytes := data.to_utf8_buffer()
	if bytes.size() > MAX_BYTES:
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return error if error != OK else (OK if stored else ERR_FILE_CANT_WRITE)


func _path(id: String) -> String:
	return directory.path_join(id + SUFFIX)
