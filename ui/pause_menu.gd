extends Control

var paused = false;

@onready var events_log: PauseMenuLogUI = %EventsLog
@onready var options_menu: PanelContainer = %OptionsMenu
@onready var pause_menu: Control = %PauseMenu
@onready var resume_button: Button = %Resume
@onready var exit_to_desktop_button: Button = %QuitToDesktop

@onready var round_director: RoundDirector = %RoundDirector


## Super secret cheat codes (shh!)
enum Keys{UP,DOWN,LEFT,RIGHT,SHOOT}
enum Cheats{
	FULL_HEALTH,
	FULL_AMMO,
	RELOCATE,
	LIGHTNING,
	GROW,
	SHRINK,
	INSTAKILL,
	NO_WIND,
	MAX_WIND,
	INSTAWIN,
	INSTALOSE,
	IMMATERIAL,
	}
var CheatCodes:Dictionary[Array, Cheats] = {
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.LEFT,Keys.RIGHT,Keys.LEFT,Keys.RIGHT]: Cheats.FULL_HEALTH,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.LEFT,Keys.UP,Keys.RIGHT,Keys.DOWN]: Cheats.RELOCATE,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.RIGHT,Keys.LEFT,Keys.RIGHT,Keys.LEFT]: Cheats.FULL_AMMO,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.RIGHT,Keys.RIGHT,Keys.RIGHT,Keys.DOWN]: Cheats.SHRINK,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.RIGHT,Keys.RIGHT,Keys.RIGHT,Keys.UP]: Cheats.GROW,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.RIGHT,Keys.RIGHT,Keys.LEFT,Keys.UP]: Cheats.INSTAKILL,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.UP,Keys.UP,Keys.UP,Keys.DOWN]: Cheats.LIGHTNING,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.UP,Keys.UP,Keys.LEFT,Keys.DOWN]: Cheats.NO_WIND,
	[Keys.UP,Keys.UP,Keys.DOWN,Keys.DOWN,Keys.UP,Keys.UP,Keys.RIGHT,Keys.DOWN]: Cheats.MAX_WIND,
	[Keys.DOWN,Keys.UP,Keys.DOWN,Keys.UP,Keys.RIGHT,Keys.UP,Keys.UP,Keys.UP]: Cheats.INSTAWIN,
	[Keys.DOWN,Keys.UP,Keys.DOWN,Keys.UP,Keys.RIGHT,Keys.DOWN,Keys.DOWN,Keys.DOWN]: Cheats.INSTALOSE,
	[Keys.LEFT,Keys.LEFT,Keys.RIGHT,Keys.RIGHT,Keys.LEFT,Keys.RIGHT,Keys.UP,Keys.RIGHT]: Cheats.IMMATERIAL,
}
var input_buffer:Array[Keys]
var input_buffer_listening:bool = false
var input_buffer_clearing_timer:Timer = Timer.new()
var input_buffer_clearing_timer_wait_time:float = 3.5

func _ready():
	input_buffer_clearing_timer.one_shot = true # We start this timer every time we capture an input.
	add_child(input_buffer_clearing_timer)
	input_buffer_clearing_timer.timeout.connect(_on_input_buffer_clearing_timer_timeout)

	if OS.get_name() == "Web":
		exit_to_desktop_button.hide()

	if not SceneManager.play_mode == SceneManager.PlayMode.PLAY_NOW:
		%PauseMenu.get_node("%NewGame").hide()
	hide()

# Called every frame. 'delta' is the elapsed time since the previous frame.
@warning_ignore("unused_parameter")
func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("pause"):
		toggle_visibility()

func _input(event: InputEvent) -> void:
	if paused && input_buffer_listening:
		var buffer_action:Keys
		if event.is_action_pressed("aim_left"): buffer_action = Keys.LEFT
		elif event.is_action_pressed("aim_right"): buffer_action = Keys.RIGHT
		elif event.is_action_pressed("power_increase"): buffer_action = Keys.UP
		elif event.is_action_pressed("power_decrease"): buffer_action = Keys.DOWN
		elif event.is_action_pressed("shoot"): buffer_action = Keys.SHOOT
		else:
			return
		input_buffer.append(buffer_action)
		while input_buffer.size() > 8:
			input_buffer.remove_at(0)
			continue
		# We want to force the user to enter a combination within a timeframe.
		if input_buffer_clearing_timer.is_stopped():
			input_buffer_clearing_timer.start(input_buffer_clearing_timer_wait_time)
		_check_cheat_code_entered(input_buffer)

