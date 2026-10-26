extends RefCounted
class_name ChipCatalog
## Chip definitions as data. Own creative names (BN-inspired, not Capcom IP).

enum Op { DAMAGE_ROW, DAMAGE_AHEAD, HEAL, PANEL_STEAL }

static func pool() -> Array[Dictionary]:
	return [
		{"id": "pulse_a", "name": "PulseShot", "code": "A", "cost": 1, "op": Op.DAMAGE_ROW, "power": 40, "color": Color(0.4, 0.75, 1.0)},
		{"id": "pulse_b", "name": "PulseShot", "code": "B", "cost": 1, "op": Op.DAMAGE_ROW, "power": 40, "color": Color(0.4, 0.75, 1.0)},
		{"id": "pulse_c", "name": "PulseShot", "code": "C", "cost": 1, "op": Op.DAMAGE_ROW, "power": 40, "color": Color(0.4, 0.75, 1.0)},
		{"id": "blade_s", "name": "BladeCut", "code": "S", "cost": 1, "op": Op.DAMAGE_AHEAD, "power": 80, "color": Color(0.95, 0.85, 0.3)},
		{"id": "blade_s2", "name": "BladeCut", "code": "S", "cost": 1, "op": Op.DAMAGE_AHEAD, "power": 80, "color": Color(0.95, 0.85, 0.3)},
		{"id": "heal_r", "name": "HealPulse", "code": "*", "cost": 1, "op": Op.HEAL, "power": 30, "color": Color(0.4, 0.95, 0.5)},
		{"id": "steal_a", "name": "PanelSteal", "code": "A", "cost": 1, "op": Op.PANEL_STEAL, "power": 0, "color": Color(0.7, 0.4, 0.95)},
		{"id": "heavy_g", "name": "HeavyBolt", "code": "G", "cost": 1, "op": Op.DAMAGE_ROW, "power": 100, "color": Color(1.0, 0.45, 0.25)},
	]

## Build a 30-chip folder from the pool (duplicates allowed like BN folders).
static func make_folder(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var base := pool()
	var folder: Array[Dictionary] = []
	# Fixed starter mix for a readable first fight.
	var recipe: Array[String] = [
		"pulse_a", "pulse_a", "pulse_a", "pulse_a", "pulse_a",
		"pulse_b", "pulse_b", "pulse_b", "pulse_b", "pulse_b",
		"pulse_c", "pulse_c", "pulse_c", "pulse_c",
		"blade_s", "blade_s", "blade_s", "blade_s", "blade_s",
		"blade_s2", "blade_s2", "blade_s2",
		"heal_r", "heal_r", "heal_r",
		"steal_a", "steal_a",
		"heavy_g", "heavy_g", "heavy_g",
	]
	var by_id := {}
	for c in base:
		by_id[c["id"]] = c
	for id in recipe:
		folder.append(by_id[id].duplicate(true))
	# Shuffle copy for draw order.
	_shuffle(folder, rng)
	return folder

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
