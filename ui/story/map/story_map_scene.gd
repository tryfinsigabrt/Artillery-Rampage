class_name StoryMapScene extends Control

#region Prototypes
@export_group("Prototypes")
@export var edge_node_prototype:PackedScene
@export var default_node_prototype:PackedScene
@export var unknown_node_prototype:PackedScene
@export var incomplete_level_material:Material
#endregion

@export var margins:Vector2 = Vector2(20.0,20.0)
@export var min_edge_length:float = 25.0
@export var max_edge_length:float = 150.0
@export var edge_dir_max_count:Vector2i = Vector2i(3, 5)

@export_group("")

@onready var graph_container: Control = %LevelNodesContainer
@onready var tooltipper:TextSequence = %StoryTooltips

# TODO: This probably belongs more on the round summary but experimenting with it here
@onready var auto_narrative:AutoNarrative = %AutoNarrative

@onready var personnel_hud:HUDElement = %PersonnelHUD
@onready var scrap_hud:HUDElement = %ScrapHUD
@onready var health_hud:HUDElement = %HealthHUD
@onready var next_button = %NextButton

@export_group("Parallax", "parallax_")
@export var parallax_layers:Array[CanvasItem] ## node reference
var _parallax_layers: Array[Vector2] ## starting global position. This could probably be a dict but I'm small brain
var _center_node_offset:Vector2
@export var parallax_amount:float = 0.1
@export var parallax_layer_factor:float = 1.0

var _story_levels_resource:StoryLevelsResource
var _next_level_index:int

func _ready() -> void:		
	for layer in parallax_layers:
		_parallax_layers.append(layer.global_position)
		
	Juice.fade_in(next_button, Juice.LONG)
	next_button.call_deferred("grab_focus") ## Gamepad support
		
func _process(_delta: float) -> void:
	for layer_id in parallax_layers.size():
		parallax_layers[layer_id].global_position = _parallax_layers[layer_id] - _center_node_offset + (
			get_global_mouse_position() - _get_center_screen()
			) * (parallax_amount + (layer_id * parallax_layer_factor) / 4.0)
			
	
func _get_center_screen() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5

#region Savable

const SAVE_STATE_KEY:StringName = &"StoryMap"
var _save_state:SaveState

func update_save_state(save:SaveState) -> void:
	var story_state:Dictionary = StorySaveUtils.get_story_save(save, true)
	story_state[SAVE_STATE_KEY] = _create_save_state()

func restore_from_save_state(save: SaveState) -> void:
	_save_state = save
	_update()
	_save_state = null

func _create_save_state() -> Dictionary:
	# Save node positions
	var state:Dictionary = {}
	var nodes:PackedVector2Array = []

	for child in graph_container.get_children():
		if child is StoryLevelNode:
			nodes.push_back(child.position)

	state["nodes"] = nodes
	return state

func _get_save_state() -> StoryMapSaveState:
	var story_state:Dictionary = StorySaveUtils.get_story_save(_save_state)
	if not story_state or not story_state.has(SAVE_STATE_KEY) or SaveStateManager.consume_state_flag(SceneManager.new_story_selected, SAVE_STATE_KEY):
		return null

	var saved_state:Dictionary = story_state[SAVE_STATE_KEY]

	var deserialized := StoryMapSaveState.new()
	deserialized.nodes = saved_state["nodes"] as PackedVector2Array

	return deserialized
#endregion

func _create_nodes_from_save_state(saved_state: StoryMapSaveState) -> Array[StoryLevelNode]:
	var levels:Array[StoryLevel] = _story_levels_resource.levels
	var nodes:Array[StoryLevelNode]
	nodes.resize(_story_levels_resource.levels.size())

	if nodes.size() != saved_state.nodes.size():
		push_warning("%s: Invalid save state - expected size=%d but node size was %d" % [name, nodes.size(), saved_state.nodes.size()])
		return []

	#region Populate Nodes

	for i in range(levels.size()):
		var level:StoryLevel = levels[i]
		var node:StoryLevelNode = _create_story_level_node(i, level)
		if not node:
			push_warning("%s: Unable to create story node for %d:%s" % [name, i, level.name])
			continue
		nodes[i] = node
		node.position = saved_state.nodes[i]
	return nodes
