extends Node2D
const ChipCatalog = preload("res://scripts/chip_catalog.gd")
## ALS NetBattle vertical slice — 6×3 panels (player 3×3 | enemy 3×3), 30-chip folder.
## Question: is panel move + chip queue fun with greybox art?

enum Phase { CUSTOM, BATTLE, WIN, LOSE }

const COLS := 6
const ROWS := 3
const CELL := Vector2(88, 72)
const ORIGIN := Vector2(180, 140)

var phase: Phase = Phase.CUSTOM
var rng := RandomNumberGenerator.new()

# Ownership: 0 = player, 1 = enemy. Starts as classic BN split.
var owner_grid: Array = []  # [col][row] -> 0|1

var player_pos := Vector2i(1, 1)
var enemy_pos := Vector2i(4, 1)
var player_hp := 200
var enemy_hp := 200
var player_max_hp := 200
var enemy_max_hp := 200

var folder: Array[Dictionary] = []  # remaining draw pile
var discard: Array[Dictionary] = []
var custom_hand: Array[Dictionary] = []  # up to 5
var selected: Array[int] = []  # indices into custom_hand
var chip_queue: Array[Dictionary] = []

var move_cooldown := 0.0
var buster_cooldown := 0.0
var enemy_timer := 0.0
var custom_gauge := 0.0  # fills in battle; full -> can open custom
var flash_msg := ""
var flash_t := 0.0
var projectiles: Array[Dictionary] = []

func _ready() -> void:
	rng.randomize()
	_init_grid()
	folder = ChipCatalog.make_folder(rng)
	_open_custom(true)

func _init_grid() -> void:
	owner_grid.clear()
	for c in COLS:
		var col: Array = []
		for r in ROWS:
			col.append(0 if c < 3 else 1)
		owner_grid.append(col)

func _open_custom(first: bool = false) -> void:
	phase = Phase.CUSTOM
	custom_gauge = 0.0
	selected.clear()
	# Draw up to 5 from folder (reshuffle discard if needed).
	custom_hand.clear()
	while custom_hand.size() < 5:
		if folder.is_empty():
			if discard.is_empty():
				break
			folder.append_array(discard)
			discard.clear()
			ChipCatalog._shuffle(folder, rng)
		custom_hand.append(folder.pop_back())
	if first:
		_toast("CUSTOM: 1–5 select · Enter OK · same code = link")

