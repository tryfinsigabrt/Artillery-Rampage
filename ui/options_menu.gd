extends Control

signal closed

@onready var configure_keybinds_button: Button = %ConfigureKeybindsButton
@onready var show_tooltips_toggle: CheckButton = %ShowTooltipsToggle
@onready var show_hud_toggle: CheckButton = %ShowHUDToggle
@onready var show_trajectory_toggle: CheckButton = %ShowTrajectoryToggle
@onready var enable_screenshake_toggle:CheckButton = %EnableScreenshakeToggle

@onready var difficulty_option:OptionButton = %DifficultyOption

@onready var music_volume_slider: HSlider = %MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = %SFXVolumeSlider
@onready var speech_volume_slider: HSlider = %SpeechVolumeSlider

@onready var options: VBoxContainer = $Options
@onready var keybinds: PanelContainer = $Keybinds
@onready var keybind_labels: VBoxContainer = %KeybindLabels
@onready var keybind_glyphs: VBoxContainer = %KeybindGlyphs

@onready var keybind_changing: PanelContainer = $Keybinds/KeybindChanging
@onready var keybind_changing_label: Label = %KeybindChangingLabel
@onready var keybind_changing_glyph: Label = %KeybindChangingGlyph

@onready var apply_button: Button = %Apply

var cached_music_volume: float
var cached_sfx_volume: float
var cached_speech_volume: float

var capturing_input:bool = false
var _last_input_event:InputEvent

func _ready() -> void:
	set_initial_states()
	options.show()
	keybinds.hide()
	keybind_changing.hide()
	keybind_changing.visibility_changed.connect(_on_keybind_changing_visibility_changed)
	
	visibility_changed.connect(_on_visibility_changed)
	
func _on_visibility_changed() -> void:
	if visible:
		apply_button.call_deferred("grab_focus") ## Gamepad support
	
func _input(event: InputEvent) -> void:
	# Keybind Change Window
	if capturing_input:
		# This prevents assignment to mouse controls
		if event is InputEventMouseMotion: return # If you put these in one line with an
		if event is InputEventMouseButton: return # "Or" operator it blocks all inputs?? Lol
		if event.is_pressed():
			_on_keybind_changing_input_pressed(event)
		get_viewport().set_input_as_handled()

func set_initial_states() -> void:
	# Each option
	show_tooltips_toggle.set_pressed_no_signal(UserOptions.show_tooltips)
	show_hud_toggle.set_pressed_no_signal(UserOptions.show_hud)
	show_trajectory_toggle.set_pressed_no_signal(UserOptions.show_assist_trajectory_preview)
	enable_screenshake_toggle.set_pressed_no_signal(UserOptions.enable_screenshake)
	
	set_initial_value(difficulty_option, int(UserOptions.difficulty))
	
	music_volume_slider.set_value_no_signal(UserOptions.volume_music)
	sfx_volume_slider.set_value_no_signal(UserOptions.volume_sfx)
	speech_volume_slider.set_value_no_signal(UserOptions.volume_speech)
	
	cached_music_volume = music_volume_slider.value
	cached_sfx_volume = sfx_volume_slider.value
	cached_speech_volume = speech_volume_slider.value
	
func set_initial_value(option_button:OptionButton, index: int):
	option_button.set_block_signals(true)  # Prevent event firing
	option_button.select(index)
	option_button.set_block_signals(false)  # Re-enable signals
	
func apply_changes() -> void:
	# Apply all options
	UserOptions.show_tooltips = show_tooltips_toggle.is_pressed()
	UserOptions.show_hud = show_hud_toggle.is_pressed()
	UserOptions.show_assist_trajectory_preview = show_trajectory_toggle.is_pressed()
	UserOptions.enable_screenshake = enable_screenshake_toggle.is_pressed()
	
	if difficulty_option.selected >= 0:
		UserOptions.difficulty = difficulty_option.selected as Difficulty.DifficultyLevel
	
	UserOptions.volume_music = music_volume_slider.value
	UserOptions.volume_sfx = sfx_volume_slider.value
	UserOptions.volume_speech = speech_volume_slider.value
	apply_volume_settings_to_audio_bus()
	
	# Emit signal
	GameEvents.user_options_changed.emit()
	
