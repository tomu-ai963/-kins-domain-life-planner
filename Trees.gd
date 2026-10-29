extends Node2D

# ── 現実時間で成長するシステム ──────────────────────────────
# 1 現実日 = 樹齢 1 年。アプリを閉じている間も現実時間ぶん育つ。
# T / G キーで時間を先送りしてプレビューできる(見た目だけ。セーブしない)。
const SECONDS_PER_YEAR := 86400.0
const SAVE_PATH := "user://kins_domain_save.json"

# ── 種の循環 ────────────────────────────────────────────────
# 苗は所持している種からしか植えられない。リンゴは樹齢 5 年から秋に実り、
# 収穫すると種が採れる。1 本につき現実の 1 日 1 回(= 樹齢 1 年に 1 回)。
# シベリア杉の種はまだ入手手段がない(Phase 2-2 の日替わりイベントで入れる予定)
const INITIAL_SEEDS := {"birch": 3, "apple": 1, "cedar": 0}
const APPLE_FRUIT_AGE := 5.0
const SEEDS_PER_HARVEST := 2

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

var trees := []               # [{pos: Vector2, species: String, planted_at: int, last_harvest: String}]
var seeds := INITIAL_SEEDS.duplicate()  # 樹種ごとの所持数
var time_offset_years := 0.0  # 時間先送りプレビュー(年)。セーブしない
var season := "summer"        # Main が現実の日付から設定する
var save_path := SAVE_PATH    # テストでは別のファイルに向ける

var _redraw_timer := 0.0

# 種があれば 1 つ使って植える。種がなければ植えずに false
func add_tree(pos: Vector2, species: String) -> bool:
	if int(seeds.get(species, 0)) <= 0:
		return false
	seeds[species] -= 1
	trees.append({"pos": pos, "species": species, "planted_at": OS.get_unix_time(), "last_harvest": ""})
	save_game()
	update()
	return true

# 足元のリンゴを収穫する。結果を表すコードを返す(文言は Main が決める)
#   harvested / none / preview / not_season / young / done
func harvest_nearest(pos: Vector2, max_dist: float) -> String:
	var best := -1
	var best_d := max_dist
	for i in range(trees.size()):
		if trees[i].species != "apple":
			continue
		var d: float = trees[i].pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return "none"
	# 先送りで若木を実らせて収穫できないよう、判定は現実の樹齢で行い、プレビュー中は収穫させない
	if time_offset_years > 0.0:
		return "preview"
	var tree: Dictionary = trees[best]
	if season != "autumn":
		return "not_season"
	if real_age_years(tree) < APPLE_FRUIT_AGE:
		return "young"
	if tree.last_harvest == _today():
		return "done"
	tree.last_harvest = _today()
	seeds["apple"] += SEEDS_PER_HARVEST
	save_game()
	update()
	return "harvested"

func _today() -> String:
	var dt: Dictionary = OS.get_datetime()
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

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
	update()

# 表示用の樹齢(プレビューの先送りを含む)
func age_years(tree: Dictionary) -> float:
	return real_age_years(tree) + time_offset_years

# ゲームの判定用の樹齢(現実時間だけ)
func real_age_years(tree: Dictionary) -> float:
	return (OS.get_unix_time() - tree.planted_at) / SECONDS_PER_YEAR

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
			elif season == "autumn" and age_years(tree) >= APPLE_FRUIT_AGE \
					and tree.last_harvest != _today():
				_draw_fruits(tree.pos, r)                                  # 実(今日収穫したら消える)

func _draw_fruits(pos: Vector2, r: float) -> void:
	# 座標から決まる疑似乱数で毎回同じ場所に実を描く
	var seed_val := int(abs(pos.x) * 7.0 + abs(pos.y) * 13.0)
	for i in range(5):
		var a := float((seed_val + i * 47) % 100) / 100.0 * TAU
		var d := (0.35 + 0.5 * float((seed_val + i * 31) % 100) / 100.0) * r
		draw_circle(pos + Vector2(cos(a), sin(a)) * d, 3.0, Color(0.85, 0.15, 0.12))

# ── セーブ / ロード ──────────────────────────────────────────
# 時間先送りはプレビューなので保存しない
func save_game() -> void:
	var data := {"seeds": seeds, "trees": []}
	for t in trees:
		data.trees.append({
			"x": t.pos.x, "y": t.pos.y,
			"species": t.species, "planted_at": t.planted_at,
			"last_harvest": t.last_harvest,
		})
	var f := File.new()
	if f.open(save_path, File.WRITE) == OK:
		f.store_string(to_json(data))
		f.close()

func load_game() -> void:
	var f := File.new()
	if not f.file_exists(save_path):
		return
	if f.open(save_path, File.READ) != OK:
		return
	var data = parse_json(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	# 旧形式のセーブにある time_offset_years は読まない(先送りは 0 から)
	time_offset_years = 0.0
	# 種の所持数がない旧形式のセーブは、初期の種から始める
	seeds = INITIAL_SEEDS.duplicate()
	var saved_seeds = data.get("seeds", {})
	if typeof(saved_seeds) == TYPE_DICTIONARY:
		for sp in SPECIES:
			if saved_seeds.has(sp):
				seeds[sp] = int(saved_seeds[sp])
	trees.clear()
	for t in data.get("trees", []):
		if t.species in SPECIES:
			trees.append({
				"pos": Vector2(float(t.x), float(t.y)),
				"species": String(t.species),
				"planted_at": int(t.planted_at),
				"last_harvest": String(t.get("last_harvest", "")),
			})
	update()
