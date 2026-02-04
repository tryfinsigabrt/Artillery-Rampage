class_name StoryRoundSummary extends Control

@export var rewards_config: StoryRewardsConfig

@export var win_background:Texture
@export var lose_background:Texture

@onready var background:TextureRect = %Background
@onready var title:HUDElement = %Title
@onready var turns:HUDElement = %Turns
@onready var kills:HUDElement = %Kills
@onready var damage_done:HUDElement = %DamageDone
@onready var health_lost:HUDElement = %HealthLost
@onready var grade_hudelement:HUDElement = %Grade
@onready var personnel:HUDElement = %Personnel
@onready var scrap:HUDElement = %Scrap

@onready var tooltipper:TextSequence = %StoryTooltips
@onready var auto_narrative:AutoNarrative = %AutoNarrative

@onready var win_audio: AudioStreamPlayer = %RoundWinAudio
@onready var lose_audio: AudioStreamPlayer = %RoundLoseAudio
@onready var next_button:Button = %Next

var _grade:int = 0
var _is_game_over:bool = false

static var letter_to_grade:Dictionary[String, int]
static var grade_to_letter:Dictionary[int, String]

static func _static_init():
	var grades: Array[String] = [
		"A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"
	]
	# Lowest grade is a Zero
	grades.reverse()
	
	for i in grades.size():
		letter_to_grade[grades[i]] = i
		grade_to_letter[i] = grades[i]

func _ready() -> void:
	print_debug("StoryRoundSummary: _ready")
	
	next_button.call_deferred("grab_focus") ## Gamepad support
	
	var stats : RoundStatTracker.RoundData = RoundStatTracker.round_data
	if not stats:
		push_error("No RoundStatTracker.RoundData was recorded!")
		title.set_value("ERROR!")
		return
	if not rewards_config:
		push_error("No StoryRewardsConfig is assigned!")
		title.set_value("ERROR!")
		return
		
	title.set_label("%s:" % [stats.level_name])
	
	if stats.won:
		title.set_value("Victory!")
		background.texture = win_background
		
	else:
		title.set_value("Defeat :(")
		background.texture = lose_background
		
	_grade = _calculate_grade(RoundStatTracker.round_data)
	# Hiding grade if you lose
	if stats.won:
		grade_hudelement.set_value(_fmt_grade(_grade))
	else:
		grade_hudelement.hide()
		
	_set_narrative(_grade)
	
	turns.set_value(stats.turns)
	kills.set_value(stats.kills)
	damage_done.set_value("%.1f" % stats.damage_done)
	# Show health lost bot has absolute value and percentage of max
	var health_lost_amount:float = stats.start_health - stats.final_health
	health_lost.set_value(UIUtils.get_health_pct_display(health_lost_amount, stats.max_health))
	
	_play_audio()
	
	_update_attributes.call_deferred(rewards_config, stats)

func _update_attributes(config: StoryRewardsConfig, stats: RoundStatTracker.RoundData) -> void:
	if not config:
		push_error("No StoryRewardsConfig assigned!")
		return
	
	if not stats:
		push_error("No RoundStatTracker.RoundData!")
		return
	else:
		var personnel_change:int = config.calculate_personnel_change(_get_letter_grade(_grade))
		if stats.additional_personnel_rewarded > 0:
			print_debug("%s: Awarding additional %d personnel from level-specific rewards" % [name, stats.additional_personnel_rewarded])
			# Add any additional personnel rewarded
			personnel_change += stats.additional_personnel_rewarded

		# Player gets scrap even when lose based on collected data
		var scrap_change:float = _calculate_scrap_earned(config, stats)
		
		if stats.won:
			# If win get a bonus multiplier for scrap_change based on grade
			var bonus_scrap_multiplier:float = config.calculate_scrap_bonus_multiplier(_get_letter_grade(_grade))
			print_debug("%s: Bonus scrap multiplier of %.2fx on win starting from %d scrap" % [name, bonus_scrap_multiplier, scrap_change])
			scrap_change = ceilf(scrap_change * bonus_scrap_multiplier)
	
		var run_count:int = 1
		if SceneManager.story_level_state:
			run_count = SceneManager.story_level_state.run_count
		else:
			push_warning("No scene level state: Defaulting run count for bonus calculations to 1")

		var run_bonus_multiplier:float = config.calculate_run_bonus_multiplier(run_count)
		print_debug("%s: Run bonus multiplier of %.2fx" % [name, run_bonus_multiplier])
		personnel_change = ceili(personnel_change * run_bonus_multiplier)
		scrap_change = ceilf(scrap_change * run_bonus_multiplier)
		
		@warning_ignore_start("narrowing_conversion")
		PlayerAttributes.personnel = maxi(PlayerAttributes.personnel + personnel_change, 0)
		PlayerAttributes.scrap = maxi(PlayerAttributes.scrap + scrap_change, 0)

		personnel.set_value(_fmt_attr(PlayerAttributes.personnel, personnel_change))
		scrap.set_value(_fmt_attr(PlayerAttributes.scrap, scrap_change))
		@warning_ignore_restore("narrowing_conversion")

	# TODO: Maybe do this from StatTracker as player could game the system and quit here and it wouldn't save
	# Here we are explicitly forcing a save
	SaveStateManager.save_tree_state(&"StoryLevelFinished")

	_is_game_over = PlayerAttributes.personnel <= 0

