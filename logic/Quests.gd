extends Reference

# ── 段階クエスト(原作『アナスタシア』の一族の土地づくり) ────────────
# 順番に 1 つずつ進める。先に条件を満たしていたら、その段階に来たときにすぐ達成。
# 達成した段階は、あとで木を抜いても戻らない。4 つそろうと「愛の空間」が完成する。
# 文言は Main、見た目は view/QuestsView.gd が決める(ここは id と数だけ)
signal changed

const QUESTS := ["hedge", "garden", "pond", "family_cedar"]

const HALF := 2000.0             # ドメインの半幅(px)
const HEDGE_BAND := 120.0        # 生垣とみなす帯: 境界から内側 3m
const HEDGE_SEGMENT := 400.0     # 周囲を 10m ごとに区切る
const HEDGE_SEGMENTS := 40       # 周囲 400m / 10m
const GARDEN_PLOTS := 4          # 菜園は区画 4 つ
const FAMILY_CEDAR_RADIUS := 200.0  # 中心から 5m 以内のシベリア杉

var stage := 0                   # いま取り組んでいる段階(0〜3)。4 で完成
var forest: Reference            # GameWorld が設定する
var land: Reference

func is_complete() -> bool:
	return stage >= QUESTS.size()

func current_id() -> String:
	if is_complete():
		return ""
	return QUESTS[stage]

# 生垣の 40 区画それぞれに木があるか。角の近くの木は 2 辺の区画を同時に埋める
func hedge_filled() -> Array:
	var filled := []
	filled.resize(HEDGE_SEGMENTS)
	for i in range(HEDGE_SEGMENTS):
		filled[i] = false
	for t in forest.trees:
		var p: Vector2 = t.pos
		if abs(p.x) > HALF or abs(p.y) > HALF:
			continue
		# 周囲を時計回りに 1 本の線とみなした位置(px): 上辺 → 右辺 → 下辺 → 左辺
		if p.y - (-HALF) <= HEDGE_BAND:
			_fill(filled, p.x + HALF)
		if HALF - p.x <= HEDGE_BAND:
			_fill(filled, 2 * HALF + (p.y + HALF))
		if HALF - p.y <= HEDGE_BAND:
			_fill(filled, 4 * HALF + (HALF - p.x))
		if p.x - (-HALF) <= HEDGE_BAND:
			_fill(filled, 6 * HALF + (HALF - p.y))
	return filled

func _fill(filled: Array, s: float) -> void:
	filled[int(clamp(floor(s / HEDGE_SEGMENT), 0, HEDGE_SEGMENTS - 1))] = true

# [いまの数, 目標の数]
func progress(id: String) -> Array:
	match id:
		"hedge":
			var n := 0
			for f in hedge_filled():
				if f:
					n += 1
			return [n, HEDGE_SEGMENTS]
		"garden":
			return [int(min(land.plots.size(), GARDEN_PLOTS)), GARDEN_PLOTS]
		"pond":
			return [0 if land.pond == null else 1, 1]
		"family_cedar":
			for t in forest.trees:
				if t.species == "cedar" and t.pos.length() <= FAMILY_CEDAR_RADIUS:
					return [1, 1]
			return [0, 1]
	return [0, 1]

# いまの段階の条件を満たしていれば進める(満たしている限り続けて進む)。
# 新しく達成した id の配列を返す。完成したら最後に "complete" が入る
func advance() -> Array:
	var done := []
	while not is_complete():
		var p: Array = progress(current_id())
		if p[0] < p[1]:
			break
		done.append(current_id())
		stage += 1
		if is_complete():
			done.append("complete")
	if not done.empty():
		emit_signal("changed")
	return done

# 生垣の区画 i の真ん中、境界から 1.5m 内側の点
func segment_center(i: int) -> Vector2:
	var s := (i + 0.5) * HEDGE_SEGMENT
	var inset := HEDGE_BAND * 0.5
	if s < 2 * HALF:
		return Vector2(-HALF + s, -HALF + inset)
	s -= 2 * HALF
	if s < 2 * HALF:
		return Vector2(HALF - inset, -HALF + s)
	s -= 2 * HALF
	if s < 2 * HALF:
		return Vector2(HALF - s, HALF - inset)
	s -= 2 * HALF
	return Vector2(-HALF + inset, HALF - s)

# ── セーブ用 ──────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"stage": stage}

func from_save(d: Dictionary) -> void:
	stage = int(clamp(int(d.get("stage", 0)), 0, QUESTS.size()))
	emit_signal("changed")
