class_name MoveDef
extends Resource
## One attack. Lives as a .tres in res://data/moves/. Timing, reach, damage scaling and feel are all here,
## so new attacks are mostly new files. Played by Attacker; damage math is in Damage.

@export var id: StringName
@export var display_name: String
@export_enum("melee", "projectile") var kind: String = "melee"
## Authored animation clip for this move. Falls back to "Attack" / "Strike".
@export var anim_name: String = "Attack"

@export_group("Damage")
@export_enum("power", "focus", "hp", "guard", "speed") var atk_stat: String = "power"
@export var atk_mult := 1.3
## How much of the defender's guard stat is subtracted.
@export var def_mult := 0.5
## Apply the elemental type multiplier (Types.mult).
@export var use_type := false

@export_group("Timing (seconds)")
@export var windup := 0.08
@export var active := 0.1
@export var recovery := 0.25
@export var cooldown := 0.45

@export_group("Reach")
## Melee: hitbox distance in front of the body. Projectile: max travel distance.
@export var reach := 1.6
@export var radius := 1.2
@export var proj_speed := 14.0
## Forward push on the attacker when the hit comes out.
@export var lunge := 4.0

@export_group("Feel")
@export var knockback := 7.0
@export var hitstun := 0.25
@export var hitstop := 0.065