func toggle_visibility():
	paused = !paused

	if paused:
		self.show()
		SceneManager.pause_game()
		#get_tree().paused = true
		#GameEvents.game_paused.emit(true)
		input_buffer_listening = true
		resume_button.call_deferred("grab_focus") ## Gamepad support
	else:
		self.hide()
		#get_tree().paused = false
		#GameEvents.game_paused.emit(false)
		SceneManager.pause_game(false)
		input_buffer_listening = false
	input_buffer.clear()


func _on_resume_pressed():
	toggle_visibility()

func _on_main_menu_pressed() -> void:
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.MainMenu, 0.0)

func _on_quit_to_desktop_pressed() -> void:
	#get_tree().quit()
	SceneManager.quit()

func _on_options_pressed() -> void:
	pause_menu.hide()
	options_menu.show()
	input_buffer_listening = false

func _on_options_menu_closed() -> void:
	pause_menu.show()
	options_menu.hide()
	input_buffer_listening = true
	resume_button.grab_focus() ## Gamepad support

func _on_new_game_pressed() -> void:
	# Start a new quick match

	#PlayerStateManager.enable = false
	#SceneManager.play_mode = SceneManager.PlayMode.PLAY_NOW

	var level: StoryLevel = SceneManager.levels_always_selectable.pick_random()
	if level:
		SceneManager.switch_scene_file(level.scene_res_path)


func _check_cheat_code_entered(code:Array[Keys]) -> void:
	if code in CheatCodes:
		var cheat_name:String

		match CheatCodes[input_buffer]:
			Cheats.FULL_HEALTH:
				cheat_name = "FULL HEALTH"
				# Give the player's Tank max health
				var tank = _get_player_controller().tank
				tank.health = tank.max_health

			Cheats.FULL_AMMO:
				cheat_name = "FULL AMMO"
				var current_weapon = _get_player_controller().tank.get_equipped_weapon()
				current_weapon.restock_ammo(99)

			Cheats.INSTAKILL:
				cheat_name = "INSTAKILL"
				var current_weapon = _get_player_controller().tank.get_equipped_weapon()
				current_weapon.enforce_projectile_property("damage_multiplier", 9999.9)

			Cheats.RELOCATE:
				cheat_name = "RELOCATE - TODO nonfunctional"
				# TODO ;)

			Cheats.LIGHTNING:
				cheat_name = "LIGHTNING"
				var level_root = SceneManager.get_current_level_root()
				if level_root is GameLevel:
					level_root.round_director.trigger_lightning()

			Cheats.GROW:
				cheat_name = "GROW"
				var tank = _get_player_controller().tank
				tank.apply_scale(Vector2(1.5,1.5))

			Cheats.SHRINK:
				cheat_name = "SHRINK"
				var tank = _get_player_controller().tank
				tank.apply_scale(Vector2(0.75,0.75))

			Cheats.NO_WIND:
				cheat_name = "WINDLESS"
				var level_root = SceneManager.get_current_level_root()
				if level_root is GameLevel:
					level_root.wind.wind = Vector2.ZERO

			Cheats.MAX_WIND:
				cheat_name = "SUPERBREEZE"
				var level_root = SceneManager.get_current_level_root()
				if level_root is GameLevel:
					var _sign:float = 1.0 if level_root.wind.wind.x >= 0.0 else -1.0
					level_root.wind.wind = Vector2(level_root.wind.wind_max * _sign, 0.0)
					
			Cheats.INSTAWIN:
				cheat_name = "PLATINUM CHIP"
				GameEvents.round_ended.emit()
				
			Cheats.INSTALOSE:
				cheat_name = "COURIER'S FATE"
				GameEvents.player_died.emit(_get_player_controller())
				GameEvents.round_ended.emit()
				
			Cheats.IMMATERIAL: 
				cheat_name = "LUKE'S GOODBYE"
				var tankBody = _get_player_controller().tank.tankBody
				tankBody.set_collision_layer_value(1, false)


		print_debug("-- CHEAT: ", cheat_name)
		events_log.record("CHEAT ENTERED: "+ cheat_name)

func _get_player_controller() -> Player:
	var player = null
	for unit in get_tree().get_nodes_in_group(Groups.Unit):
		if unit is Tank:
			if unit.controller is Player:
				player = unit.controller
				break
	return player

func _on_input_buffer_clearing_timer_timeout() -> void:
	input_buffer.clear()
