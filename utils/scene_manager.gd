extends Node

signal game_quit

@export var level_resources_always_selectable: Array[StoryLevelsResource] ## These levels are immediately & always available to select.

# Don't use PackedScene as we don't want all the scene data to be preloaded at the start of the game
@export var story_levels: StoryLevelsResource

var levels_always_selectable: Array[StoryLevel] = []

var is_switching_scene: bool
var is_precompiler_running:bool = false
var is_quitting_game: bool = false

enum PlayMode {
	DIRECT, # Happens with playing level directly
	STORY,
	PLAY_NOW,
	LEVEL_SELECT
}

var is_running_on_steam_deck:bool:
	get:
		if OS.get_processor_name() == "AMD Custom APU 0405":
			return true
		else:
			return false
			

class SceneKeys:
	const MainMenu:StringName = &"MainMenu"
	#const PauseMenu:StringName = &"PauseMenu"
	const RandomStart:StringName = &"RandomStart"
	
	const StoryMap:StringName = &"StoryMap"
	const StoryComplete:StringName = &"StoryComplete"
	const StoryStart:StringName = &"StoryStart"
	const StoryDifficultySelect:StringName = &"StoryDifficultySelect"
	const RoundSummary:StringName = &"RoundSummary"
	const StoryShop:StringName = &"StoryShop"
	const UpgradeSelect:StringName = &"UpgradeSelect"

	const GameOver:StringName = &"GameOver"

# We expect to reference the above keys with a const "preload" of a packed scene 
# or reference to a unique name (possibly for pause menu)

const default_delay: float = 2.0

const main_menu_scene_file = "res://levels/main_menu.tscn"

# Story mode scenes
const story_start_scene_file = "res://ui/story/story_sequence.tscn"
const story_map_scene_file = "res://ui/story/map/story_map_scene.tscn"
const story_complete_scene_file = "res://ui/story/story_completed.tscn"
const story_round_summary_scene_file = "res://ui/story/round_summary/story_round_summary.tscn"
const story_difficulty_select_scene_file = "res://ui/story/story_difficulty_select.tscn"
const upgrade_select_scene_file = "res://progression/upgrade_select.tscn"
const story_shop_scene_file = "res://ui/story/shop/story_shop.tscn"

const game_over_scene_file = "res://levels/game_over.tscn"

## CRITICAL
var _current_level_root_node:GameLevel
var _current_story_level:StoryLevel

var _current_level_index:int = -1
var next_level_index:int:
	get: return 0 if is_on_last_story_level() else _current_level_index + 1

var _scene_queue:Array[Callable] = []

var play_mode:PlayMode:
	set(value):
		if play_mode != value:
			var old_value:PlayMode = play_mode
			play_mode = value
			GameEvents.play_mode_changed.emit(old_value, play_mode)
	get: return play_mode

const new_story_selected:StringName = &"NewStory"
const continue_story_selected:StringName = &"ContinueStory"

var current_scene:Node = null:
	get: return current_scene if current_scene else get_current_game_scene_root()
	set(value):
		current_scene = value
		
var is_current_scene_set:bool = false

var current_story_level:StoryLevel:
	get:
		return _current_story_level if play_mode == PlayMode.STORY else null
	
var story_level_state:StoryLevelState:
	get:
		return get_tree().get_first_node_in_group(Groups.STORY_LEVEL_STATE) as StoryLevelState
		
# Any scene, even if it is a UI scene and not a game level scene
var _last_scene_resource:Resource

# Only the last game level scene
var _last_game_level_resource:Resource

@onready var loading_bg: ColorRect = $LoadingBG

func _enter_tree() -> void:
	get_tree()

func _ready()->void:
	GameEvents.level_loaded.connect(_on_GameLevel_loaded)
	loading_bg.hide()

	_init_selectable_levels()
	
	## Check if we loaded a level directly instead of launching the game normally
	check_for_directly_loaded_level()
	