#endregion

func _on_next_button_pressed() -> void:
	SceneManager.next_level()
	next_button.disabled = true

func _update() -> void:
	_create_graph()
	_update_hud()

func _create_graph() -> void:
	_clear_graph()

	# We display the next story index
	_next_level_index = SceneManager.next_level_index

	_story_levels_resource = SceneManager.story_levels
	if not _story_levels_resource or not _story_levels_resource.levels:
		push_error("%s: No story levels defined. Map will be empty!" % [name])
		return

	var nodes:Array[StoryLevelNode] =_generate_or_load_nodes()
	var story_incomplete:bool = _next_level_index < nodes.size()

	var active_node:StoryLevelNode = nodes[_next_level_index] if story_incomplete else null

	#region Populate Edges
	for i in range(1, nodes.size()):
		var prev_node:StoryLevelNode = nodes[i - 1]
		var next_node:StoryLevelNode = nodes[i]

		if prev_node and next_node:
			var animate:bool = next_node == active_node
			graph_container.add_child(_edge_from_to(prev_node, next_node, animate))
	#endregion

	if story_incomplete:
		var next_level:StoryLevel = _story_levels_resource.levels[_next_level_index]
		_create_scrolling_narrative(next_level, active_node)
		
	var _node_to_center:StoryLevelNode
	if active_node:
		_node_to_center = active_node
	else:
		_node_to_center = nodes.back()
	
	_center_node_offset = Vector2((_node_to_center.global_position.x + _node_to_center.get_combined_minimum_size().x * 0.5) - _get_center_screen().x, 0.0)

func _generate_or_load_nodes() -> Array[StoryLevelNode]:
	var saved_state: StoryMapSaveState = _get_save_state()
	var nodes:Array[StoryLevelNode] = []

	if saved_state:
		nodes = _create_nodes_from_save_state(saved_state)
		# Save state could be invalid so it will return empty in that case
	if not nodes:
		nodes = _generate_nodes()
	return nodes

func _calculate_bounds() -> Rect2:
	var bounds:Rect2 = get_viewport().get_visible_rect()
	bounds.size -= 2 * margins
	bounds.position.x += margins.x
	bounds.position.y += margins.y

	return bounds

func _update_hud() -> void:
	personnel_hud.set_value(PlayerAttributes.personnel)
	scrap_hud.set_value(PlayerAttributes.scrap)
	var player_state: PlayerState = PlayerStateManager.player_state
	if player_state:
		health_hud.set_value(UIUtils.get_health_pct_display(player_state.health, player_state.max_health))
	else:
		print_debug("%s: No player state health found - defaulting to 100.0%%" % name)
		health_hud.set_value(UIUtils.get_health_pct_display(1.0, 1.0))

