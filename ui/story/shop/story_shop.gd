extends Control

@export var item_resources:ShopItemsResource
@export var min_remaining_scrap:int = 0
@export var min_remaining_personnel:int = 1

@onready var items_container:Container = %ItemsContainer
@onready var resources_control:ShopResourceRowControl = %ResourceRow
@onready var buttons_container:Container = %ButtonsContainer

@onready var total_scrap_spending: HUDElement = %TotalScrapSpending

# Shop item row scenes by ItemType (Currently only weapon)
@export var weapon_row_scene:PackedScene = preload("res://ui/story/shop/shop_row_weapon.tscn")

@onready var reset_button: Button = %Reset

## SFX
@onready var sfx_buy_ammo: AudioStreamPlayer = %SFX_BuyAmmo
@onready var sfx_buy_weapon: AudioStreamPlayer = %SFX_BuyWeapon
@onready var sfx_undo_buy_weapon: AudioStreamPlayer = %SFX_UndoBuyWeapon
@onready var sfx_reset: AudioStreamPlayer = %SFX_Reset
@onready var sfx_done: AudioStreamPlayer = %SFX_Done


class ItemPurchaseState:
	var item:ShopItemResource
	var existing_item: Node:
		get: return existing_item
		set(value):
			existing_item = value
			_on_item_set(existing_item)

	var already_in_inventory:bool
	var new_item:Node:
		get: return new_item
		set(value):
			new_item = value
			_on_item_set(new_item)

	var ui_control:Control
	var buy:bool
	var refill_amount:int
	var refill_cost:int

	var inventory_item:Node:
		get: return existing_item if existing_item else new_item

	func reset() -> void:
		buy = false
		refill_cost = 0
		refill_amount = 0
		ui_control.reset()

	func _on_item_set(backing_item:Node) -> void:
		if not backing_item:
			return
		var weapon:Weapon = backing_item as Weapon
		if not weapon:
			return

		# Apply a discount if weapon is retained when empty so that this has some kind of advantage in the game
		# We make a duplicate of the resource so okay to modify it. Ordinarily resources are global resources
		# We do not need to re-purchase previously unlocked weapons
		item.apply_refill_discount = weapon.retain_when_empty
		item.uses_magazines = weapon.use_magazines
		item.ammo_purchase_increment = weapon.magazine_capacity if weapon.use_magazines else 1
		
		print_debug("%s: _on_item_set(%s) - apply_refill_discount=%s; uses_magazines=%s; ammo_purchase_increment=%d" \
			 % [item.item_scene.resource_path, weapon.display_name, str(item.apply_refill_discount), str(item.uses_magazines), item.ammo_purchase_increment])

## Keyed by the scene file path of the instantiated item
var _purchase_item_state_dictionary:Dictionary[String, ItemPurchaseState] = {}

var pending_scrap_spend:int = 0
var pending_personnel_spend:int = 0

func _ready() -> void:
	reset_button.call_deferred("grab_focus") ## Gamepad support
	
	var player_state:PlayerState =_initialize_player_state()

	var existing_weapons:Dictionary[String, Weapon] = {}
	for weapon in player_state.weapons:
		existing_weapons[weapon.scene_file_path] = weapon

	_update_resources_control_state()

	# Cannot do a deep copy of array to duplicate the resources as this type is not duplicated in a deep copy
	# We need to duplicate as will be modifying the resource and map returns an Array not a generic array i.e. Array[ShopItemResource]
	# We don't need to duplicate subresources as there are none - only potential future arrays and dictionaries which now require deep copying
	# Skip any resources explicitly marked as disabled
	
	var sorted_items: Array = item_resources.items.filter(func(r): return not r.disable).map(func(r): return r.duplicate_deep(Resource.DEEP_DUPLICATE_NONE))
	sorted_items.sort_custom((func(a,b)->bool: return a.unlock_cost < b.unlock_cost))

	for item:ShopItemResource in sorted_items:
		# Display a row if we have the item already or can afford to buy it
		if not item.item_scene:
			continue

		# Here we could choose which UI scene to instantitate by item type
		var item_scene_path:String = item.item_scene.resource_path
		var existing_weapon:Weapon = existing_weapons.get(item_scene_path)
		var in_inventory:bool = is_instance_valid(existing_weapon)
		if not in_inventory:
			existing_weapon = player_state.get_empty_weapon_if_unlocked(item_scene_path)

		if existing_weapon or (not existing_weapon and can_afford_to_buy_item(item)):
			var weapon_row = weapon_row_scene.instantiate()

			var purchase_state:ItemPurchaseState = ItemPurchaseState.new()
			purchase_state.item = item
			purchase_state.existing_item = existing_weapon
			purchase_state.already_in_inventory = in_inventory
			purchase_state.ui_control = weapon_row
			_purchase_item_state_dictionary[item_scene_path] = purchase_state

			weapon_row.shop_item = item
			weapon_row.weapon = existing_weapon
			items_container.add_child(weapon_row)

			weapon_row.on_buy_state_changed.connect(_on_weapon_buy_state_changed)
			weapon_row.on_ammo_state_changed.connect(_on_weapon_ammo_state_changed)

	_update_row_states()

