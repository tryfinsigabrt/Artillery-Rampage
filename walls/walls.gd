class_name Walls extends Node2D

@onready var playableArea = $PlayableArea
@onready var shape = $PlayableArea/CollisionShape2D
@export var warp_offset: float = 10
@export var elastic_min_velocity_threshold:float = 100

enum WallType {
	WARP, 
	ELASTIC,
	ACCELERATE,
	STICKY,
	NONE
}

enum WallInteractionLocation {
	Top,
	Bottom,
	Right,
	Left
}

@export
var wall_mode = WallType.WARP

@export
var speed_multiplier_by_wall_mode : Dictionary[WallType, float] = {
	WallType.WARP: 1.0,
	WallType.ELASTIC: 1.0,
	WallType.ACCELERATE: 1.5,
	WallType.STICKY: 0.5
}

## Override wall mode with specification of available wall types
## and their weight in selection. A weight <= 0 will ignore that type.
@export
var wall_randomization_weights:Dictionary[WallType, float] = {}

var bounds: Rect2;
var min_extent: Vector2
var max_extent: Vector2

var ceiling_y:float:
	get: return bounds.position.y
var is_elastic_variety:bool:
	get:
		return wall_mode == Walls.WallType.ELASTIC or wall_mode == Walls.WallType.STICKY or wall_mode == Walls.WallType.ACCELERATE 

var tracked_projectiles: Array[WeaponProjectile]
var tracked_beams: Array[WeaponNonPhysicalBeam]

func _ready() -> void:
	wall_mode = _select_wall_type()
	
	print_debug("%s: Wall Mode=%s" % [name, wall_mode])
	
	# Opting for continuous checking once fired due to edge cases crossing boundary like the turret going through boundary
	GameEvents.projectile_fired.connect(_on_projectile_fired)
	GameEvents.beam_fired.connect(_on_beam_fired)

	bounds = shape.shape.get_rect()
	bounds = Rect2(shape.to_global(bounds.position), bounds.size)

	min_extent = Vector2(bounds.position.x, bounds.size.y)
	max_extent = Vector2(bounds.position.x + bounds.size.x, bounds.size.y)

func _physics_process(_delta: float) -> void:
	# Workaround for lifetime complete event sometimes not firing and there being a previously freed instance in array
	_erase_all_invalid(tracked_projectiles)
	_erase_all_invalid(tracked_beams)
	
	for projectile in tracked_projectiles:
		check_projectile_wall_interaction(projectile)
	for beam in tracked_beams:
		check_beam_wall_interaction(beam)

func _erase_all_invalid(array) -> void:
	for i in range(array.size() - 1, -1, -1):
		var value = array[i]
		if not is_instance_valid(value):
			push_warning("%s: Erased invalid instance at index %d in array %s" % [name, i, array])
			array.remove_at(i)
		
func _select_wall_type() -> WallType:
	if wall_randomization_weights.is_empty():
		return wall_mode
		
	var weight_sum:float = 0.0
	for wall_type in wall_randomization_weights:
		var weight:float = wall_randomization_weights[wall_type]
		if weight > 0:
			weight_sum += weight
		
	if is_zero_approx(weight_sum):
		push_warning("%s: All wall type randomizations have zero weight!" % name)
		return wall_mode
	
	var walls:Array[WallType] = []
	var thresholds: PackedFloat32Array = []
	
	for wall_type in wall_randomization_weights:
		var weight:float = wall_randomization_weights[wall_type]
		if weight > 0:
			walls.push_back(wall_type)
			thresholds.push_back(weight / weight_sum)
	
	var roll:float = randf()
	
	var sum:float = 0.0
	for i in range(walls.size()):
		sum += thresholds[i]
		if sum <= roll:
			return walls[i]
			
	return walls.back() if not walls.is_empty() else wall_mode
	
func check_projectile_wall_interaction(projectile: WeaponProjectile):
	match wall_mode:
		WallType.WARP:
			projectile_warp(projectile)
		WallType.ELASTIC, WallType.ACCELERATE, WallType.STICKY:
			projectile_elastic(projectile)
		WallType.NONE:
			projectile_none(projectile)