func _generate_nodes() -> Array[StoryLevelNode]:
	var levels:Array[StoryLevel] = _story_levels_resource.levels

	var bounds:Rect2 = _calculate_bounds()

	var nodes:Array[StoryLevelNode] = []
	nodes.resize(_story_levels_resource.levels.size())

	var prototype_node:StoryLevelNode = _new_story_level_node(default_node_prototype)
	var avg_node_width:float = _get_node_width(prototype_node)
	var ideal_edge_length:float = maxf((bounds.size.x - nodes.size() * avg_node_width) / (nodes.size() - 1), min_edge_length)
	var edge_range:Vector2 = Vector2(min_edge_length, max_edge_length)

	prototype_node.queue_free()

	#region Populate Nodes

	var edge_length_diff:float = 0.0

	var edge_dir_bias:int
	var edge_dir_bias_max_count:int = 0
	var edge_dir_bias_count:int = 0

	# Start in the middle in y
	var pos:Vector2 = Vector2(0.0, (bounds.position.y + bounds.size.y) / 2.0)
	
	for i in range(levels.size()):
		var level:StoryLevel = levels[i]
		var node:StoryLevelNode = _create_story_level_node(i, level)
		if not node:
			push_warning("%s: Unable to create story node for %d:%s" % [name, i, level.name])
			continue

		# Position so that left edge attachment is where we want to add the node
		if i > 0:
			pos.x += node.right_edge.position.x

		print_debug("%s: Add node(%s) at position=%s" % [name, level.name, pos])
		node.position = pos

		# Offset by right edge position for edge attachment
		pos.x += _get_node_width(node)

		var edge_length:float = randf_range(edge_range.x, edge_range.y)
		if edge_length_diff < 0 and -edge_length_diff > ideal_edge_length * (levels.size() - i) / float(levels.size()):
			print_debug("%s: Edges are too long - reducing current edge(%d) length from %f by %f" % [name, i, edge_length, -edge_length_diff])
			edge_length = maxf(ideal_edge_length + edge_length_diff, edge_range.x)

		if edge_dir_bias_count == edge_dir_bias_max_count:
			edge_dir_bias_count = 0
			edge_dir_bias_max_count = randi_range(edge_dir_max_count.x, edge_dir_max_count.y)
			edge_dir_bias = randi_range(-1, 1)

		var edge:Vector2 = get_edge_dir(node, edge_dir_bias) * edge_length

		if(pos.y + edge.y > bounds.position.y + bounds.size.y or
			pos.y + edge.y < bounds.position.y):
			print_debug("%s: Edge(%d) hit y bounds - flipping y direction" % [name, i])
			edge.y = -edge.y
		edge_length_diff += ideal_edge_length - edge.x
		pos += edge

		nodes[i] = node
		edge_dir_bias_count += 1

	#endregion

	return nodes

func get_edge_dir(node: StoryLevelNode, sign_bias:int) -> Vector2:
	var deg_angle_range:Vector2 = Vector2(node.min_edge_angle, node.max_edge_angle)
	if sign_bias == 1:
		deg_angle_range.x = node.max_edge_angle * 0.67
	elif sign_bias == -1:
		deg_angle_range.y = node.min_edge_angle * 0.67

	return Vector2(1.0,0.0).rotated(deg_to_rad(randf_range(deg_angle_range.x, deg_angle_range.y))).normalized()

func _get_node_width(node: StoryLevelNode) -> float:
	return node.right_edge.position.x - node.left_edge.position.x
	#return node.get_minimum_size().x

func _clear_graph() -> void:
	#graph_container.set_global_position(Vector2.ZERO) ## Parallax
	
	for i in range(graph_container.get_child_count() - 1, -1, -1):
		var child:Node = graph_container.get_child(i)
		graph_container.remove_child(child)
		child.queue_free()

	# Delete all but the prototype text node for the tooltipper
	# Skip anything that is not a control as this will be a Timer
	# whose cleanup is automatically handled by the implementation
	# Don't delete the first sequence so stop iteration at index 1
	for _i in range(tooltipper.sequence.size() - 1, 0, -1):
		var child:Control = tooltipper.sequence.pop_back()
		tooltipper.remove_child(child)
		child.queue_free()
		
		
func _create_story_level_node(index:int, metadata:StoryLevel) -> StoryLevelNode:
	# TODO: Maybe knowing about future node is an unlockable or a more complex strategy is adopted
	# If it is unlockable then the story sequence would need to be more procedural
	# which wasn't planned other than individual procedural nature within a given level
	if index < _next_level_index:
		return _new_explored_node(metadata)
	elif index == _next_level_index:
		return _new_discovered_node(metadata)
	return _new_unknown_node(metadata)

func _new_explored_node(metadata: StoryLevel) -> StoryLevelNode:
	return _new_story_level_node_from_metadata(metadata)

