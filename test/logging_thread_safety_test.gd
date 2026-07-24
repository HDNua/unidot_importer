extends SceneTree

const ASSET_DATABASE := preload("res://addons/unidot_importer/asset_database.gd")
const ASSET_META := preload("res://addons/unidot_importer/asset_meta.gd")

const THREAD_COUNT := 8
const ITERATIONS_PER_THREAD := 500
const DEBUG_LOG_LIMIT := 37


func _initialize() -> void:
	var database = ASSET_DATABASE.new()
	database.enable_verbose_logs = true
	database.log_limit_per_guid = DEBUG_LOG_LIMIT

	var meta = ASSET_META.new()
	meta.set_log_database(database)
	meta.guid = "thread-safety-test-guid"
	meta.orig_path_short = "ThreadSafety.asset"

	var threads: Array[Thread] = []
	for worker_index in range(THREAD_COUNT):
		var thread := Thread.new()
		var start_error := thread.start(
			_stress_worker.bind(database, meta, worker_index)
		)
		if start_error != OK:
			_fail("Unable to start worker %d: %s" % [worker_index, error_string(start_error)])
			return
		threads.append(thread)

	for thread in threads:
		thread.wait_to_finish()

	var expected_worker_messages := THREAD_COUNT * ITERATIONS_PER_THREAD
	var expected_sequence_count := expected_worker_messages * 6
	if database.global_log_count != expected_sequence_count:
		_fail(
			"Atomic sequence count mismatch: expected %d, got %d"
			% [expected_sequence_count, database.global_log_count]
		)
		return

	var asset_snapshot: Dictionary = meta.log_message_holder.snapshot()
	var expected_debug_logs: int = min(expected_worker_messages, DEBUG_LOG_LIMIT + 1)
	var expected_asset_log_count: int = expected_worker_messages * 2 + expected_debug_logs
	if len(asset_snapshot["fails"]) != expected_worker_messages:
		_fail("Failure count mismatch.")
		return
	if len(asset_snapshot["warnings_fails"]) != expected_worker_messages * 2:
		_fail("Warning/failure count mismatch.")
		return
	if len(asset_snapshot["all_logs"]) != expected_asset_log_count:
		_fail(
			"Asset log count mismatch: expected %d, got %d"
			% [expected_asset_log_count, len(asset_snapshot["all_logs"])]
		)
		return

	var global_snapshot: Dictionary = database.log_message_holder.snapshot()
	if len(global_snapshot["all_logs"]) != expected_worker_messages * 3:
		_fail("Global log count mismatch.")
		return
	if len(global_snapshot["warnings_fails"]) != expected_worker_messages * 2:
		_fail("Global warning/failure count mismatch.")
		return
	if len(global_snapshot["fails"]) != expected_worker_messages:
		_fail("Global failure count mismatch.")
		return

	var retained_logs: PackedStringArray = asset_snapshot["all_logs"]
	retained_logs.append_array(global_snapshot["all_logs"])
	var sequences := {}
	for log_str in retained_logs:
		var sequence_text: String = log_str.substr(0, 8)
		if not sequence_text.is_valid_int():
			_fail("Malformed log sequence: " + log_str)
			return
		var sequence := sequence_text.to_int()
		if sequences.has(sequence):
			_fail("Duplicate log sequence: %d" % sequence)
			return
		sequences[sequence] = true

	print(
		"UNIDOT_LOGGING_THREAD_SAFETY_TEST_PASS sequences=%d retained=%d fails=%d warnings=%d"
		% [
			database.global_log_count,
			len(retained_logs),
			len(asset_snapshot["fails"]),
			len(asset_snapshot["warnings_fails"]) - len(asset_snapshot["fails"]),
		]
	)
	quit(0)


func _stress_worker(database: Resource, meta: Resource, worker_index: int) -> void:
	for iteration in range(ITERATIONS_PER_THREAD):
		var message := "worker=%d iteration=%d" % [worker_index, iteration]
		meta.log_fail(iteration + 1, message)
		meta.log_warn(iteration + 1, message)
		meta.log_debug(iteration + 1, message)
		database.log_debug([null, 0, "", 0], message)
		database.log_warn([null, 0, "", 0], message)
		database.log_fail([null, 0, "", 0], message)


func _fail(message: String) -> void:
	push_error("UNIDOT_LOGGING_THREAD_SAFETY_TEST_FAIL: " + message)
	quit(1)
