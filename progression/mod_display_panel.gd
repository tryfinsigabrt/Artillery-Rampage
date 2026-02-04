class_name ModDisplayPanel extends Control

const DespawnTimeWhenScrapped:float = Juice.PATIENT

var mods:Array[ModBundle]:
	set(value):
		mods = value
		configure_from_mods()

var confirming:bool = false

@export var buff_color:Color = Color.WHITE
@export var debuff_color:Color = Color.INDIAN_RED

@onready var everything: VBoxContainer = %Everything

@onready var header_label: Label = %HeaderLabel
@onready var header_sublabel: Label = %HeaderSublabel

@onready var display_property: Label = %Property
@onready var display_operation: Label = %Operation
@onready var display_value: Label = %Value
@onready var buff_debuff_bg_fill: Sprite2D = %BuffDebuffBGFill

@onready var hide_timer: Timer = %HideTimer
@onready var buttons: VBoxContainer = %Buttons
@onready var delete: Button = %Delete
@onready var cancel: Button = %Cancel
@onready var confirm: Button = %Confirm
@onready var confirm_label: Label = %ConfirmLabel

@onready var scrapped_valuation: VBoxContainer = %ScrappedValuation
@onready var scrapped_value: Label = %ScrappedValue


func _enter_tree() -> void:
	focus_entered.connect(_on_focus_entered) ## Gamepad support
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _exit_tree() -> void:
	mouse_entered.disconnect(_on_mouse_entered)
	mouse_exited.disconnect(_on_mouse_exited)
	
func _ready() -> void:
	buttons.hide()
	delete.show()
	cancel.hide()
	confirm.hide()
	confirm_label.hide()
	scrapped_valuation.hide()
	everything.show()
	
	if not mods.is_empty():
		configure_from_mods()
	else:
		push_warning("ModDisplayPanel: Mods not configured before ready. Be sure to call the method manually.")
	
func configure_from_mods() -> void:
	var _mods:Array
	for mod in mods:
		_mods.append_array(mod.components_weapon_mods)
		_mods.append_array(mod.components_projectile_mods)
			
	## NOTE
	## This logic will only show the ___first___ mod in the ModBundle array's data (see the return at the end).
	## Not sure how to sort this yet but I think in -all- cases right now, it will only be one mod per bundle.
	## This will definitely change once layers are used in the bundle.
	## It will probably be worth doing aggregation in the upgrade list script instead of the display panel.
	for mod in _mods:
		if mod is ModWeapon:
			header_label.text = mod.target_weapon_name
			#header_sublabel.text =
			display_property.text = mod.property_to_display_string()
			display_operation.text = mod.operation_to_display_string()
			display_value.text = mod.get_property_value_to_string()
			
			buff_debuff_bg_fill.modulate = buff_color if mod.is_buff else debuff_color
			
		if mod is ModProjectile:
			# Find the appropriate weapon and display it
			pass
		return
	
func exchange_mod_for_scrap() -> void:
	# Get scrap value & remove upgrade from player
	var scrap_value:int = 0
	for mod in mods:
		if mod is ModBundle:
			scrap_value += PlayerUpgrades.remove_upgrade_and_get_scrap_value(mod)
			
	# Give that scrap to the player
	PlayerAttributes.scrap += scrap_value
	print_debug("Player exchanged mods for %s scrap." % [scrap_value])
	
	# UI Response
	Juice.fade_out(everything, Juice.SNAP)
	var exit_tween:Tween = Juice.fade_in(scrapped_valuation, Juice.SNAP)
	exit_tween.tween_interval(DespawnTimeWhenScrapped)
	exit_tween.tween_property(self, ^"modulate", Color.TRANSPARENT, Juice.SNAPPY)
	exit_tween.tween_callback(queue_free)
	
	scrapped_valuation.show()
	scrapped_value.text = "%s  %s" % ["+" if scrap_value > 0 else "-", scrap_value]
	
func toggle_buttons(to_confirm:bool = true) -> void:
	if to_confirm:
		confirming = true
		delete.hide()
		# Are you sure?
		confirm_label.show()
		cancel.show()
		confirm.show()
		confirm.grab_focus()
	else:
		confirming = false
		delete.show()
		delete.grab_focus()
		# Are you sure?
		confirm_label.hide()
		cancel.hide()
		confirm.hide()
		
func _on_focus_entered() -> void:
	_on_mouse_entered()
	delete.grab_focus.call_deferred()

func _on_mouse_entered() -> void:
	hide_timer.stop()
	buttons.show()
	
func _on_mouse_exited() -> void:
	hide_timer.start()

func _on_delete_pressed() -> void:
	toggle_buttons(true)

func _on_cancel_pressed() -> void:
	toggle_buttons(false)

func _on_confirm_pressed() -> void:
	toggle_buttons(false)
	delete.disabled = true
	
	exchange_mod_for_scrap() # Expecting to queue free


func _on_hide_timer_timeout() -> void:
	toggle_buttons(false)
	buttons.hide()
