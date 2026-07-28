extends Node2D

# ── 現実時間で成長するシステム ──────────────────────────────
# 1 現実日 = 樹齢 1 年。アプリを閉じている間も現実時間ぶん育つ。
# T / G キーで時間を先送りしてプレビューできる(セーブされる)。
const SECONDS_PER_YEAR := 86400.0
const SAVE_PATH := "user://kins_domain_save.json"

# 樹種ごとの成長パラメータ
#   max_r: 成熟時の樹冠半径(px, 40px = 1m)
#   tau:   成長の時定数(年)。小さいほど早く育つ
const SPECIES := {
	"birch": {
		"name": "白樺", "max_r": 140.0, "tau": 6.0, "evergreen": false,
		"leaf": Color(0.45, 0.72, 0.30, 0.60),
		"leaf_autumn": Color(0.85, 0.72, 0.20, 0.60),
		"trunk": Color(0.92, 0.92, 0.88),
	},
	"apple": {
		"name": "リンゴ", "max_r": 120.0, "tau": 12.0, "evergreen": false,
		"leaf": Color(0.20, 0.60, 0.20, 0.60),
		"leaf_autumn": Color(0.80, 0.55, 0.18, 0.60),
		"trunk": Color(0.35, 0.22, 0.10),
	},
	"cedar": {
		"name": "シベリア杉", "max_r": 240.0, "tau": 40.0, "evergreen": true,
		"leaf": Color(0.08, 0.42, 0.20, 0.65),
		"leaf_autumn": Color(0.08, 0.42, 0.20, 0.65),
		"trunk": Color(0.30, 0.18, 0.08),
	},
}

var trees := []               # [{pos: Vector2, species: String, planted_at: int}]
var time_offset_years := 0.0  # デバッグ用の時間先送り(年)
var season := "summer"        # Main が現実の日付から設定する

var _redraw_timer := 0.0

func add_tree(pos: Vector2, species: String) -> void:
	trees.append({"pos": pos, "species": species, "planted_at": OS.get_unix_time()})
	save_game()
	update()

func remove_nearest(pos: Vector2, max_dist: float) -> bool:
	var best := -1
	var best_d := max_dist
	for i in range(trees.size()):
		var d: float = trees[i].pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		trees.remove(best)
		save_game()
		update()
		return true
	return false

func advance_years(years: float) -> void:
	time_offset_years += years
	save_game()
	update()

func age_years(tree: Dictionary) -> float:
	return (OS.get_unix_time() - tree.planted_at) / SECONDS_PER_YEAR + time_offset_years

func radius_of(tree: Dictionary) -> float:
	var sp: Dictionary = SPECIES[tree.species]
	return sp.max_r * (1.0 - exp(-age_years(tree) / sp.tau))

func _process(delta: float) -> void:
	# 成長は年単位なので毎秒 1 回の再描画で十分(低スペック配慮)
	_redraw_timer += delta
	if _redraw_timer >= 1.0:
		_redraw_timer = 0.0
		update()

func _draw() -> void:
	for tree in trees:
		var sp: Dictionary = SPECIES[tree.species]
		var r := radius_of(tree)

		if r < 6.0:
			# 苗木フェーズ
			draw_circle(tree.pos, 3.0, Color(0.15, 0.65, 0.15))
			continue

		if season == "winter" and not sp.evergreen:
			# 落葉樹の冬: 裸の樹形(輪郭のみ) + 幹
			draw_arc(tree.pos, r * 0.75, 0, TAU, 32, Color(0.45, 0.38, 0.30, 0.7), 1.5)
			draw_circle(tree.pos, 4.0, sp.trunk)
			continue

		var leaf: Color = sp.leaf
		if season == "autumn" and not sp.evergreen:
			leaf = sp.leaf_autumn
		elif season == "winter" and sp.evergreen:
			# 常緑樹の冬: 少し沈んだ色
			leaf = Color(leaf.r * 0.8, leaf.g * 0.8, leaf.b * 0.85, leaf.a)

		draw_circle(tree.pos, r, leaf)
		draw_circle(tree.pos, r * 0.4, Color(leaf.r * 0.8, leaf.g * 0.85, leaf.b * 0.8, 0.3))
		draw_circle(tree.pos, 4.0, sp.trunk)

		# リンゴの季節演出
		if tree.species == "apple":
			if season == "spring":
				draw_circle(tree.pos, r, Color(0.98, 0.80, 0.86, 0.35))  # 花
			elif season == "autumn" and age_years(tree) >= 5.0:
				_draw_fruits(tree.pos, r)                                  # 実

func _draw_fruits(pos: Vector2, r: float) -> void:
	# 座標から決まる疑似乱数で毎回同じ場所に実を描く
	var seed_val := int(abs(pos.x) * 7.0 + abs(pos.y) * 13.0)
	for i in range(5):
		var a := float((seed_val + i * 47) % 100) / 100.0 * TAU
		var d := (0.35 + 0.5 * float((seed_val + i * 31) % 100) / 100.0) * r
		draw_circle(pos + Vector2(cos(a), sin(a)) * d, 3.0, Color(0.85, 0.15, 0.12))

# ── セーブ / ロード ──────────────────────────────────────────
func save_game() -> void:
	var data := {"time_offset_years": time_offset_years, "trees": []}
	for t in trees:
		data.trees.append({
			"x": t.pos.x, "y": t.pos.y,
			"species": t.species, "planted_at": t.planted_at,
		})
	var f := File.new()
	if f.open(SAVE_PATH, File.WRITE) == OK:
		f.store_string(to_json(data))
		f.close()

func load_game() -> void:
	var f := File.new()
	if not f.file_exists(SAVE_PATH):
		return
	if f.open(SAVE_PATH, File.READ) != OK:
		return
	var data = parse_json(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	time_offset_years = float(data.get("time_offset_years", 0.0))
	trees.clear()
	for t in data.get("trees", []):
		if t.species in SPECIES:
			trees.append({
				"pos": Vector2(float(t.x), float(t.y)),
				"species": String(t.species),
				"planted_at": int(t.planted_at),
			})
	update()