func _calculate_scrap_earned(config: StoryRewardsConfig, stats: RoundStatTracker.RoundData) -> float:
	# Earn scrap for a full kill (player killed opponent and caused all the damage except for tank self damage)
	# Earn scrap for a partial kill (player killed opponent but some other opponent caused some damage)
	# Earn scrap for any damage to opponent
	
	
	var earned_scrap:float = config.scrap_baseline_stipend
	for key in stats.enemies_damaged:
		var enemy_data:RoundStatTracker.EnemyData = stats.enemies_damaged[key]
		
		if enemy_data.is_full_kill():
			earned_scrap += config.scrap_per_full_kill
			print_debug("%s: Awarding %d scrap for full kill against %s" % [name, config.scrap_per_full_kill, enemy_data.name])
			
		elif enemy_data.is_partial_kill():
			earned_scrap += config.scrap_per_partial_kill
			print_debug("%s: Awarding %d scrap for partial kill against %s" % [name, config.scrap_per_partial_kill, enemy_data.name])
			
		elif enemy_data.is_damaged():
			earned_scrap += config.scrap_per_enemy_damaged
			print_debug("%s: Awarding %d scrap for some damage against %s" % [name, config.scrap_per_enemy_damaged, enemy_data.name])
	
	if stats.additional_scrap_rewarded > 0:
		print_debug("%s: Awarding additional %d scrap from level-specific rewards" % [name, stats.additional_scrap_rewarded])
		earned_scrap += stats.additional_scrap_rewarded

	return earned_scrap

func _on_next_pressed() -> void:
	var stats : RoundStatTracker.RoundData = RoundStatTracker.round_data

	if stats and stats.won:
		_next_after_win()
	elif not _is_game_over:
		_next_after_loss()
	else:
		SceneManager.switch_scene_keyed(SceneManager.SceneKeys.GameOver)
		
	next_button.disabled = true

func _next_after_loss() -> void:
	# If player state is defined make sure we restart with full health as already took the personnel hit
	var player_state:PlayerState = PlayerStateManager.player_state
	if player_state:
		player_state.health = player_state.max_health
	else:
		push_warning("%s: No player state was defined when restarting level - unable to reset player health" % name)

	# TODO: May want to only go to shop if have resources to spend
	# Can handle this by queueing the transition and then dequeue_transition which will work for both cases
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.StoryShop)

	# Queue next transition after this
	SceneManager.queue_transition("restart_level")

func _next_after_win() -> void:
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.UpgradeSelect)

	# Queue next transitions after this
	SceneManager.queue_transition("switch_scene_keyed", [SceneManager.SceneKeys.StoryShop])

	# Check if on last level of run and trigger the run end screen instead in that case
	if SceneManager.is_on_last_story_level():
		SceneManager.queue_transition("switch_scene_keyed", [SceneManager.SceneKeys.StoryComplete])
	else:
		SceneManager.queue_transition("switch_scene_keyed", [SceneManager.SceneKeys.StoryMap])

func _play_audio() -> void:
	if RoundStatTracker.round_data.won:
		if win_audio:
			win_audio.play()
	else:
		if lose_audio:
			lose_audio.play()
		
#region Auto Narrative

func _set_narrative(grade: int) -> void:
	var text_control:Control = tooltipper.sequence.back()
	
	var outcome := _calculate_outcome(grade)
	var narrative:String = auto_narrative.generate_narrative(outcome)
	text_control.get_child(0).text = narrative

func _calculate_outcome(grade: int) -> AutoNarrative.Outcomes:
	match _fmt_grade(grade):
		"A+", "A", "A-" : return AutoNarrative.Outcomes.MIRACLE
		"B+", "B", "B-": return AutoNarrative.Outcomes.SUCCESS
		"C+", "C", "C-" : return AutoNarrative.Outcomes.NEUTRAL
		"D+", "D", "D-" : return AutoNarrative.Outcomes.FAILURE
	return AutoNarrative.Outcomes.CATASTROPHE
	
#endregion

#region Letter Grades
		
func _fmt_grade(grade: int) -> String:
	return _get_letter_grade(grade)

func _get_letter_grade(grade: int) -> String:
	return grade_to_letter.get(grade, "A+")

