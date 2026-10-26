extends Node

const ROOT: String = "user://tests/casualty_archive_worker"
const ARCHIVE_WRITER: Script = preload("res://resources/casualties/casualty_archive_writer.gd")

class BlockingWriter extends "res://resources/casualties/casualty_archive_writer.gd":
	var entered: Semaphore = Semaphore.new()
	var release_first: Semaphore = Semaphore.new()
	var received_counts: Array[int] = []
	var background_only: bool = true

	func _write_snapshot(snapshot: Snapshot) -> Error:
		background_only = background_only and not Thread.is_main_thread()
		received_counts.append(snapshot.records.size())
		if received_counts.size() == 1:
			entered.post()
			release_first.wait()
		return super._write_snapshot(snapshot)


class SingleThreadWriter extends "res://resources/casualties/casualty_archive_writer.gd":
	var received_counts: Array[int] = []
	var main_thread_only: bool = true

	func _init() -> void:
		super(false)

	func _write_snapshot(snapshot: Snapshot) -> Error:
		main_thread_only = main_thread_only and Thread.is_main_thread()
		received_counts.append(snapshot.records.size())
		return super._write_snapshot(snapshot)


var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _record(id: String) -> CasualtyRecord:
	var record: CasualtyRecord = CasualtyRecord.new()
	record.record_id = id
	record.equipment = CasualtyEquipment.new()
	record.equipment.ammunition = 7
	return record


func _history(filename: String) -> CasualtyHistory:
	var history: CasualtyHistory = CasualtyHistory.new()
	history.storage_path = ROOT.path_join(filename + ".tres")
	return history


