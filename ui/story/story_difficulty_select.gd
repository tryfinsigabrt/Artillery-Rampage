extends Control

@onready var buttons_container:Container = %DifficultySelectContainer
@onready var normal_button: Button = %Normal

func _ready() -> void:
	normal_button.call_deferred("grab_focus") ## Gamepad support

func _on_easy_pressed() -> void:
	_start_story(Difficulty.DifficultyLevel.EASY)

func _on_normal_pressed() -> void:
	_start_story(Difficulty.DifficultyLevel.NORMAL)

func _on_hard_pressed() -> void:
	_start_story(Difficulty.DifficultyLevel.HARD)

func _start_story(difficulty: Difficulty.DifficultyLevel) -> void:
	UserOptions.difficulty = difficulty
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryMap)

	UIUtils.disable_all_buttons(buttons_container)
