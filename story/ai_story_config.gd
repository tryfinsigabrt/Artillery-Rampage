class_name AIStoryConfig extends Resource

## Weapon scenes available to spawn
@export var weapons:Array[PackedScene]

## Range of weapons to spawn
@export var weapon_count: Vector2i = Vector2i(1,1)

## Overrides the configured AI types to spawn
@export var artillery_ai_types: Array[PackedScene]
