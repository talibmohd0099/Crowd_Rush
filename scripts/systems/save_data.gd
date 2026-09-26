class_name SaveData
extends RefCounted
## Local-only persistence (no server, no account): best surviving crowd.

const PATH := "user://crowd_rush_save.cfg"

## Survives scene reloads for the current session.
static var session_best := -1
static var intro_seen := false


static func load_best() -> int:
	if session_best >= 0:
		return session_best
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		session_best = int(cfg.get_value("records", "best_crowd", 0))
	else:
		session_best = 0
	return session_best


## Records a result and returns the (possibly new) best.
static func submit(survived: int) -> int:
	var best := load_best()
	if survived > best:
		best = survived
		session_best = best
		var cfg := ConfigFile.new()
		cfg.load(PATH)
		cfg.set_value("records", "best_crowd", best)
		cfg.save(PATH)
	return best
