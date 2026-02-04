class_name StorySequence extends Control

var current_slide:int = 0
var total_slides:int:
	get: return %StorySlides.get_children().size()

@onready var slides:Array = %StorySlides.get_children()
var texts:Array[Control]
@onready var next_button: Button = %NextButton
@onready var skip_button:Button = %SkipButton

var auto_narrative = preload("res://narrative/auto_narrative.tscn")
var button_highlight_tween
var playing:Array = [] # For stopping playing SFX

func _ready() -> void:
	auto_narrative = auto_narrative.instantiate()
	add_child(auto_narrative)
	next_button.pressed.connect(_on_next)
	skip_button.pressed.connect(_on_skip)
	
	# Find all the text controls, add to an array for the typewriter effect, &
	# replace keywords using the auto_narrative.
	for slide in slides:
		for child in slide.get_children():
			if child is RichTextLabel or child is Label:
				texts.append(child)
				child.text = auto_narrative.replace_story_keywords(child.text)
		slide.hide()
	next_slide()
	
func next_slide() -> void:
	next_button.grab_focus() ## Gamepad support
	# Stop any playing audio players
	for player in playing:
		player.stop()
	playing.clear()
	
	if not current_slide == 0:
		%StorySlides.get_child(current_slide-1).hide()
	TypewriterEffect.apply_to(texts[current_slide])
	
	var this_slide = %StorySlides.get_child(current_slide)
	this_slide.show()
	current_slide += 1
	
	# Play any children audio players
	var found:bool = false
	for child in this_slide.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			child.play()
			playing.append(child)
			found = true
			
	# Play the generic radio sound if there are no children audio players for this slide
	if not found: %Radio.play()
	
	if button_highlight_tween: button_highlight_tween.kill()
	# This makes a slow flashing effect
	button_highlight_tween = create_tween()
	button_highlight_tween.tween_property(%NextButton, "modulate", %NextButton.modulate, Juice.SMOOTH).from(Color.TRANSPARENT)
	button_highlight_tween.tween_property(%NextButton, "modulate", %NextButton.modulate, Juice.PATIENT).from(Color.TRANSPARENT)
	button_highlight_tween.tween_property(%NextButton, "modulate", %NextButton.modulate, Juice.SLOW).from(Color.TRANSPARENT)
func _on_next() -> void:
	#print_debug("on_next")
	if current_slide < total_slides:
		next_slide()
	else:
		await _go_to_next_scene()
	
func _on_skip() -> void:
	print_debug("on_skip")
	await _go_to_next_scene()

	
func _go_to_next_scene() -> void:
	await SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryDifficultySelect, 0)
