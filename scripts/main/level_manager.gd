class_name LevelManager
extends Node3D
## One straight, hand-tuned level. Distances are in world units along the road
## (world z = -distance). Change the layout here - everything else adapts.
##
##  START -> intro -> Gate1 -> Gate2 -> Obstacle -> Gate3 -> Gate4 -> Arena -> Boss
##  Crowd speed is 10 u/s, so 10 units ~ 1 second of play.

const GATE_SCENE := preload("res://scenes/gates/Gate.tscn")

## Tuning (see README "Gate calculations"): best path 5 -> 15 -> 25 -> ~22 -> 44 -> 132
const GATE_LAYOUT: Array[Dictionary] = [
	{"d": 100.0, "left": [Gate.Op.ADD, 10], "right": [Gate.Op.MUL, 2]},
	{"d": 180.0, "left": [Gate.Op.SUB, 5], "right": [Gate.Op.ADD, 10]},
	{"d": 315.0, "left": [Gate.Op.MUL, 2], "right": [Gate.Op.ADD, 15]},
	{"d": 395.0, "left": [Gate.Op.SUB, 10], "right": [Gate.Op.MUL, 3]},
]
const OBSTACLE_D := 250.0
const ARENA_D := 455.0
const BOSS_TRIGGER_D := 446.0 ## crowd front reaches this -> boss entrance
const HALT_D := 468.0 ## crowd centre stops here during the entrance
const BOSS_STEP_IN := 2.8 ## boss walks this far forward during its entrance
const INTRO_END_D := 54.0

var gates: Array[Gate] = []

@onready var obstacle: ObstacleBarrier = $ObstacleBarrier
@onready var arena: BossArena = $BossArena
@onready var boss: BossController = $Boss


func build(gate_manager: GateManager) -> void:
	for def in GATE_LAYOUT:
		var g: Gate = GATE_SCENE.instantiate()
		g.left_op = def["left"][0]
		g.left_value = def["left"][1]
		g.right_op = def["right"][0]
		g.right_value = def["right"][1]
		g.position = Vector3(0, 0, -float(def["d"]))
		g.name = "Gate%d" % (gates.size() + 1)
		add_child(g)
		gates.append(g)
		gate_manager.register(g)
	obstacle.position = Vector3(0, 0, -OBSTACLE_D)
	arena.position = Vector3(0, 0, -ARENA_D)
	boss.position = Vector3(0, 0, -(ARENA_D + arena.boss_offset + BOSS_STEP_IN))
	boss.rotation.y = PI # face the incoming crowd (+Z)


func first_gate() -> Gate:
	return gates[0]


func obstacle_z() -> float:
	return -OBSTACLE_D


func boss_trigger_z() -> float:
	return -BOSS_TRIGGER_D


func halt_z() -> float:
	return -HALT_D


func boss_final_position() -> Vector3:
	return Vector3(0, 0, -(ARENA_D + arena.boss_offset))


## 0..1 progress from start to boss for the HUD track.
func progress_for(z: float) -> float:
	return clampf((-z - INTRO_END_D) / (BOSS_TRIGGER_D - INTRO_END_D), 0.0, 1.0)
