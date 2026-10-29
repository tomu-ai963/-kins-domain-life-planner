extends Node2D

# ── 現実時間で成長するシステム ──────────────────────────────
# 1 現実日 = 樹齢 1 年。アプリを閉じている間も現実時間ぶん育つ。
# T / G キーで時間を先送りしてプレビューできる(見た目だけ。セーブしない)。
const SECONDS_PER_YEAR := 86400.0
const SAVE_PATH := "user://kins_domain_save.json"

# ── 種の循環 ────────────────────────────────────────────────
# 苗は所持している種からしか植えられない。リンゴは樹齢 5 年から秋に実り、
# 収穫すると種が採れる。1 本につき現実の 1 日 1 回(= 樹齢 1 年に 1 回)。
# シベリア杉の種は日替わりの発見(リスが実を置いていく)でだけ手に入る
const INITIAL_SEEDS := {"birch": 3, "apple": 1, "cedar": 0}
const APPLE_FRUIT_AGE := 5.0
const SEEDS_PER_HARVEST := 2

# ── 毎日の理由 ──────────────────────────────────────────────
# 水やり: 1 本につき 1 日 1 回、樹齢にボーナスが付く(収穫などの判定にも効く)
# 日替わりの発見: その日はじめて開いたときに 1 つ起きる。開かなかった日の分はたまらない。
# 何が起きるかは日付から決まるので、同じ日に開き直しても引き直しにならない
const WATER_BONUS_YEARS := 0.5
const DAILY_EVENTS := [
	# [id, 重み]。文言は Main が決める
	["birch_seed", 35],  # 白樺の種 +1
	["cedar_seed", 15],  # シベリア杉の種 +1
	["rain", 25],        # 全部の木に水やり済み
	["birds", 25],       # 演出のみ
]

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

# [{pos: Vector2, species: String, planted_at: int, last_harvest: String,
#   last_watered: String, bonus_years: float}]
var trees := []
var seeds := INITIAL_SEEDS.duplicate()  # 樹種ごとの所持数
var last_day := ""            # 日替わりの発見を最後に起こした日(YYYY-MM-DD)
var today_event := ""         # その日の発見の id(HUD で一日中見られるように保存する)
var time_offset_years := 0.0  # 時間先送りプレビュー(年)。セーブしない
var season := "summer"        # Main が現実の日付から設定する
var save_path := SAVE_PATH    # テストでは別のファイルに向ける

var _redraw_timer := 0.0

# 種があれば 1 つ使って植える。種がなければ植えずに false
func add_tree(pos: Vector2, species: String) -> bool:
	if int(seeds.get(species, 0)) <= 0:
		return false
	seeds[species] -= 1
	trees.append({
		"pos": pos, "species": species, "planted_at": OS.get_unix_time(),
		"last_harvest": "", "last_watered": "", "bonus_years": 0.0,
	})
	# 雨の日は一日中降っている扱い。あとから植えた木も水やり済みにする
	if last_day == _today() and today_event == "rain":
		_water(trees[-1])
	save_game()
	update()
	return true

# 足元の木に水をあげる。結果コードを返す: watered / none / done
func water_nearest(pos: Vector2, max_dist: float) -> String:
	var best := nearest_index(pos, max_dist, "")
	if best < 0:
		return "none"
	if not _water(trees[best]):
		return "done"
	save_game()
	update()
	return "watered"

# まだ今日水をあげていない木すべてに水をあげる(雨の日)。あげた本数を返す
func water_all() -> int:
	var n := 0
	for t in trees:
		if _water(t):
			n += 1
	if n > 0:
		save_game()
		update()
	return n

func _water(tree: Dictionary) -> bool:
	if tree.last_watered == _today():
		return false
	tree.last_watered = _today()
	tree.bonus_years += WATER_BONUS_YEARS
	return true

# pos から max_dist 未満でいちばん近い木の添字。species が空なら全樹種。なければ -1
func nearest_index(pos: Vector2, max_dist: float, species: String) -> int:
	var best := -1
	var best_d := max_dist
	for i in range(trees.size()):
		if species != "" and trees[i].species != species:
			continue
		var d: float = trees[i].pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best

# 日付が変わっていたら、その日の発見を 1 つ起こして id を返す。変わっていなければ ""
func check_new_day() -> String:
	var today := _today()
	if last_day == today:
		return ""
	last_day = today
	today_event = roll_daily_event(today)
	_apply_event(today_event)
	save_game()
	update()
	return today_event

# 日付から決まる発見の id(同じ日付なら必ず同じ)
func roll_daily_event(date: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = date.hash()
	var total := 0
	for e in DAILY_EVENTS:
		total += e[1]
	var r := rng.randi_range(0, total - 1)
	for e in DAILY_EVENTS:
		if r < e[1]:
			return e[0]
		r -= e[1]
	return DAILY_EVENTS[-1][0]

func _apply_event(id: String) -> void:
	match id:
		"birch_seed":
			seeds["birch"] += 1
		"cedar_seed":
			seeds["cedar"] += 1
		"rain":
			water_all()

# 足元のリンゴを収穫する。結果を表すコードを返す(文言は Main が決める)
#   harvested / none / preview / not_season / young / done
func harvest_nearest(pos: Vector2, max_dist: float) -> String:
	var best := nearest_index(pos, max_dist, "apple")
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
	var best := nearest_index(pos, max_dist, "")
	if best >= 0:
		trees.remove(best)
		save_game()
		update()
		return true
	return false

func advance_years(years: float) -> void:
	time_offset_years += years
	update()

# プレビューをやめて今日の姿に戻す
func reset_preview() -> void:
	time_offset_years = 0.0
	update()

# 表示用の樹齢(プレビューの先送りを含む)
func age_years(tree: Dictionary) -> float:
	return real_age_years(tree) + time_offset_years

# ゲームの判定用の樹齢(現実時間 + 水やりのボーナス。プレビューは含まない)
func real_age_years(tree: Dictionary) -> float:
	return (OS.get_unix_time() - tree.planted_at) / SECONDS_PER_YEAR + tree.bonus_years

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

	# 今日水をあげた木は、幹のまわりに水色の輪(どの木が済んだか分かるように)
	var today := _today()
	for tree in trees:
		if tree.last_watered == today:
			draw_arc(tree.pos, 8.0, 0, TAU, 16, Color(0.25, 0.60, 0.95, 0.9), 2.0)

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
	var data := {"seeds": seeds, "last_day": last_day, "today_event": today_event, "trees": []}
	for t in trees:
		data.trees.append({
			"x": t.pos.x, "y": t.pos.y,
			"species": t.species, "planted_at": t.planted_at,
			"last_harvest": t.last_harvest,
			"last_watered": t.last_watered, "bonus_years": t.bonus_years,
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
	# 記録がない旧形式のセーブは、次に開いたとき(= 今)その日の発見が起きる
	last_day = String(data.get("last_day", ""))
	today_event = String(data.get("today_event", ""))
	trees.clear()
	for t in data.get("trees", []):
		if t.species in SPECIES:
			trees.append({
				"pos": Vector2(float(t.x), float(t.y)),
				"species": String(t.species),
				"planted_at": int(t.planted_at),
				"last_harvest": String(t.get("last_harvest", "")),
				"last_watered": String(t.get("last_watered", "")),
				"bonus_years": float(t.get("bonus_years", 0.0)),
			})
	update()
