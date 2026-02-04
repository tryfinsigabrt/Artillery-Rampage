extends HFlowContainer

@export var scene:PackedScene ## Must Be PanelContainer!

func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	PlayerUpgrades.upgrades_changed.connect(_on_upgrades_changed)
	
func _on_focus_entered() -> void:
	for child in get_children():
		if child is ModDisplayPanel:
			child.grab_focus.call_deferred() ## Gamepad support
			break
	
func create_mod_display_panel(mod) -> ModDisplayPanel:
	if not scene:
		push_error("ModDisplayPanel scene not configured in export property.")
		return
	var display:ModDisplayPanel = scene.instantiate()
	display.mods.append(mod)
	return display


func update() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	
	var upgrades: Array[ModBundle] = PlayerUpgrades.get_current_upgrades()
	upgrades.sort_custom(ModUtils.sort_by_target_weapon) ## Ascending. Bind `false` for descending order.
	
	#var bundle_strings: PackedStringArray = []
	#for mod in upgrades:
		#bundle_strings.push_back(mod.to_string())
	#text = "\n".join(bundle_strings)
	var last_display: ModDisplayPanel
	for mod in upgrades:
		var display:ModDisplayPanel = create_mod_display_panel(mod)
		add_child(display)
		display.configure_from_mods()
		Juice.fade_in(display)
		
		if last_display:
			last_display.focus_next = get_path_to(display)
			display.focus_previous = get_path_to(last_display)
		
		last_display = display
	
func _on_upgrades_changed() -> void:
	update()
