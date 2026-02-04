extends Control

@onready var receive_upgrade_button: ButtonUpgradeSelection = %ReceiveUpgradeButton
@onready var continue_button:Button = %ContinueButton
@onready var current_upgrades_panel: PanelContainer = %CurrentUpgradesPanel
@onready var everything: MarginContainer = %Everything
@onready var particles_container: Control = %ParticlesContainer
@onready var small_question_marks: CPUParticles2D = %SmallQuestionMarks
@onready var big_question_marks: CPUParticles2D = %BigQuestionMarks


func _ready() -> void:
	receive_upgrade_button.call_deferred("grab_focus") ## Gamepad support
	
	modulate = Color.BLACK
	#current_upgrades_panel.modulate = Color.TRANSPARENT
	current_upgrades_panel.hide()
	everything.modulate = Color.BLACK
	
	await Juice.fade_in(self, Juice.SMOOTH, Color.BLACK).finished
	Juice.fade_in(everything, Juice.PATIENT)
	
	_ready_cheats()
	
func _acquire_mod(button: ButtonUpgradeSelection) -> void:
	
	PlayerUpgrades.acquire_upgrade(button.get_mod_bundle())
	current_upgrades_panel.show()
	Juice.fade_out(receive_upgrade_button)
	Juice.fade_in(current_upgrades_panel)
	
	continue_button.disabled = false
	continue_button.grab_focus()


func _on_button_upgrade_random_selected(button: ButtonUpgradeSelection) -> void:
	_acquire_mod(button)
	
	input_buffer_listening = true
	
func _on_continue_button_pressed() -> void:
	input_buffer_listening = false
	
	Juice.fade_out(everything)
	if not SceneManager.deque_transition():
		SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryShop)
	
	# Prevent multiple clicks which will cause the wrong scenes to transition
	continue_button.disabled = true

## Cheats
## Super secret cheat codes (shh!)
enum Keys{UP,DOWN,LEFT,RIGHT,SHOOT}
enum Cheats{
	GIVE_RANDOM_UPGRADE,
	}
var CheatCodes:Dictionary[Array, Cheats] = {
	[Keys.RIGHT,Keys.LEFT,Keys.RIGHT,Keys.LEFT,Keys.DOWN,Keys.UP,Keys.DOWN,Keys.UP]: Cheats.GIVE_RANDOM_UPGRADE
}
var input_buffer:Array[Keys]
var input_buffer_listening:bool = false
var input_buffer_clearing_timer:Timer = Timer.new()
var input_buffer_clearing_timer_wait_time:float = 3.5

func _ready_cheats() -> void:
	input_buffer_clearing_timer.one_shot = true # We start this timer every time we capture an input.
	add_child(input_buffer_clearing_timer)
	input_buffer_clearing_timer.timeout.connect(_on_input_buffer_clearing_timer_timeout)

func _input(event: InputEvent) -> void:
	if input_buffer_listening:
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
		
func _check_cheat_code_entered(code:Array[Keys]) -> void:
	if code in CheatCodes:
		var cheat_name:String

		match CheatCodes[input_buffer]:
			Cheats.GIVE_RANDOM_UPGRADE:
				PlayerUpgrades.acquire_upgrade(PlayerUpgradesClass.generate_random_upgrade([ModBundle.Types.ANY]))

		print_debug("-- CHEAT: ", cheat_name)

func _on_input_buffer_clearing_timer_timeout() -> void:
	input_buffer.clear()