func _initialize_player_state() -> PlayerState:
	var player_state:PlayerState = PlayerStateManager.player_state
	if not player_state:
		push_warning("PlayerStateManager.player_state is null, no existing weapon info")
		return PlayerState.new()

	# PlayerState here is already a copy from the serialized state and the shop is shown after the round
	# Upgrades are not applied by default to weapons in player state that was deserialized
	# During gameplay that is ordinary done in the Player ready function
	# We need the upgrades applied here as they affect the shop related to ammo - e.g. not requiring ammo and so shouldn't be able to purchase it
	# If this changes later could use PlayerState.duplicate() to make a copy
	PlayerUpgrades.apply_all_upgrades(player_state.weapons)

	return player_state

func can_afford_to_buy_item(item: ShopItemResource) -> bool:
	if item.unlock_cost_type == ShopItemResource.CostType.Scrap:
		return PlayerAttributes.scrap - item.unlock_cost - pending_scrap_spend - min_remaining_scrap >= 0
	return PlayerAttributes.personnel - item.unlock_cost - pending_personnel_spend - min_remaining_personnel >= 0


func can_afford_to_refill_any(item: ShopItemResource) -> bool:
	var avail_spend:int
	if item.refill_cost_type == ShopItemResource.CostType.Scrap:
		avail_spend = PlayerAttributes.scrap - pending_scrap_spend - min_remaining_scrap
	else:
		avail_spend = PlayerAttributes.personnel - pending_personnel_spend - min_remaining_personnel

	# In case the refill cost is 0 don't check the avail spend first
	return avail_spend - item.get_refill_cost(1) >= 0

func _on_done_pressed() -> void:
	sfx_done.play()
	
	_apply_changes()

	if not SceneManager.deque_transition():
		SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryMap)
	
	UIUtils.disable_all_buttons(buttons_container)

func _apply_changes() -> void:
	# Update the player state with the new weapon states
	var player_state:PlayerState = PlayerStateManager.player_state
	assert(player_state, "PlayerStateManager.player_state is null, cannot apply changes")

	for purchase_state_key in _purchase_item_state_dictionary:
		var purchase_state:ItemPurchaseState = _purchase_item_state_dictionary[purchase_state_key]
		match purchase_state.item.item_type:
			ShopItemResource.ItemType.Weapon:
				_apply_weapon(player_state, purchase_state)
			_:
				push_warning("%s: Unsupported item type %s found for purchase_state item=%s" % [name, str(purchase_state.item.item_type), purchase_state.item.resource_path])

	# Apply resource costs
	PlayerAttributes.scrap = PlayerAttributes.scrap - pending_scrap_spend
	PlayerAttributes.personnel = PlayerAttributes.personnel - pending_personnel_spend

func _apply_weapon(player_state: PlayerState, purchase_state: ItemPurchaseState)  -> void:
	var store_existing_weapon:Weapon = purchase_state.existing_item as Weapon
	if store_existing_weapon:
		# Object reference may have been swapped out in PlayerState due to how save system works
		# So make sure affect the actual array instance
		_apply_ammo_and_magazines(purchase_state, store_existing_weapon)
		if purchase_state.refill_amount > 0:
			if purchase_state.already_in_inventory:
				# Set back on original weapon
				var existing_weapon_index:int = player_state.weapons.find_custom(func(w)->bool: return w.scene_file_path == store_existing_weapon.scene_file_path)
				if existing_weapon_index != -1:
					_copy_weapon_ammo_and_magazines_from_to(store_existing_weapon, player_state.weapons[existing_weapon_index])
				else:
					push_error("%s: Store weapon copy for %s could not be found in player state weapons!" % [name, store_existing_weapon.display_name])
					# Best we can do at this point is refund the cost
					_update_state_refill_cost(purchase_state, 0, 0)
			else: # If this was a previous unlock but not in inventory then treat similar to new item
				player_state.weapons.push_back(store_existing_weapon.duplicate())
	elif purchase_state.buy:
		assert(purchase_state.new_item)

		# Need to duplicate as the reference above is owned by the UI element and will be freed when this node exits
		# We could both be buying and adding ammo
		var new_weapon:Weapon = purchase_state.new_item.duplicate()
		print_debug("%s: Purchased new weapon - %s" % [name, purchase_state.new_item.display_name])

		_apply_ammo_and_magazines(purchase_state, new_weapon)
		player_state.weapons.push_back(new_weapon)