func apply_volume_settings_to_audio_bus() -> void:
	var music_bus = AudioServer.get_bus_index("Music")
	var sfx_bus = AudioServer.get_bus_index("SFX")
	var speech_bus = AudioServer.get_bus_index("Speech")
	
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(UserOptions.volume_music))
	AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(UserOptions.volume_sfx))
	AudioServer.set_bus_volume_db(speech_bus, linear_to_db(speech_volume_slider.value))
	
func reset_changed_cached_settings() -> void:
	sfx_volume_slider.value = cached_sfx_volume
	music_volume_slider.value = cached_music_volume
	speech_volume_slider.value = cached_speech_volume
	apply_volume_settings_to_audio_bus()
	
func close_options_menu() -> void:
	closed.emit()

func _on_apply_pressed() -> void:
	apply_changes()
	close_options_menu()

func _on_cancel_pressed() -> void:
	reset_changed_cached_settings()
	close_options_menu()

func populate_keybinds_ui() -> void:
	## Clear old data
	for child in keybind_labels.get_children() + keybind_glyphs.get_children(): # Didn't know i could do this, cool
		child.queue_free()
	
	## Get all keybinds and display them
	var map: Array[StringName] = UserOptions.get_all_keybinds() # InputMap.get_actions()
	#print_debug(map)
	
	for action in map:
		# We're doing Glyph (right column) first in order to get its minimum size, to scale
		# the Label properly. Kind of a workaround, there's probably a way to set fixed size.
		
		## Glyph
		var inputs: Array[InputEvent] = InputMap.action_get_events(action)
		var text: String = ""
		for input: InputEvent in inputs:
			if not text.is_empty(): text += ", " # Add a separator
			text += input.as_text()
			
		var glyph = Button.new()
		glyph.text = text
		glyph.pressed.connect(_on_keybinds_changing.bind(action))
		keybind_glyphs.add_child(glyph)
		
		## Label
		var label = Label.new()
		label.text = action
		label.custom_minimum_size.y = glyph.get_combined_minimum_size().y
		keybind_labels.add_child(label)

func _on_configure_keybinds_button_pressed() -> void:
	populate_keybinds_ui()
	keybinds.show()

func _on_keybinds_confirm_changes_pressed() -> void:
	# TODO apply changes
	keybinds.hide()

func _on_keybinds_cancel_pressed() -> void:
	keybinds.hide()

func _on_keybinds_reset_all_pressed() -> void:
	UserOptions.reset_all_keybinds_to_default()
	keybinds.hide()
	_on_configure_keybinds_button_pressed() # Reload


func _on_music_volume_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		var music_bus = AudioServer.get_bus_index("Music")
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(music_volume_slider.value))

func _on_sfx_volume_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		var sfx_bus = AudioServer.get_bus_index("SFX")
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(sfx_volume_slider.value))
		
func _on_speech_volume_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		var speech_bus = AudioServer.get_bus_index("Speech")
		AudioServer.set_bus_volume_db(speech_bus, linear_to_db(speech_volume_slider.value))
		
## Keybinds Changing Window
func _on_keybinds_changing(action: StringName) -> void:
	print_debug(action)
	
	keybind_changing.show()
	keybind_changing_label.text = action
	keybind_changing_glyph.text = str(UserOptions.get_glyphs(action))
	
func _on_keybind_changing_visibility_changed() -> void:
	# We need to capture the users inputs if this window is showing to prevent it from
	# doing unintended things.
	if keybind_changing.visible:
		capturing_input = true
		print_debug("Capturing user inputs...")
	else:
		capturing_input = false
		print_debug("Released input capture...")
		# Refresh the UI in case we changed something
		populate_keybinds_ui()
		
func _on_keybind_changing_input_pressed(event: InputEvent) -> void:
	print(event)
	_last_input_event = event
	keybind_changing_glyph.text = event.as_text()
	
func _on_keybind_changing_cancel_pressed() -> void:
	keybind_changing.hide()

func _on_keybind_changing_apply_pressed() -> void:
	# Assign the keybind
	# TODO multiple keybinds
	UserOptions.change_keybind(keybind_changing_label.text, _last_input_event)
	keybind_changing.hide()