func projectile_elastic(projectile: WeaponProjectile):
	var pos = projectile.global_position
	var movement_dir : Vector2 = projectile.linear_velocity.normalized()
	
	#Left
	if(pos.x <= bounds.position.x):
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Left):
			return
		pos.x = bounds.position.x
		if(movement_dir.x < 0):
			movement_dir.x = -movement_dir.x
			_adjust_interaction_velocity(projectile, movement_dir)
			GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Left)
	#Right
	elif pos.x >= bounds.position.x + bounds.size.x:
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Right):
			return
		pos.x = bounds.position.x + bounds.size.x
		if(movement_dir.x > 0):
			movement_dir.x = -movement_dir.x
			_adjust_interaction_velocity(projectile, movement_dir)
			GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Right)
			
	#Top
	if pos.y <= bounds.position.y:
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Top):
			return
		pos.y = bounds.position.y
		if movement_dir.y < 0:
			movement_dir.y = -movement_dir.y
			_adjust_interaction_velocity(projectile, movement_dir)
			GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Top)
	#Bottom
	elif pos.y >= bounds.position.y + bounds.size.y:
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Bottom):
			return
		pos.y = bounds.position.y + bounds.size.y
		if movement_dir.y > 0:
			movement_dir.y = -movement_dir.y
			_adjust_interaction_velocity(projectile, movement_dir)
			GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Bottom)
			
		# if velocity small on bottom then we should delete
		var speed:float = projectile.linear_velocity.length_squared()
		if speed <= elastic_min_velocity_threshold * elastic_min_velocity_threshold:
			print_debug("Hit bottom %s with small velocity=%s - destroying" % [str(pos), projectile.linear_velocity])
			#Delete projectile
			projectile.explode_and_force_destroy()
		else:
			print_debug("Hit bottom %s with velocity=%s; speed=%f above threshold" % [str(pos), projectile.linear_velocity, sqrt(speed)])
	projectile.global_position = pos

func projectile_warp(projectile: WeaponProjectile):
	var pos: Vector2 = projectile.global_position

#	#left
	if(pos.x <= bounds.position.x):
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Left):
			return
		pos.x = bounds.position.x + bounds.size.x - warp_offset
		print_debug("Warp to right side %s -> %s" % [str(projectile.global_position), str(pos)])
		GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Left)
	#Right
	elif pos.x >= bounds.position.x + bounds.size.x:
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Right):
			return
		pos.x = bounds.position.x + warp_offset
		print_debug("Warp to left side %s -> %s" % [str(projectile.global_position), str(pos)])
		GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Right)
	#Bottom
	if pos.y >= bounds.position.y + bounds.size.y:
		if _check_interaction_force_explode(projectile, WallInteractionLocation.Bottom):
			return
		print_debug("Hit bottom %s - destroying" % [str(pos)])
		GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Bottom)
		#Delete projectile
		projectile.explode_and_force_destroy()
		
	# Top - check just for force explode
	elif pos.y <= bounds.position.y and _check_interaction_force_explode(projectile, WallInteractionLocation.Top):
		return
	
	projectile.global_position = pos

func projectile_none(projectile: WeaponProjectile):
	var pos: Vector2 = projectile.global_position

	#Left
	if(pos.x <= bounds.position.x):
		print_debug("Hit left side %s at %s" % [projectile.name, projectile.global_position])
		GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Left)
		projectile.explode_and_force_destroy()
	#Right
	elif pos.x >= bounds.position.x + bounds.size.x:
		print_debug("Hit right side %s at %s" % [projectile.name, projectile.global_position])
		GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Right)
		projectile.explode_and_force_destroy()
	#Bottom
	elif pos.y >= bounds.position.y + bounds.size.y:
		print_debug("Hit bottom %s at %s" % [projectile.name, projectile.global_position])
		GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Bottom)
		projectile.explode_and_force_destroy()
	# Top - check just for force explode
	elif pos.y <= bounds.position.y and _check_interaction_force_explode(projectile, WallInteractionLocation.Top):
		return
		
func _adjust_interaction_velocity(projectile: WeaponProjectile, new_dir:Vector2) -> void:
	var speed:float = projectile.linear_velocity.length()
	var new_speed:float = speed * speed_multiplier_by_wall_mode.get(wall_mode, 1.0)
	var new_velocity:Vector2 = new_dir * new_speed
	
	projectile.linear_velocity = new_velocity
		 
func _on_projectile_fired(projectile: WeaponProjectile) -> void:
	#print_debug("%s - Tracking projectile fired - %s - %s" % [name, projectile.name, str(projectile.global_position)])
	tracked_projectiles.append(projectile)

	# Need to bind the extra projectile argument to connect
	#projectile.completed_lifespan.connect(_on_projectile_destroyed.bind(projectile))
	projectile.completed_lifespan.connect(_on_projectile_destroyed)

# Bind arguments are passed as an array
func _on_projectile_destroyed(projectile: WeaponProjectile) -> void:
	#print_debug("%s: Projectile Destroyed=%s" % [name, projectile.name])

	tracked_projectiles.erase(projectile)