func _apply_ammo_and_magazines(purchase_state:ItemPurchaseState, weapon:Weapon) -> void:
	if weapon.use_magazines:
		var magazine_purchases:int = floori(float(purchase_state.refill_amount) / weapon.magazine_capacity)
		weapon.magazines += magazine_purchases
		print_debug("%s: Purchased %d magazines for weapon %s" % [name, magazine_purchases, weapon.display_name])
	else:
		weapon.current_ammo += purchase_state.refill_amount
		print_debug("%s: Purchased %d ammo for weapon %s" % [name, purchase_state.refill_amount, weapon.display_name])

func _copy_weapon_ammo_and_magazines_from_to(from:Weapon, to:Weapon) -> void:
	if to.use_magazines:
		to.magazines = from.magazines
	else:
		to.current_ammo = from.current_ammo

func _on_weapon_buy_state_changed(weapon: Weapon, buy:bool) -> void:
	print_debug("%s - Buy State changed for %s - buy=%s" % [name, weapon.display_name, str(buy)])
	
	if buy:
		sfx_buy_weapon.play()
	else:
		sfx_undo_buy_weapon.play()

	var state: ItemPurchaseState = _purchase_item_state_dictionary[weapon.scene_file_path]
	state.buy = buy
	state.new_item = weapon

	var delta:int = state.item.unlock_cost if buy else -state.item.unlock_cost
	if state.item.unlock_cost_type == ShopItemResource.CostType.Scrap:
		pending_scrap_spend = maxi(0, pending_scrap_spend + delta)
	else:
		pending_personnel_spend = maxi(0, pending_personnel_spend + delta)

	_update_resources_control_state()
	_update_row_states()

func _update_resources_control_state() -> void:
	resources_control.update_values(
		PlayerAttributes.scrap - pending_scrap_spend,
		PlayerAttributes.personnel - pending_personnel_spend
	)
	
	total_scrap_spending.set_value(pending_scrap_spend)
	if pending_scrap_spend > 0:
		total_scrap_spending.show()
	else:
		total_scrap_spending.hide()

func _on_weapon_ammo_state_changed(weapon: Weapon, new_ammo:int, old_ammo:int, cost:int) -> void:
	print_debug("%s - Weapon Ammo State changed for %s - new_ammo=%d; old_ammo=%d; cost=%d" % [name, weapon.display_name, new_ammo, old_ammo, cost])
	sfx_buy_ammo.play()

	var state: ItemPurchaseState = _purchase_item_state_dictionary[weapon.scene_file_path]
	_update_state_refill_cost(state, new_ammo, cost)

	_update_resources_control_state()
	_update_row_states()

func _update_state_refill_cost(state: ItemPurchaseState, refill_amount: int, cost:int) -> void:
	state.refill_amount = refill_amount

	var cost_delta:int = cost - state.refill_cost
	if state.item.refill_cost_type == ShopItemResource.CostType.Scrap:
		pending_scrap_spend += cost_delta
	else:
		pending_personnel_spend += cost_delta

	state.refill_cost = cost

func _update_row_states() -> void:
	for purchase_state_key in _purchase_item_state_dictionary:
		var purchase_state:ItemPurchaseState = _purchase_item_state_dictionary[purchase_state_key]
		var item: ShopItemResource = purchase_state.item
		

		# If not yet buying make sure still have enough
		if not purchase_state.buy and not purchase_state.existing_item:
			purchase_state.ui_control.buy_enabled = can_afford_to_buy_item(item)
			# Cannot refill before buy
			purchase_state.ui_control.refill_enabled = false
		else:
			purchase_state.ui_control.refill_enabled = true
			purchase_state.ui_control.refill_purchase_enabled = can_afford_to_refill_any(item)

func _on_reset_pressed() -> void:
	pending_personnel_spend = 0
	pending_scrap_spend = 0

	_update_resources_control_state()

	# Reset the purchase state and then reset the enabled status
	for purchase_state in _purchase_item_state_dictionary.values():
		purchase_state.reset()

	_update_row_states()
	
	sfx_reset.play()