func check_for_directly_loaded_level() -> void:
	## Check if the current scene is set (typically only when launching the game normally)
	## Otherwise move the scene to the InternalSceneRoot and set our reference
	await get_tree().process_frame
	if get_tree().current_scene:
		if not is_current_scene_set:
			push_warning("Loaded level external to SceneManager. Capturing and reloading level.")
			# Force reload and reinstance
			# Find the current scene directly instanced
			var _current_scene_file_path: String = get_tree().current_scene.scene_file_path
			get_tree().unload_current_scene()
			instantiate_scene_to_internal_root(load(_current_scene_file_path))
			get_tree().current_scene = InternalSceneRoot
			push_warning("Killed and reinstanced scene tree current scene to InternalSceneRoot! You may see some warnings for any callbacks from the initial instance.")
			print_scene_tree_current_scene()
			GameEvents.scene_switched.emit(get_current_game_scene_root())
	else:
		get_tree().current_scene = InternalSceneRoot
		print_scene_tree_current_scene()
	
func set_current_scene(node: Node) -> void:
	if node.is_inside_tree():
		current_scene = node
		is_current_scene_set = true
	else:
		push_error("Node is not inside tree!")
	
func _init_selectable_levels() -> void:
	levels_always_selectable.clear()
	var unique_levels:Dictionary[String,bool] = {}

	for resource in level_resources_always_selectable:
		if not resource:
			continue
		for level in resource.levels:
			if level and level.scene_res_path and level.name and level.name not in unique_levels:
				unique_levels[level.name] = true
				levels_always_selectable.push_back(level)
	
	levels_always_selectable.sort_custom(func(a,b)->bool: return a.name < b.name)
	
## This method returns the current scene root, regardless of being in a GameLevel or not.
## Use this when you don't care if we're inside a level, for example if we're in a UI scene
## such as round_summary, the upgrade or item shop, etc.
func get_current_game_scene_root() -> Node:
	assert(InternalSceneRoot, "Null internal scene root!")
	
	if not InternalSceneRoot.get_child_count() > 0:
		push_warning("Access outside of a game scene! May create orphan nodes!")
		return InternalSceneRoot ## May create orphans
	else:
		return InternalSceneRoot.get_child(0)

## This method returns a GameLevel type node, if the current scene is a GameLevel (we're in a round of artillery rampage).
## Otherwise returns null. Use this method when you are only looking for the GameLevel scene root.
func get_current_level_root() -> GameLevel:
	#assert(is_instance_valid(_current_level_root_node), "Trying to access root outside of game level.")
	
	if is_instance_valid(_current_level_root_node):
		if _current_level_root_node.is_inside_tree():
			return _current_level_root_node
			
	if not is_precompiler_running:
		push_warning("Trying to access root outside of game level or precompiler!")
		
	_current_level_root_node = null
	return null

func quit() -> void:
	is_quitting_game = true
	game_quit.emit()
	get_tree().quit()
	
func restart_level(delay: float = default_delay) -> void:
	print_debug("restart_level: %s, delay=%f" % [str(_current_level_root_node.name) if _current_level_root_node else "Not In A Game Level!", delay])

	if not _last_game_level_resource:
		push_error("restart_level: No last game level resource to restart")
		return

	await _switch_scene(func()->Resource: return _last_game_level_resource, delay)
	
func next_level(delay: float = default_delay) -> void:
	if !story_levels or !story_levels.levels:
		push_error("No levels available to load")
		return
	# TODO: When using procedural maps may need a different strategy or may want to shuffle the levels on start
	# The procedural map could just be a specific scene that has some base configuration and then generates on ready
	# Or we could start proc-gening the next scene during current scene and then just keep in memory and present it here
	_current_level_index = (_current_level_index + 1) % story_levels.levels.size()
	_current_story_level = story_levels.levels[_current_level_index]
	
	GameEvents.story_level_changed.emit(_current_level_index)

	print_debug("Loading story level index=%d -> %s" % [_current_level_index, _current_story_level.name])

	await switch_scene_file(_current_story_level.scene_res_path, delay)
	
