extends Resource
class_name SessionLog

const SAVE_PATH: String = "user://history/session_log.tres"

@export var save_version: int = 1
@export var exit_records: Array[UnitExitRecord] = []

var storage_path: String = SAVE_PATH
var _records_by_id: Dictionary[String, UnitExitRecord] = {}
var _storage_valid: bool = true


static func load_log(path: String = SAVE_PATH) -> SessionLog:
	var log: SessionLog = SessionLog.new()
	log.storage_path = path
	if not FileAccess.file_exists(path):
		return log
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded is not SessionLog:
		log._storage_valid = false
		push_error("Could not load session log: %s" % path)
		return log
	log = loaded as SessionLog
	log.storage_path = path
	for record: UnitExitRecord in log.exit_records:
		if record != null and not record.record_id.is_empty():
			log._records_by_id[record.record_id] = record
	return log


func add_exit(record: UnitExitRecord) -> bool:
	if record == null or record.record_id.is_empty() or _records_by_id.has(record.record_id):
		return false
	exit_records.append(record)
	_records_by_id[record.record_id] = record
	return true


func save_log() -> Error:
	if not _storage_valid:
		return ERR_FILE_CORRUPT
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(storage_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var pending_path: String = storage_path.get_basename() + ".pending.tres"
	var save_error: Error = ResourceSaver.save(self, pending_path)
	if save_error != OK:
		return save_error
	return DirAccess.rename_absolute(pending_path, storage_path)