func _fmt_attr(value: int, delta:int) -> String:
	if delta > 0:
		return "%d (+%d)" % [value, delta]
	elif delta < 0:
		return "%d (%d)" % [value, delta]
	else:
		return "%d (+0)" % value
		
func _calculate_grade(stats: RoundStatTracker.RoundData) -> int:
	# If won look at damage ratio and take into account kills
	# TODO: For miracle, track damage done and kills at low health - probably need to bracket into percentiles (not dictionary with float)
	# That tracks damage_done and kills at each health level

	# Damage to health lost ratio
	var damage_to_health:float = stats.damage_done / maxf(stats.start_health - stats.final_health, 1.0)
	var kills_to_turns: float = stats.kills / maxf(stats.turns, 1.0)
	var full_kills:int = 0
	for key in stats.enemies_damaged:
		var data:RoundStatTracker.EnemyData = stats.enemies_damaged[key]
		if data.is_full_kill():
			full_kills += 1

	var damaged_frac:float = float(stats.enemies_damaged.size()) / stats.total_enemies
	var kills_frac: float = float(stats.kills) / stats.total_enemies
	var full_kills_frac: float = float(full_kills) / stats.total_enemies

	var grade:int = 0

	# impact to overall battlefield normalized [0-1]
	var battlefield_impact_grade_delta: Callable = func() -> int:
		if stats.total_enemies >= 3:
			var impact: float = (full_kills_frac + pow(kills_frac, 1.5) + pow(damaged_frac, 0.5)) / 3.0
			if impact >= 0.9:
				return 3
			elif impact >= 0.75:
				return 2
			elif impact >= 0.5:
				return 1
			elif impact >= 0.333:
				return 0
			elif impact >= 0.25:
				return -1
			elif impact >= 0.15:
				return -2
			else:
				return -3
		return 0

	# Lowest win is C-	
	if stats.won:
		# Miracles are actually decisive victories not crazy come from behind victories

		#Damage Dealt to Received
		if is_zero_approx(stats.health_lost):
			if full_kills >= 3:
				grade = letter_to_grade["A+"]
			if full_kills >= 2:
				grade = letter_to_grade["A"]
			elif full_kills >= 1:
				grade = letter_to_grade["A-"]
			else:
				grade = letter_to_grade["B+"]
		elif damage_to_health >= 10.0 and full_kills >= 2:
			grade = letter_to_grade["A"]
		elif damage_to_health >= 5.0 and full_kills >= 1:
			grade = letter_to_grade["A-"]
		elif damage_to_health >= 2.0:
			grade = letter_to_grade["B+"]
		elif damage_to_health > 1:
			grade = letter_to_grade["B"]
		elif damage_to_health >= 0.75:
			grade = letter_to_grade["B-"]
		elif damage_to_health > 0.5:
			grade = letter_to_grade["C+"]
		else:
			grade = letter_to_grade["C"]

		# Speed Score
		if kills_to_turns >= 2:
			grade += 3
		elif kills_to_turns > 1.0:
			grade += 2
		elif is_equal_approx(kills_to_turns, 1.0):
			grade += 1
		elif kills_to_turns >= 0.5:
			pass
		elif kills_to_turns >= 0.33:
			grade -= 1
		elif kills_to_turns >= 0.25:
			grade -= 2
		elif kills_to_turns >= 0.2:
			grade -= 3
		elif kills_to_turns >= 0.16:
			grade -= 4
		elif kills_to_turns > 0:
			grade -= 5
		else:
			grade -= 6
		
		grade += battlefield_impact_grade_delta.call()

		# Need at least a neutral for winning
		return maxi(grade, letter_to_grade["C-"])
		
	#Lost
	if stats.kills >= 3:
		grade = letter_to_grade["C+"]
	elif stats.kills >= 2:
		grade = letter_to_grade["C"]
	elif stats.kills >= 1:
		grade = letter_to_grade["C-"]		
		
	if damage_to_health >= 5:
		grade += 6
	elif damage_to_health >= 3.0:
		grade += 3
	elif damage_to_health >= 2.0:
		grade += 2
	elif damage_to_health >= 1.0:
		grade += 1
	elif damage_to_health >= 0.75:
		# no effect on grade use case to simplify conditionals
		pass
	elif damage_to_health >= 0.5:
		grade -= 1 	
	elif damage_to_health >= 0.35:
		grade -= 2 	
	elif damage_to_health >= 0.25:
		grade -= 3
	elif damage_to_health >= 0.1:
		grade -= 4
	elif stats.damage_done > 0:
		grade -= 5
	else:
		grade -= 6
		
	grade += battlefield_impact_grade_delta.call()

	# If you lose you cannot get higher than a D+
	return clampi(grade, 0, letter_to_grade["D+"])
	
#endregion