func _check_interaction_force_explode(projectile: WeaponProjectile, location: WallInteractionLocation) -> bool:
	# If we are in the water when we hit a wall, then always explode
	var force_explode:bool = false
	if projectile.has_meta(Groups.InWaterTag):
		force_explode = true
		print_debug("Hit wall %s while in water: %s" % [EnumUtils.enum_to_string(WallInteractionLocation, location), projectile.name])
		
	if force_explode:
		GameEvents.wall_interaction.emit(self, projectile, location)
		projectile.explode_and_force_destroy()
	return force_explode
	
#region Laser	
func _on_beam_fired(beam: WeaponNonPhysicalBeam) -> void:
	tracked_beams.append(beam)

	# Need to bind the extra projectile argument to connect
	#beam.completed_lifespan.connect(_on_beam_destroyed.bind(beam))
	beam.completed_lifespan.connect(_on_beam_destroyed)

# Bind arguments are passed as an array
func _on_beam_destroyed(beam: WeaponNonPhysicalBeam) -> void:
	tracked_beams.erase(beam)

func check_beam_wall_interaction(beam: WeaponNonPhysicalBeam):
	match wall_mode:
		WallType.WARP:
			beam_warp(beam)
		WallType.ELASTIC, WallType.ACCELERATE, WallType.STICKY:
			beam_elastic(beam)
		WallType.NONE:
			beam_none(beam)

func beam_elastic(beam: WeaponNonPhysicalBeam):
	var pos: Vector2 = beam.get_current_laser_end().global_position
	var current_aim_angle = beam.get_current_aim_angle()
	var movement_dir = Vector2(1, 0).rotated(current_aim_angle)
	
	if(pos.x <= bounds.position.x):
		if(movement_dir.x < 0):
			movement_dir.x = -movement_dir.x
			var new_aim_angle = movement_dir.angle()
			beam.create_new_segment(pos, new_aim_angle)
			movement_dir.x = -movement_dir.x
			# TODO: implement beam announcer events
			#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Left)
	elif pos.x >= bounds.position.x + bounds.size.x:
		if(movement_dir.x > 0):
			movement_dir.x = -movement_dir.x
			var new_aim_angle = movement_dir.angle()
			beam.create_new_segment(pos, new_aim_angle)
			# TODO: implement beam announcer events
			#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Right)
			
	#Top
	if pos.y <= bounds.position.y:
		if movement_dir.y < 0:
			movement_dir.y = -movement_dir.y
			var new_aim_angle = movement_dir.angle()
			beam.create_new_segment(pos, new_aim_angle)
			# TODO: implement beam announcer events
			#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Top)
	#Bottom
	elif pos.y >= bounds.position.y + bounds.size.y:
		if movement_dir.y > 0:
			movement_dir.y = -movement_dir.y
			var new_aim_angle = movement_dir.angle()
			beam.create_new_segment(pos, new_aim_angle)
			# TODO: implement beam announcer events
			#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Bottom)

func beam_warp(beam: WeaponNonPhysicalBeam):
	var pos: Vector2 = beam.get_current_laser_end().global_position

	if(pos.x <= bounds.position.x):
		var spawn_pos = Vector2(bounds.position.x + bounds.size.x - warp_offset, pos.y)
		beam.create_new_segment(spawn_pos, beam.get_current_aim_angle())
		# TODO: implement beam announcer events
		#print_debug("Warp to right side %s -> %s" % [str(projectile.global_position), str(pos)])
		#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Left)
	elif pos.x >= bounds.position.x + bounds.size.x:
		var spawn_pos = Vector2(bounds.position.x + warp_offset, pos.y)
		beam.create_new_segment(spawn_pos, beam.get_current_aim_angle())
		# TODO: implement beam announcer events
		#print_debug("Warp to left side %s -> %s" % [str(projectile.global_position), str(pos)])
		#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Right)

func beam_none(beam: WeaponNonPhysicalBeam):
	var pos: Vector2 = beam.get_current_laser_end().global_position
	print_debug("beam position? %f %f" % [pos.x, pos.y])

	if (pos.x <= bounds.position.x):
		print_debug("Hit left side %s at %s" % [beam.name, beam.global_position])
		# TODO: implement beam announcer events
		#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Left)
		beam.explode_and_force_destroy()
	elif pos.x >= bounds.position.x + bounds.size.x:
		print_debug("Hit right side %s at %s" % [beam.name, beam.global_position])
		# TODO: implement beam announcer events
		#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Right)
		beam.explode_and_force_destroy()
	elif pos.y >= bounds.position.y + bounds.size.y:
		print_debug("Hit bottom %s at %s" % [beam.name, beam.global_position])
		# TODO: implement beam announcer events
		#GameEvents.wall_interaction.emit(self, projectile, WallInteractionLocation.Bottom)
		beam.explode_and_force_destroy()
		
#endregion