func _new_unknown_node(_metadata: StoryLevel) -> StoryLevelNode:
	return _new_story_level_node(unknown_node_prototype)

func _new_discovered_node(metadata: StoryLevel) -> StoryLevelNode:
	var node:StoryLevelNode = _new_story_level_node_from_metadata(metadata)
	node.set_icon_material(incomplete_level_material)

	return node

func _new_story_level_node_from_metadata(metadata: StoryLevel) -> StoryLevelNode:
	var prototype:PackedScene = metadata.ui_map_node
	if not prototype:
		push_warning("%s: Level %s has no UI map node defined! Defaulting to default prototype" % [name, metadata.name])
		prototype = default_node_prototype

	var node:StoryLevelNode = _new_story_level_node(prototype)
	if metadata.ui_map_node_texture:
		node.set_icon_texture(metadata.ui_map_node_texture)
	node.set_label(metadata.name)

	return node

func _new_story_level_node(prototype: PackedScene) -> StoryLevelNode:
	var node:StoryLevelNode = prototype.instantiate() as StoryLevelNode
	graph_container.add_child(node)
	return node

func _edge_from_to(from: StoryLevelNode, to: StoryLevelNode, animate:bool) -> StoryLevelEdge:
	var edge:StoryLevelEdge = edge_node_prototype.instantiate() as StoryLevelEdge

	edge.position = Vector2.ZERO
	edge.from = from.position + from.right_edge.position
	edge.to = to.position + to.left_edge.position

	if not animate:
		edge.num_arrow_animations = 0

	print_debug("%s: Add edge(%s->%s) - [%s, %s]" % [name, from.label.text, to.label.text, edge.from, edge.to])

	#TODO: Change color?
	return edge

#region Narrative

func _create_scrolling_narrative(level:StoryLevel, active_node: StoryLevelNode) -> void:
	# TODO: Start sequence is needed here on the export for the tooltipper - get a nullreference
	# Also relying on too many internal details so this should be later refactored
	# So need to align that with the child nodes
	#tooltipper.sequence

	if not level.narratives:
		push_warning("%s: No narratives defined for level %s" % [name, level.name])
		return
	if not tooltipper.sequence:
		push_warning("%s: Tooltipper=%s has no sequences defined. Cannot extract prototype for level %s"
		% [name, tooltipper.name, level.name])

	var prototype:Control = tooltipper.sequence.back()
	var all_narratives:Array[String] = level.narratives

	# Copy and add the prototype
	for i in range(1, all_narratives.size()):
		var node:Control = prototype.duplicate() as Control
		# Hide by default - same as start_sequence behavior
		node.get_child(0).text = all_narratives[i]
		node.hide()

		tooltipper.sequence.push_back(node)
		tooltipper.add_child(node)

	# Set text on first instance
	prototype.get_child(0).text = all_narratives[0]

	# Position above current node if <= bounds and below current node otherwise
	var active_node_pos:Vector2 = active_node.position
	var narrative_pos:Vector2 = active_node_pos

	var bounds:Rect2 = _calculate_bounds()
	if active_node_pos.y > (bounds.position.y + bounds.size.y) * 0.5:
		narrative_pos.y -= 300
		pass
	else:
		narrative_pos.y += 300
		pass

	if active_node_pos.x > (bounds.position.x + bounds.size.x) * 0.5:
		narrative_pos.x = (bounds.position.x + bounds.size.x) * 0.5
	else:
		narrative_pos.x += 100

	#tooltipper.position = narrative_pos
	tooltipper.restart_sequence()

#region Auto Narrative Round Summary

func _get_prev_round_narrative_summary() -> String:
	# TODO: Determine outcome based on actual results
	# Here we are assuming we won since moving to next level but we aren't measuring the success level yet
	var outcome:AutoNarrative.Outcomes = randi_range(0, 2) as AutoNarrative.Outcomes
	return auto_narrative.generate_narrative(outcome)
#endregion

#endregion