func _process(delta: float) -> void:
	if flash_t > 0.0:
		flash_t -= delta
	move_cooldown = maxf(0.0, move_cooldown - delta)
	buster_cooldown = maxf(0.0, buster_cooldown - delta)
	_update_projectiles(delta)
	if phase == Phase.BATTLE:
		custom_gauge = minf(1.0, custom_gauge + delta * 0.12)
		enemy_timer -= delta
		if enemy_timer <= 0.0:
			_enemy_act()
			enemy_timer = rng.randf_range(0.55, 0.95)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.WIN or phase == Phase.LOSE:
		if event.is_action_pressed("confirm_custom"):
			_restart()
		return
	if phase == Phase.CUSTOM:
		_custom_input(event)
		return
	# Battle
	if event.is_action_pressed("open_custom") and custom_gauge >= 1.0:
		_open_custom()
		return
	if event.is_action_pressed("move_up"):
		_try_move(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_try_move(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_try_move(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_try_move(Vector2i(1, 0))
	elif event.is_action_pressed("buster"):
		_fire_buster()
	elif event.is_action_pressed("use_chip"):
		_fire_next_chip()

func _custom_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: Key = event.keycode
		if k >= KEY_1 and k <= KEY_5:
			var idx := int(k - KEY_1)
			_toggle_select(idx)
		elif event.is_action_pressed("confirm_custom"):
			_confirm_custom()

func _toggle_select(idx: int) -> void:
	if idx < 0 or idx >= custom_hand.size():
		return
	if idx in selected:
		selected.erase(idx)
		return
	# Same-code link rule (BN-lite): first free; later must match prior code or '*' .
	if selected.is_empty():
		selected.append(idx)
		return
	var last_code: String = str(custom_hand[selected.back()]["code"])
	var code: String = str(custom_hand[idx]["code"])
	if code == "*" or last_code == "*" or code == last_code:
		selected.append(idx)
	else:
		_toast("Need same code (or *) to link")

func _confirm_custom() -> void:
	chip_queue.clear()
	# Preserve selection order; unselected go to discard.
	var taken: Dictionary = {}
	for i in selected:
		chip_queue.append(custom_hand[i])
		taken[i] = true
	for i in custom_hand.size():
		if not taken.has(i):
			discard.append(custom_hand[i])
	custom_hand.clear()
	selected.clear()
	phase = Phase.BATTLE
	enemy_timer = 0.8
	_toast("BATTLE · WASD move · X buster · Space chip · C custom")

func _try_move(d: Vector2i) -> void:
	if move_cooldown > 0.0:
		return
	var np := player_pos + d
	if not _in_bounds(np):
		return
	if owner_grid[np.x][np.y] != 0:
		return
	player_pos = np
	move_cooldown = 0.12

func _fire_buster() -> void:
	if buster_cooldown > 0.0:
		return
	buster_cooldown = 0.22
	projectiles.append({
		"kind": "buster",
		"row": player_pos.y,
		"col": float(player_pos.x) + 0.5,
		"speed": 14.0,
		"power": 3,
		"from_player": true,
	})

func _fire_next_chip() -> void:
	if chip_queue.is_empty():
		_toast("No chips — wait gauge + C")
		return
	var chip: Dictionary = chip_queue.pop_front()
	discard.append(chip)
	_resolve_chip(chip, true)

func _resolve_chip(chip: Dictionary, from_player: bool) -> void:
	var op: int = int(chip["op"])
	var power: int = int(chip["power"])
	match op:
		ChipCatalog.Op.DAMAGE_ROW:
			projectiles.append({
				"kind": "row",
				"row": player_pos.y if from_player else enemy_pos.y,
				"col": float(player_pos.x + 1) if from_player else float(enemy_pos.x - 1),
				"speed": 10.0 if from_player else -10.0,
				"power": power,
				"from_player": from_player,
				"color": chip.get("color", Color.WHITE),
			})
			_toast(str(chip["name"]))
		ChipCatalog.Op.DAMAGE_AHEAD:
			var hit := false
			if from_player:
				hit = enemy_pos.y == player_pos.y and enemy_pos.x == player_pos.x + 1
				if hit:
					_hurt_enemy(power)
			else:
				hit = player_pos.y == enemy_pos.y and player_pos.x == enemy_pos.x - 1
				if hit:
					_hurt_player(power)
			if hit:
				_toast(str(chip["name"]) + "!")
			else:
				_toast(str(chip["name"]) + " (miss)")
		ChipCatalog.Op.HEAL:
			if from_player:
				player_hp = mini(player_max_hp, player_hp + power)
			else:
				enemy_hp = mini(enemy_max_hp, enemy_hp + power)
			_toast(str(chip["name"]) + " +" + str(power))
		ChipCatalog.Op.PANEL_STEAL:
			if from_player:
				var c := _front_enemy_col()
				if c >= 0:
					for r in ROWS:
						owner_grid[c][r] = 0
					_toast("PanelSteal col " + str(c))
					if owner_grid[enemy_pos.x][enemy_pos.y] != 1:
						enemy_pos = _find_pos(1)
			else:
				var c2 := _front_player_col()
				if c2 >= 0:
					for r in ROWS:
						owner_grid[c2][r] = 1
					if owner_grid[player_pos.x][player_pos.y] != 0:
						player_pos = _find_pos(0)

func _front_enemy_col() -> int:
	for c in range(3, COLS):
		var enemy_owned := false
		for r in ROWS:
			if owner_grid[c][r] == 1:
				enemy_owned = true
				break
		if enemy_owned:
			return c
	return -1

func _front_player_col() -> int:
	for c in range(2, -1, -1):
		var owned := false
		for r in ROWS:
			if owner_grid[c][r] == 0:
				owned = true
				break
		if owned:
			return c
	return -1

func _find_pos(side: int) -> Vector2i:
	for c in COLS:
		for r in ROWS:
			if owner_grid[c][r] == side:
				return Vector2i(c, r)
	return Vector2i(1, 1) if side == 0 else Vector2i(4, 1)

func _update_projectiles(delta: float) -> void:
	var next: Array[Dictionary] = []
	for p in projectiles:
		p["col"] = float(p["col"]) + float(p["speed"]) * delta
		var hit := false
		if p["from_player"]:
			if int(round(float(p["row"]))) == enemy_pos.y and float(p["col"]) >= float(enemy_pos.x) - 0.35:
				_hurt_enemy(int(p["power"]))
				hit = true
		else:
			if int(round(float(p["row"]))) == player_pos.y and float(p["col"]) <= float(player_pos.x) + 0.35:
				_hurt_player(int(p["power"]))
				hit = true
		if hit:
			continue
		if float(p["col"]) < -1.0 or float(p["col"]) > COLS + 1.0:
			continue
		next.append(p)
	projectiles = next

func _hurt_enemy(amount: int) -> void:
	enemy_hp = maxi(0, enemy_hp - amount)
	if enemy_hp <= 0:
		phase = Phase.WIN
		_toast("YOU WIN — Enter restart")

func _hurt_player(amount: int) -> void:
	player_hp = maxi(0, player_hp - amount)
	if player_hp <= 0:
		phase = Phase.LOSE
		_toast("DELETED — Enter restart")

func _enemy_act() -> void:
	if phase != Phase.BATTLE:
		return
	# Move randomly on owned panels, sometimes shoot.
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]
	var d: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
	var np := enemy_pos + d
	if _in_bounds(np) and owner_grid[np.x][np.y] == 1:
		enemy_pos = np
	if rng.randf() < 0.55:
		projectiles.append({
			"kind": "buster",
			"row": enemy_pos.y,
			"col": float(enemy_pos.x) - 0.5,
			"speed": -12.0,
			"power": 8,
			"from_player": false,
		})

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < COLS and p.y >= 0 and p.y < ROWS

func _toast(msg: String) -> void:
	flash_msg = msg
	flash_t = 1.4

func _restart() -> void:
	player_hp = player_max_hp
	enemy_hp = enemy_max_hp
	player_pos = Vector2i(1, 1)
	enemy_pos = Vector2i(4, 1)
	projectiles.clear()
	chip_queue.clear()
	discard.clear()
	_init_grid()
	folder = ChipCatalog.make_folder(rng)
	_open_custom(true)

func _cell_rect(c: int, r: int) -> Rect2:
	return Rect2(ORIGIN + Vector2(c * CELL.x, r * CELL.y), CELL - Vector2(4, 4))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 540)), Color(0.08, 0.09, 0.14))
	# Panels
	for c in COLS:
		for r in ROWS:
			var rect := _cell_rect(c, r)
			var owned: int = owner_grid[c][r]
			var col := Color(0.15, 0.35, 0.7) if owned == 0 else Color(0.65, 0.18, 0.22)
			draw_rect(rect, col)
			draw_rect(rect, Color(1, 1, 1, 0.15), false, 2.0)
	# Actors
	_draw_actor(player_pos, Color(0.35, 0.9, 1.0), "P")
	_draw_actor(enemy_pos, Color(1.0, 0.45, 0.4), "E")
	# Projectiles
	for p in projectiles:
		var pr := Rect2(
			ORIGIN + Vector2(float(p["col"]) * CELL.x + 28, float(p["row"]) * CELL.y + 28),
			Vector2(24, 16)
		)
		var pc: Color = p.get("color", Color(1, 1, 0.6))
		draw_rect(pr, pc)
	# HUD
	draw_string(ThemeDB.fallback_font, Vector2(24, 36), "HP %d" % player_hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.95, 1))
	draw_string(ThemeDB.fallback_font, Vector2(780, 36), "HP %d" % enemy_hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.55, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(24, 520), "ALS NetBattle · BN-inspired greybox · own creative use", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.55, 0.65))
	# Custom gauge
	var grect := Rect2(360, 28, 240, 14)
	draw_rect(grect, Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(grect.position, Vector2(grect.size.x * custom_gauge, grect.size.y)), Color(0.95, 0.85, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(360, 24), "CUSTOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.7))
	# Chip queue
	draw_string(ThemeDB.fallback_font, Vector2(24, 64), "Queue: " + _queue_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.9, 0.85))
	if flash_t > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(300, 100), flash_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.75))
	if phase == Phase.CUSTOM:
		_draw_custom_ui()
	elif phase == Phase.WIN:
		draw_string(ThemeDB.fallback_font, Vector2(380, 260), "YOU WIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.5, 1, 0.6))
	elif phase == Phase.LOSE:
		draw_string(ThemeDB.fallback_font, Vector2(380, 260), "DELETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1, 0.4, 0.4))

func _draw_actor(pos: Vector2i, color: Color, label: String) -> void:
	var rect := _cell_rect(pos.x, pos.y).grow(-14)
	draw_rect(rect, color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0))

func _queue_text() -> String:
	if chip_queue.is_empty():
		return "(empty)"
	var parts: PackedStringArray = []
	for c in chip_queue:
		parts.append("%s%s" % [c["name"], c["code"]])
	return " > ".join(parts)

func _draw_custom_ui() -> void:
	draw_rect(Rect2(80, 360, 800, 150), Color(0.05, 0.06, 0.1, 0.92))
	draw_string(ThemeDB.fallback_font, Vector2(100, 390), "CUSTOM SCREEN — pick chips (same code links). Enter to fight.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 1))
	for i in custom_hand.size():
		var chip: Dictionary = custom_hand[i]
		var x := 100.0 + i * 150.0
		var selected_here := i in selected
		var bg := Color(0.2, 0.25, 0.35) if not selected_here else Color(0.35, 0.45, 0.2)
		draw_rect(Rect2(x, 410, 130, 80), bg)
		draw_rect(Rect2(x, 410, 130, 80), chip.get("color", Color.WHITE), false, 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(x + 8, 435), "[%d] %s" % [i + 1, chip["code"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(x + 8, 460), str(chip["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.95, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(x + 8, 480), "pwr %s" % str(chip["power"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.8))
