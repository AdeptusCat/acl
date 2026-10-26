extends RefCounted

# Threaded builds serialize immutable historical snapshots in a worker.
# Single-thread builds drain the same queue through the gameplay frame pump.
class Snapshot extends RefCounted:
	var path: String
	var save_version: int
	var storage_valid: bool
	var records: Array[CasualtyRecord] = []

	func _init(history: CasualtyHistory) -> void:
		path = history.storage_path
		save_version = history.save_version
		storage_valid = history._storage_valid
		records.assign(history.records)


var _thread: Thread
var _use_threads: bool = false
var _mutex: Mutex
var _work: Semaphore
var _completed: Semaphore
var _pending: Dictionary[String, Snapshot] = {}
var _results: Array[Dictionary] = []
var _busy: bool = false
var _stopping: bool = false


func _init(allow_threads: bool = true) -> void:
	_use_threads = allow_threads and OS.has_feature("threads")
	if _use_threads:
		_mutex = Mutex.new()
		_work = Semaphore.new()
		_completed = Semaphore.new()


func queue_save(history: CasualtyHistory) -> Error:
	if _stopping:
		return ERR_UNAVAILABLE
	if not _use_threads:
		# The frame pump writes the newest snapshot for each archive, not each death.
		_pending[history.storage_path] = Snapshot.new(history)
		return OK
	if _thread == null:
		_thread = Thread.new()
		var error: Error = _thread.start(_run)
		if error != OK:
			_thread = null
			return error
	var snapshot: Snapshot = Snapshot.new(history)
	_mutex.lock()
	var already_pending: bool = _pending.has(snapshot.path)
	# Newer snapshots replace queued writes to the same archive, never an
	# in-progress write. One worker also prevents temporary-file collisions.
	_pending[snapshot.path] = snapshot
	_mutex.unlock()
	if not already_pending:
		_work.post()
	return OK


func take_results() -> Array[Dictionary]:
	if _use_threads:
		_mutex.lock()
	var results: Array[Dictionary] = _results
	_results = []
	if _use_threads:
		_mutex.unlock()
	return results


func process_pending() -> void:
	# Single-thread exports save at most one coalesced archive per frame.
	if _use_threads or _pending.is_empty():
		return
	var path: String = _pending.keys()[0]
	var snapshot: Snapshot = _pending[path]
	_pending.erase(path)
	var started: int = Time.get_ticks_usec()
	var error: Error = _write_snapshot(snapshot)
	_results.append({"path": path, "error": error, "records": snapshot.records.size(), "duration_us": Time.get_ticks_usec() - started})


func flush() -> void:
	if not _use_threads:
		while not _pending.is_empty():
			process_pending()
		return
	while true:
		_mutex.lock()
		var finished: bool = _pending.is_empty() and not _busy
		_mutex.unlock()
		if finished:
			return
		_completed.wait()


func shutdown() -> void:
	flush()
	if not _use_threads:
		_stopping = true
		return
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	if _thread != null:
		_work.post()
		_thread.wait_to_finish()
		_thread = null


func _run() -> void:
	while true:
		_work.wait()
		_mutex.lock()
		if _stopping:
			_mutex.unlock()
			return
		var path: String = _pending.keys()[0]
		var snapshot: Snapshot = _pending[path]
		_pending.erase(path)
		_busy = true
		_mutex.unlock()
		var started: int = Time.get_ticks_usec()
		var error: Error = _write_snapshot(snapshot)
		_mutex.lock()
		_results.append({"path": path, "error": error, "records": snapshot.records.size(), "duration_us": Time.get_ticks_usec() - started})
		_busy = false
		_mutex.unlock()
		_completed.post()


func _write_snapshot(snapshot: Snapshot) -> Error:
	if not snapshot.storage_valid:
		return ERR_FILE_CORRUPT
	var archive: CasualtyHistory = CasualtyHistory.new()
	archive.storage_path = snapshot.path
	archive.save_version = snapshot.save_version
	for record: CasualtyRecord in snapshot.records:
		if record == null:
			archive.records.append(null)
		else:
			archive.records.append(record.duplicate(true) as CasualtyRecord)
	return archive.save_history()
