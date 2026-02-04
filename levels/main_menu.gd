extends Node2D

#region--Variables
@export var revealables:Array[Control] ## Will reveal their text as determined by reveal_speed

@export var credits_line_scroll_frequency:float = 1.5 ## In seconds, advances credits one line.
var _current_credits_list_line:int = 0

@onready var credits_list: RichTextLabel = %CreditsList
var credits_list_is_focused:bool = false

@onready var main_menu: VBoxContainer = %MainMenu
@onready var options_menu: Control = %Options
@onready var level_select_menu: LevelSelect = %LevelSelect
@onready var play_now: Button = %PlayNow
@onready var exit_to_desktop_button: Button = %Quit

@onready var soundtrack: AudioStreamPlayer = %Soundtrack
@onready var btn_continue_story:Button = %ContinueStory
@onready var buttons_container:Container = %MainMenuButtons
@onready var confirmation_dialog = %ARConfirmationDialog

#endregion


#region--Virtuals
func _init() -> void:
	modulate = Color.BLACK # For fade-in
	
func _ready() -> void:
	main_menu.visibility_changed.connect(_on_main_menu_visibility_changed)
	
	SceneManager.print_scene_tree_current_scene()
	main_menu.show()
	level_select_menu.hide()
	play_now.call_deferred("grab_focus") ## Gamepad support
	
	# Remove buttons that don't function on Web
	if OS.get_name() == "Web":
		exit_to_desktop_button.hide()
		
	# Only show continue story if there is an existing save
	btn_continue_story.disabled = not StorySaveUtils.story_save_exists()
	
	per_line_scroll_credits() # Autoscrolling
	start_typewriter_effect() # Typewriter effect
	soundtrack.play()
	
	# Fade in
	await get_tree().process_frame
	await Juice.fade_in(self, Juice.SMOOTH, Color.BLACK).finished
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), false) # Unmute SFX bus
#endregion

#region--Public Methods
func start_typewriter_effect() -> void:
	for node in revealables:
		TypewriterEffect.apply_to(node)
		
# Scrolls the credits automatically as it isn't focused (mouse hover).
func per_line_scroll_credits() -> void:
	var scroller = Timer.new()
	scroller.timeout.connect(_on_scroller_timeout)
	add_child(scroller)
	await get_tree().create_timer(credits_line_scroll_frequency*3).timeout # Let it populate a litte
	scroller.start(credits_line_scroll_frequency)
		
func _on_scroller_timeout() -> void:
	if credits_list_is_focused: return
	_current_credits_list_line += 1
	if _current_credits_list_line > credits_list.get_line_count():
		_current_credits_list_line = 0
	credits_list.scroll_to_line(_current_credits_list_line)
#endregion

#region--Private Methods
func _on_play_now_pressed() -> void:
	PlayerStateManager.enable = false
	SceneManager.play_mode = SceneManager.PlayMode.PLAY_NOW
	
	var level: StoryLevel = SceneManager.levels_always_selectable.pick_random()
	if level:
		SceneManager.switch_scene_file(level.scene_res_path, 0.0)
		_disable_buttons()

func _on_story_pressed() -> void:
	print_debug("New Story Pressed")
	if StorySaveUtils.story_save_exists():
		confirmation_dialog.set_text("Are you sure you want to start a new story?\n This will overwrite your current story progress.")
		confirmation_dialog.confirmed.connect(_on_new_story_confirmed)
		confirmation_dialog.canceled.connect(_on_new_story_canceled) # Disconnect to avoid multiple connections
		confirmation_dialog.popup_centered()
	else:
		_new_story()

func _on_new_story_confirmed() -> void:
	_new_story()
	confirmation_dialog.confirmed.disconnect(_on_new_story_confirmed)
	
func _on_new_story_canceled() -> void:
	print_debug("New story canceled")
	confirmation_dialog.confirmed.disconnect(_on_new_story_confirmed)
	confirmation_dialog.canceled.disconnect(_on_new_story_canceled)
	
func _new_story() -> void:
	SaveStateManager.start_new_story_with_new_save()
	_disable_buttons()

func _on_level_select_pressed() -> void:
	print_debug("Level select button")
	PlayerStateManager.enable = false
	SceneManager.play_mode = SceneManager.PlayMode.LEVEL_SELECT

	level_select_menu.show()
	main_menu.hide()

func _on_options_pressed() -> void:
	print_debug("Options button")

	options_menu.show()
	main_menu.hide()

func _on_quit_pressed() -> void:
	_disable_buttons()
	get_tree().quit()
	
func _on_options_menu_closed() -> void:
	print_debug("Options menu closed -- main menu")

	options_menu.hide()
	main_menu.show()

func _on_credits_list_mouse_entered() -> void:
	credits_list_is_focused = true

func _on_credits_list_mouse_exited() -> void:
	credits_list_is_focused = false


func _on_continue_story_pressed() -> void:
	if btn_continue_story.disabled:
		print_debug("Continue story button is disabled")
		return
		
	PlayerStateManager.enable = true
	SceneManager.play_mode = SceneManager.PlayMode.STORY

	SaveStateManager.add_state_flag(SceneManager.continue_story_selected)
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryMap, 0.0)
	
	_disable_buttons()

func _disable_buttons() -> void:
	UIUtils.disable_all_buttons(buttons_container, 20.0)

func _on_main_menu_visibility_changed() -> void:
	if main_menu.visible:
		play_now.grab_focus()