func _run() -> void:
	if OS.get_cmdline_user_args().has("--single-thread"):
		Globals._casualty_writer = SingleThreadWriter.new()
	if OS.get_cmdline_user_args().has("--shutdown-fixture"):
		Globals.casualty_history = _history("shutdown")
		DirAccess.remove_absolute(Globals.casualty_history.storage_path)
		Globals.import_casualty_records([_record("shutdown")])
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--verify-shutdown"):
		var saved: CasualtyHistory = CasualtyHistory.load_history(_history("shutdown").storage_path)
		_check(saved.records.size() == 1 and saved.find_record("shutdown") != null, "Application shutdown saves a batch that has not reached its timer")
	else:
		if OS.has_feature("threads"):
			_test_worker()
		_test_single_thread_writer()
		_test_global_batching()
		_test_single_thread_global_batching()
	print("Casualty archive worker checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_worker() -> void:
	var history: CasualtyHistory = _history("worker")
	var first: CasualtyRecord = _record("first")
	history.add_record(first)
	var writer: BlockingWriter = BlockingWriter.new()
	_check(writer.queue_save(history) == OK, "Queue a background archive write")
	writer.entered.wait()
	history.add_record(_record("second"))
	_check(writer.queue_save(history) == OK, "New casualties queue while serialization is still blocked")
	history.add_record(_record("third"))
	_check(writer.queue_save(history) == OK, "A newer batch replaces the same pending archive")
	var other: CasualtyHistory = _history("other")
	other.add_record(_record("other"))
	_check(writer.queue_save(other) == OK, "Different archive paths can queue independently")
	_check(history.records.size() == 3 and history.find_record("third") != null, "Casualties remain immediately available in memory during a save")
	writer.release_first.post()
	writer.flush()
	_check(writer.background_only, "Resource copying and serialization run outside the main thread")
	_check(writer.received_counts == [1, 3, 1], "An in-flight snapshot keeps its membership and queued batches coalesce to the latest records")
	var results: Array[Dictionary] = writer.take_results()
	_check(results.size() == 3, "Every completed archive reports a result")
	for result: Dictionary in results:
		_check(result["error"] == OK, "Background archive writes complete successfully")
	var saved: CasualtyHistory = CasualtyHistory.load_history(history.storage_path)
	_check(saved.records.size() == 3 and saved.find_record("third") != null, "The latest queued archive includes every casualty")
	_check(saved.find_record("first").equipment.ammunition == 7 and first.equipment.ammunition == 7, "Worker-owned equipment copies retain historical data")
	_check(CasualtyHistory.load_history(other.storage_path).find_record("other") != null, "Saving another archive does not overwrite the first")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(history.storage_path)
	history._storage_valid = false
	history.add_record(_record("fourth"))
	writer.queue_save(history)
	writer.flush()
	results = writer.take_results()
	_check(results.size() == 1 and results[0]["error"] == ERR_FILE_CORRUPT, "An unreadable archive reports a background save failure")
	_check(FileAccess.get_file_as_bytes(history.storage_path) == original_bytes, "An unreadable archive never overwrites the existing file")
	history._storage_valid = true
	writer.queue_save(history)
	writer.shutdown()
	_check(CasualtyHistory.load_history(history.storage_path).records.size() == 4, "Worker shutdown waits for its final queued write")
	_check(writer.queue_save(history) == ERR_UNAVAILABLE, "A stopped worker rejects further writes")


func _test_single_thread_writer() -> void:
	var writer: SingleThreadWriter = SingleThreadWriter.new()
	_check(writer._thread == null and writer._mutex == null and writer._work == null and writer._completed == null, "The single-thread writer allocates no threading primitives")
	var history: CasualtyHistory = _history("single_thread")
	DirAccess.remove_absolute(history.storage_path)
	history.add_record(_record("first"))
	_check(writer.queue_save(history) == OK, "Single-thread builds accept queued saves")
	history.add_record(_record("second"))
	_check(writer.queue_save(history) == OK, "Repeated single-thread saves coalesce")
	history.add_record(_record("not_queued"))
	var other: CasualtyHistory = _history("single_other")
	DirAccess.remove_absolute(other.storage_path)
	other.add_record(_record("other"))
	writer.queue_save(other)
	_check(writer.received_counts.is_empty() and not FileAccess.file_exists(history.storage_path), "Queueing never serializes immediately on the caller")
	_check(history.find_record("not_queued") != null, "New casualties stay immediately available in memory")
	writer.process_pending()
	_check(writer.received_counts == [2] and not FileAccess.file_exists(other.storage_path), "Each frame saves only one archive with the latest queued membership")
	var saved: CasualtyHistory = CasualtyHistory.load_history(history.storage_path)
	_check(saved.records.size() == 2 and saved.find_record("second") != null, "Single-thread snapshots preserve membership from queue time")
	_check(saved.find_record("first").equipment.ammunition == 7, "Single-thread saves preserve historical equipment")
	writer.flush()
	_check(writer.received_counts == [2, 1] and writer.main_thread_only, "Flush drains all remaining archives on the main thread")
	var results: Array[Dictionary] = writer.take_results()
	_check(results.size() == 2 and writer.take_results().is_empty(), "Single-thread results are delivered once")
	for result: Dictionary in results:
		_check(result["error"] == OK, "Single-thread archive writes succeed")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(history.storage_path)
	history._storage_valid = false
	writer.queue_save(history)
	writer.process_pending()
	results = writer.take_results()
	_check(results.size() == 1 and results[0]["error"] == ERR_FILE_CORRUPT, "Single-thread save failures are reported")
	_check(FileAccess.get_file_as_bytes(history.storage_path) == original_bytes, "Invalid archives remain untouched on single-thread builds")
	history._storage_valid = true
	writer.queue_save(history)
	writer.shutdown()
	_check(CasualtyHistory.load_history(history.storage_path).records.size() == 3, "Single-thread shutdown drains queued saves")
	_check(writer.queue_save(history) == ERR_UNAVAILABLE, "A stopped single-thread writer rejects new saves")
	_check(writer._thread == null and writer._mutex == null and writer._work == null and writer._completed == null, "Single-thread saving and shutdown never allocate threading primitives")


func _test_single_thread_global_batching() -> void:
	Globals.flush_casualty_history()
	var original_writer: ARCHIVE_WRITER = Globals._casualty_writer
	var writer: SingleThreadWriter = SingleThreadWriter.new()
	Globals._casualty_writer = writer
	_test_global_batching()
	_check(writer.received_counts.size() == 2 and writer.main_thread_only, "The gameplay frame pump and checkpoints save both archives without a worker")
	writer.shutdown()
	Globals._casualty_writer = original_writer


func _test_global_batching() -> void:
	Globals.flush_casualty_history()
	var original: CasualtyHistory = Globals.casualty_history
	var first: CasualtyHistory = _history("batch_first")
	var second: CasualtyHistory = _history("batch_second")
	DirAccess.remove_absolute(first.storage_path)
	Globals.casualty_history = first
	Globals.import_casualty_records([_record("batch_one")])
	Globals._process(0.15)
	_check(not FileAccess.file_exists(first.storage_path), "Deaths collect in memory before the batch deadline")
	Globals.import_casualty_records([_record("batch_two")])
	Globals._process(0.1)
	_check(not Globals._casualty_save_queued, "Continuous casualties do not postpone the fixed batch deadline")
	if not Globals._casualty_writer._use_threads:
		_check(CasualtyHistory.load_history(first.storage_path).records.size() == 2, "The normal frame pump persists a single-thread batch without an explicit flush")
	Globals.casualty_history = second
	Globals.import_casualty_records([_record("other_batch")])
	Globals.flush_casualty_history()
	_check(CasualtyHistory.load_history(first.storage_path).records.size() == 2, "An archive replacement cannot lose already queued casualties")
	_check(CasualtyHistory.load_history(second.storage_path).find_record("other_batch") != null, "An explicit checkpoint flushes the newest pending archive")
	Globals.casualty_history = original


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
