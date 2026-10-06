extends Resource
class_name CasualtyHistory

const SAVE_PATH: String = "user://history/casualties.tres"

@export var save_version: int = 1
@export var records: Array[CasualtyRecord] = []

var storage_path: String = SAVE_PATH
var _records_by_id: Dictionary[String, CasualtyRecord] = {}
var _storage_valid: bool = true


static func load_history(path: String = SAVE_PATH) -> CasualtyHistory:
	var history: CasualtyHistory = CasualtyHistory.new()
	history.storage_path = path
	if not FileAccess.file_exists(path):
		return history
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded is not CasualtyHistory:
		# Keep new records in memory, but never overwrite an unreadable archive.
		history._storage_valid = false
		push_error("Could not load casualty history: %s" % path)
		return history
	history = loaded as CasualtyHistory
	history.storage_path = path
	for record: CasualtyRecord in history.records:
		if record != null and not record.record_id.is_empty():
			history._records_by_id[record.record_id] = record
	return history


func find_record(record_id: String) -> CasualtyRecord:
	return _records_by_id.get(record_id, null) as CasualtyRecord


func add_record(record: CasualtyRecord) -> bool:
	if record == null or record.record_id.is_empty() or _records_by_id.has(record.record_id):
		return false
	records.append(record)
	_records_by_id[record.record_id] = record
	return true


func save_history() -> Error:
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
