extends Control
## The launcher window: checks GitHub for a newer game build, downloads and verifies it,
## keeps the previous version for rollback, then starts the game.
## All the file work is in update_logic.gd; this script is the UI and the downloads.

const UpdateLogic := preload("res://update_logic.gd")
const AUTO_START_SEC := 3.0

## LANCER_LAUNCHER_ROOT installs somewhere else (testing against a fake release without
## touching the real install in the launcher's user folder).
var logic := UpdateLogic.new(OS.get_environment("LANCER_LAUNCHER_ROOT") if OS.get_environment("LANCER_LAUNCHER_ROOT") != "" else "user://")
var release: Dictionary = {}
var http: HTTPRequest
var countdown := -1.0

var status: Label
var detail: Label
var progress: ProgressBar
var play_button: Button
var rollback_button: Button
var retry_button: Button


func _ready() -> void:
	_build_ui()
	http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	check_for_update()


func _process(delta: float) -> void:
	if http.get_http_client_status() == HTTPClient.STATUS_BODY and http.get_body_size() > 0:
		progress.value = 100.0 * http.get_downloaded_bytes() / http.get_body_size()
	if countdown >= 0.0:
		countdown -= delta
		play_button.text = "Play (starting in %d)" % ceili(maxf(countdown, 0.0))
		if countdown <= 0.0:
			countdown = -1.0
			_launch()


func _input(event: InputEvent) -> void:
	# Any click or key stops the auto-start so the player can roll back instead.
	if countdown >= 0.0 and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		countdown = -1.0
		play_button.text = "Play"


func check_for_update() -> void:
	_set_busy("Checking for updates...")
	# LANCER_RELEASE_URL points at a fake release for testing the launcher locally.
	var url := OS.get_environment("LANCER_RELEASE_URL")
	var err := await _get_text(url if url != "" else UpdateLogic.LATEST_RELEASE_URL)
	if err["error"] != "":
		_ready_to_play("Couldn't check for updates (%s)." % err["error"])
		return
	release = UpdateLogic.parse_release(err["body"])
	if release.has("error"):
		_ready_to_play(release["error"])
		return
	if release["version"] == logic.current_version() and logic.game_exe() != "":
		_ready_to_play("You have the latest version.", true)
		return
	await _download_and_install()


func _download_and_install() -> void:
	_set_busy("Downloading version %s..." % release["version"])
	var sums_reply := await _get_text(release["sums_url"])
	if sums_reply["error"] != "":
		_ready_to_play("Download failed (%s)." % sums_reply["error"])
		return
	var expected: String = UpdateLogic.parse_sums(sums_reply["body"]).get(release["zip_name"], "")
	if expected == "":
		_ready_to_play("The release is missing a checksum for its download, so it wasn't installed.")
		return
	DirAccess.make_dir_recursive_absolute(logic.downloads_dir())
	var zip_path: String = logic.downloads_dir() + "/" + release["zip_name"]
	http.download_file = zip_path
	progress.visible = true
	var err := http.request(release["zip_url"], _headers())
	var reply: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0]
	if err == OK:
		reply = await http.request_completed
	http.download_file = ""
	progress.visible = false
	if reply[0] != HTTPRequest.RESULT_SUCCESS or reply[1] != 200:
		_ready_to_play("Download failed (%s)." % _describe(reply[0], reply[1]))
		return
	_set_busy("Checking and installing version %s..." % release["version"])
	var problem := logic.install(zip_path, release["version"], expected)
	if problem != "":
		_ready_to_play(problem)
		return
	_ready_to_play("Updated to version %s." % release["version"], true)


func _ready_to_play(message: String, auto_start: bool = false) -> void:
	if OS.get_environment("LANCER_LAUNCHER_DRY_RUN") != "":
		# Testing the update logic (tools/launcher_dry_run.sh): say what happened, start nothing.
		print("LAUNCHER: %s | installed=%s previous=%s" % [message, logic.current_version(), logic.previous_version()])
		get_tree().quit()
		return
	var current := logic.current_version()
	var can_play := logic.game_exe() != ""
	status.text = message
	if can_play:
		detail.text = "Installed: %s" % current
	else:
		detail.text = "The game isn't installed yet."
	play_button.disabled = not can_play
	play_button.text = "Play"
	retry_button.visible = not auto_start
	var previous := logic.previous_version()
	rollback_button.visible = previous != "" and logic.game_exe(previous) != ""
	rollback_button.text = "Go back to %s" % previous
	if auto_start and can_play:
		countdown = AUTO_START_SEC
	if can_play:
		play_button.grab_focus()


func _set_busy(message: String) -> void:
	status.text = message
	countdown = -1.0
	play_button.disabled = true
	rollback_button.visible = false
	retry_button.visible = false


func _launch() -> void:
	var exe := logic.game_exe()
	if exe == "":
		return
	var pid := OS.create_process(ProjectSettings.globalize_path(exe), [])
	if pid <= 0:
		status.text = "Couldn't start the game."
		return
	get_tree().quit()


func _on_rollback() -> void:
	var problem := logic.rollback()
	_ready_to_play(problem if problem != "" else "Switched back to version %s." % logic.current_version())


## GETs a small text file. Returns {"error": "" or why, "body": String}.
func _get_text(url: String) -> Dictionary:
	if http.request(url, _headers()) != OK:
		return {"error": "no connection", "body": ""}
	var reply: Array = await http.request_completed
	if reply[0] != HTTPRequest.RESULT_SUCCESS or reply[1] != 200:
		return {"error": _describe(reply[0], reply[1]), "body": ""}
	return {"error": "", "body": (reply[3] as PackedByteArray).get_string_from_utf8()}


static func _headers() -> PackedStringArray:
	# GitHub's API requires a User-Agent.
	return PackedStringArray(["User-Agent: LancerTTRPG-Launcher", "Accept: application/vnd.github+json"])


static func _describe(result: int, code: int) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "no internet connection?" if result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE] else "network error %d" % result
	if code == 404:
		return "no release published yet"
	if code == 403 or code == 429:
		return "GitHub is limiting requests, try again in a few minutes"
	return "HTTP %d" % code


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 32
	box.offset_right = -32
	box.offset_top = 28
	box.offset_bottom = -28
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "LANCER TTRPG"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	box.add_child(title)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 18)
	box.add_child(status)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	box.add_child(detail)
	progress = ProgressBar.new()
	progress.visible = false
	box.add_child(progress)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	play_button = Button.new()
	play_button.custom_minimum_size = Vector2(220, 48)
	play_button.add_theme_font_size_override("font_size", 20)
	play_button.pressed.connect(_launch)
	row.add_child(play_button)
	rollback_button = Button.new()
	rollback_button.pressed.connect(_on_rollback)
	row.add_child(rollback_button)
	retry_button = Button.new()
	retry_button.text = "Check again"
	retry_button.pressed.connect(check_for_update)
	row.add_child(retry_button)
