extends Node
const CONFIG_PATH = "user://settings.cfg"
var selected_character: String = "mascot"
var bgm_volume:	 float  = 0.7
var difficulty:	 String = "normal"
var dummy_mode:	 bool   = false
var hp_lock:		bool   = false
var dev_mode:	   bool   = false
var learn_mode:	 bool   = false
var total_dmg:	  int	= 0
var _dmg_log:	   Array  = []

func reset_stats() -> void:
	total_dmg = 0
	_dmg_log.clear()

func record_damage(amount: int) -> void:
	total_dmg += amount
	_dmg_log.append({"t": Time.get_ticks_msec() / 1000.0, "a": amount})

func get_dps(window: float = 3.0) -> float:
	var now	:= Time.get_ticks_msec() / 1000.0
	var cutoff := now - window
	while not _dmg_log.is_empty() and float((_dmg_log[0] as Dictionary)["t"]) < cutoff:
		_dmg_log.pop_front()
	var sum := 0
	for entry in _dmg_log:
		sum += int((entry as Dictionary)["a"])
	return float(sum) / window

func sync_audio_volume() -> void:
	var bus_idx = AudioServer.get_bus_index("Master")
	if bus_idx != -1:
		var db = linear_to_db(bgm_volume) if bgm_volume > 0.0001 else -80.0
		AudioServer.set_bus_volume_db(bus_idx, db)

func save_settings() -> void:
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("settings", "master_volume", bgm_volume)
	config.set_value("settings", "learn_mode", learn_mode)
	# Fullscreen is handled by MainMenu usually, but we can store it here too
	var is_fs = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	config.set_value("settings", "fullscreen", is_fs)
	config.save(CONFIG_PATH)

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	if err == OK:
		bgm_volume = config.get_value("settings", "master_volume", 0.7)
		learn_mode = config.get_value("settings", "learn_mode", false)
		var fs = config.get_value("settings", "fullscreen", false)
		if fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sync_audio_volume()
