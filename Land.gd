extends Node2D

# ── 木以外の配置: 菜園の区画と池 ──────────────────────────────
# 見た目は当面 _draw() の四角と円(Phase 3 で絵に差し替える)。資源は使わない。
# 同じキーをもう一度押すと取り消せる
const HALF := 2000.0            # ドメインの半幅(px)。境界は ±50m
const PLOT_SIZE := 120.0        # 菜園の区画 3m 四方。3m グリッドにそろえて置く
const POND_RADIUS := 160.0      # 池 半径 4m

var plots := []                 # 区画の中心 [Vector2]
var pond = null                 # 池の中心 Vector2。なければ null(池はひとつまで)

# 足元の 3m マスに区画を置く / すでにあれば取り消す。結果: placed / removed / outside
func toggle_plot(pos: Vector2) -> String:
	var c := Vector2((floor(pos.x / PLOT_SIZE) + 0.5) * PLOT_SIZE, (floor(pos.y / PLOT_SIZE) + 0.5) * PLOT_SIZE)
	for i in range(plots.size()):
		if plots[i] == c:
			plots.remove(i)
			update()
			return "removed"
	if abs(c.x) + PLOT_SIZE * 0.5 > HALF or abs(c.y) + PLOT_SIZE * 0.5 > HALF:
		return "outside"
	plots.append(c)
	update()
	return "placed"

# 足元に池を掘る / 池の中なら埋める。結果: placed / removed / one_only / outside
func toggle_pond(pos: Vector2) -> String:
	if pond != null:
		if pos.distance_to(pond) <= POND_RADIUS:
			pond = null
			update()
			return "removed"
		return "one_only"
	if abs(pos.x) + POND_RADIUS > HALF or abs(pos.y) + POND_RADIUS > HALF:
		return "outside"
	pond = pos
	update()
	return "placed"

func _draw() -> void:
	var soil := Color(0.42, 0.28, 0.16)
	var furrow := Color(0.30, 0.20, 0.11)
	var h := PLOT_SIZE * 0.5
	for c in plots:
		draw_rect(Rect2(c.x - h + 4, c.y - h + 4, PLOT_SIZE - 8, PLOT_SIZE - 8), soil)
		for k in range(1, 4):  # 畝
			var y: float = c.y - h + 4 + (PLOT_SIZE - 8) * k / 4.0
			draw_line(Vector2(c.x - h + 10, y), Vector2(c.x + h - 10, y), furrow, 2)
	if pond != null:
		draw_circle(pond, POND_RADIUS, Color(0.28, 0.52, 0.78, 0.85))
		draw_circle(pond, POND_RADIUS * 0.6, Color(0.34, 0.60, 0.86, 0.6))

# ── セーブ用 ──────────────────────────────────────────────
func to_save() -> Dictionary:
	var ps := []
	for c in plots:
		ps.append([c.x, c.y])
	var d := {"plots": ps}
	if pond != null:
		d["pond"] = [pond.x, pond.y]
	return d

func from_save(d: Dictionary) -> void:
	plots.clear()
	for p in d.get("plots", []):
		plots.append(Vector2(float(p[0]), float(p[1])))
	pond = null
	var pd = d.get("pond", null)
	if typeof(pd) == TYPE_ARRAY and pd.size() == 2:
		pond = Vector2(float(pd[0]), float(pd[1]))
	update()