func set_story_level_index(index:int) -> bool:
	# Allowing -1 to reset the state
	if index >= -1 and index < story_levels.levels.size():
		print_debug("set story level index=%d" % [index])
		_current_level_index = index
		GameEvents.story_level_changed.emit(_current_level_index)
		return true
	push_warning("Attempted to set invalid story level index=%d - expected [0, %d)" % [index, story_levels.levels.size()])
	return false

func is_on_last_story_level() -> bool:
	if not play_mode == PlayMode.STORY or not story_levels.levels:
		return false
	return _current_level_index == story_levels.levels.size() - 1

## Pushes a scene transition to the scene queue by func_name on the SceneManager and arguments it should take
func queue_transition(func_name:String, args: Array = []) -> void:
	_scene_queue.push_back(Callable.create(self, func_name).bindv(args))

## Dequeues and executes a scene transition if the scene callable queue is not empty; otherwise, returns false
func deque_transition() -> bool:
	if not _scene_queue.is_empty():
		print_debug("Dequeue scene transition: queue_size=%d" % _scene_queue.size())
		var transition:Callable = _scene_queue.pop_front()
		transition.call()
		return true
	print_debug("Dequeue scene transition: queue empty - return false")
	return false

## Clears any scene transitions from the queue
func clear_transitions() -> void:
	_scene_queue.clear()

# TODO: May move these branches out of the scene manager to keep it more single responsiblity
func level_failed() -> void:
	match play_mode:
		PlayMode.STORY:
			switch_scene_keyed(SceneKeys.RoundSummary)
		PlayMode.DIRECT:
			_default_restart_level()
		_: # default
			restart_level()
			
func _default_restart_level():
	await get_tree().create_timer(default_delay).timeout
	_reload_current_scene()
	
func _reload_current_scene() -> void:
	unload_current_game_scene()
	instantiate_scene_to_internal_root(_last_scene_resource)
	
func unload_current_game_scene() -> void:
	if not current_scene or current_scene == InternalSceneRoot:
		push_error("No current scene to unload!")
		return
	# Free immmediately to avoid race conditions with tree exit and loading of next scene
	current_scene.free()
	current_scene = null
	
func instantiate_scene_to_internal_root(scene: PackedScene) -> void:
	if scene.can_instantiate() and InternalSceneRoot:
		var instance: Node = scene.instantiate()
		
		## These variables must be set before add_child() otherwise the 
		## _ready functions get called before these are set. i think ;)
		_last_scene_resource = scene
		current_scene = instance
		
		InternalSceneRoot.add_child(instance, true)
	else:
		push_error("Can't instantiate!")
		return
	
func level_complete() -> void:
	match play_mode:
		PlayMode.DIRECT:
			_default_restart_level()
		PlayMode.STORY:
			await switch_scene_keyed(SceneKeys.RoundSummary)
		PlayMode.PLAY_NOW:
			# TODO: Logic duplication, possibly different set of levels with PlayNow logic in MainMenu, should consolidate
			if story_levels and story_levels.levels:
				await switch_scene_file(story_levels.levels.pick_random().scene_res_path)
			else:
				restart_level()
		PlayMode.LEVEL_SELECT:
			await switch_scene_keyed(SceneKeys.MainMenu)
			
