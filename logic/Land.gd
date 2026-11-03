extends RefCounted

# ── 木以外の配置: 菜園の区画と池(描画を持たない) ─────────────────
# 見た目は view/ が描く。資源は使わない。同じキーをもう一度押すと取り消せる
# 座標の単位は m
signal changed

const HALF := 50.0              # ドメインの半幅(m)。境界は ±50m
const PLOT_SIZE := 3.0          # 菜園の区画 3m 四方。3m グリッドにそろえて置く
const POND_RADIUS := 4.0        # 池 半径 4m

var plots := []                 # 区画の中心 [Vector2]
var pond = null                 # 池の中心 Vector2。なければ null(池はひとつまで)

# 足元の 3m マスに区画を置く / すでにあれば取り消す。結果: placed / removed / outside
func toggle_plot(pos: Vector2) -> String:
	var c := Vector2((floorf(pos.x / PLOT_SIZE) + 0.5) * PLOT_SIZE, (floorf(pos.y / PLOT_SIZE) + 0.5) * PLOT_SIZE)
	for i in range(plots.size()):
		if plots[i] == c:
			plots.remove_at(i)
			changed.emit()
			return "removed"
	if absf(c.x) + PLOT_SIZE * 0.5 > HALF or absf(c.y) + PLOT_SIZE * 0.5 > HALF:
		return "outside"
	plots.append(c)
	changed.emit()
	return "placed"

# 足元に池を掘る / 池の中なら埋める。結果: placed / removed / one_only / outside
func toggle_pond(pos: Vector2) -> String:
	if pond != null:
		if pos.distance_to(pond) <= POND_RADIUS:
			pond = null
			changed.emit()
			return "removed"
		return "one_only"
	if absf(pos.x) + POND_RADIUS > HALF or absf(pos.y) + POND_RADIUS > HALF:
		return "outside"
	pond = pos
	changed.emit()
	return "placed"

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
	changed.emit()
