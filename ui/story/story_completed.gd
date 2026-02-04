extends Control

@onready var run_header_label:Label = %RunHeaderLabel
@onready var yes_button:Button = %Yes
@onready var no_button:Button = %No
@onready var victory_texture:TextureRect = %VictoryImage
@onready var buttons_container:Container = %ButtonsContainer

func _ready() -> void:
	yes_button.call_deferred("grab_focus") ## Gamepad support
	
	_apply_tank_shader()

	var story_level_state:StoryLevelState = get_tree().get_first_node_in_group(Groups.STORY_LEVEL_STATE) as StoryLevelState
	if story_level_state:
		var run_count:int = story_level_state.run_count
		run_header_label.text = run_header_label.text.replace("%RUN%", str(run_count))
	else:
		push_error("%s: Could not find StoryLevelState node in tree" % name)

func _apply_tank_shader() -> void:
	# TODO: This can be swapped out for a better image. By default showing the player tank as victorious
	var texture_modulate:Color = Color(0xab/256.0, 0xff/256.0, 0x1a/256.0).darkened(0.3)
	# Set to player color
	var image_material:ShaderMaterial = victory_texture.material as ShaderMaterial
	if image_material:
		# Looks better with full range
		pass
		# image_material.set_shader_parameter(&"modulate", texture_modulate)
	else:
		victory_texture.modulate = texture_modulate

func _on_yes_pressed() -> void:
	print_debug("%s: Selected new run" % name)
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryMap)
	
	_disable_buttons()
	
func _on_no_pressed() -> void:
	print_debug("%s: Selected to end story" % name)
	# Don't delete save here so player has another chance to change mind on main menu
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.MainMenu)

	_disable_buttons()

func _disable_buttons() -> void:
	UIUtils.disable_all_buttons(buttons_container, 15.0)