func switch_scene_keyed(key : StringName, delay: float = default_delay) -> void:
	match key:
		SceneKeys.MainMenu:
			await switch_scene_file(main_menu_scene_file, delay, func() -> void:
				clear_transitions()
				# Clear out the play mode when going back to main menu
				play_mode = PlayMode.DIRECT
				PlayerStateManager.enable = false
				# Make sure option state loaded
				SaveStateManager.restore_node_state(UserOptions, UserOptions.name)
			)
		SceneKeys.RandomStart:
			await next_level(delay)
		SceneKeys.StoryStart:
			_current_level_index = -1
			await switch_scene_file(story_start_scene_file, delay)
		SceneKeys.StoryDifficultySelect:
			await switch_scene_file(story_difficulty_select_scene_file, delay)
		SceneKeys.UpgradeSelect:
			await switch_scene_file(upgrade_select_scene_file, delay)
		SceneKeys.StoryShop:
			await switch_scene_file(story_shop_scene_file, delay)
		SceneKeys.StoryMap:
			await switch_scene_file(story_map_scene_file, delay)
		SceneKeys.StoryComplete:
			await switch_scene_file(story_complete_scene_file, delay)
		SceneKeys.RoundSummary:
			await switch_scene_file(story_round_summary_scene_file, delay)
		SceneKeys.GameOver:
			await switch_scene_file(game_over_scene_file, delay)
		_:
			push_error("Unhandled scene key=%s" % [key])
	
func switch_scene(scene: PackedScene, delay: float = default_delay, before_load:Callable = Callable()) -> void:
	var display_name = str(scene)
	print_debug("switch_scene: %s, delay=%f" % [display_name, delay])
	await _switch_scene(
		func()->Resource:
			if before_load:
				before_load.call()
			return scene,
	 delay)
	
func switch_scene_file(scene: String, delay: float = default_delay, before_load:Callable = Callable()) -> void:
	print_debug("switch_scene_file: %s, delay=%f" % [scene, delay])
	# TODO: Consider using resource loader to load async during the delay period
	await _switch_scene(
		func()->Resource:
			if before_load:
				before_load.call()
			return load(scene), 
	delay)

func _switch_scene(switchFunc: Callable, delay: float) -> void:
	if is_switching_scene:
		return
	
	SaveStateManager.save_tree_state(SaveState.ContextTriggers.SCENE_SWITCH)
	
	# Avoid two events causing a restart in the same game (e.g. player dies and leaves 1 player remaining)
	is_switching_scene = true
	
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	else:
		await get_tree().process_frame
	
	#var root = get_tree().root
	await loading_screen(true)
	
	GameEvents.scene_leaving.emit(current_scene)
	unload_current_game_scene()
	is_switching_scene = false

	if OS.is_debug_build():
		await get_tree().process_frame
		print_debug("**********BEGIN ORPHAN NODES**********")
		print_orphan_nodes()
		print_debug("**********END ORPHAN NODES**********")

	# Await in case the loading is done async
	var new_scene:Resource = await switchFunc.call()
	
	instantiate_scene_to_internal_root(new_scene)
	GameEvents.scene_switched.emit(current_scene)

	SaveStateManager.restore_tree_state(SaveState.ContextTriggers.SCENE_SWITCH)
	loading_screen(false)
	pause_game(false)
	
func pause_game(paused:bool = true) -> void:
	#get_tree().paused = paused ## FIXME VR
	if paused:
		InternalSceneRoot.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		InternalSceneRoot.process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.game_paused.emit(paused)

func _on_GameLevel_loaded(level:GameLevel) -> void:
	print_debug("_on_GameLevel_loaded: level=%s" % [str(level.get_parent().name) if level else "NULL"])
	
	if _current_story_level:
		level.name = _current_story_level.name
		
	_current_level_root_node = level

	_last_game_level_resource = _last_scene_resource

func loading_screen(_visible:bool) -> bool:
	if not is_instance_valid(loading_bg): return false
	if _visible:
		var fade_in = Juice.fade_in(loading_bg)
		for child in loading_bg.get_children():
			Juice.fade_in(child, Juice.LONG)
		loading_bg.show()
		await fade_in.finished
		return true
	else:
		loading_bg.hide()
		return true

func get_spawnables_container() -> Node2D:
	if get_current_level_root():
		return get_current_level_root().get_container()
	else:
		return get_current_game_scene_root()

func print_scene_tree_current_scene() -> void:
	push_warning("Scene Tree current scene is %s." % [get_tree().current_scene])
