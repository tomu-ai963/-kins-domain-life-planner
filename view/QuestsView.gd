extends Node2D

# ── 段階クエストの 2D 表示(いまの段階のヒントと完成の演出) ────────────
# 状態とルールは logic/Quests.gd。生垣の印は木の増減でも変わるので、木と土地の変化でも描き直す
var quests: Reference

func setup(q: Reference) -> void:
	quests = q
	quests.connect("changed", self, "update")
	quests.forest.connect("changed", self, "update")
	quests.land.connect("changed", self, "update")
	update()

func _draw() -> void:
	if quests == null:
		return
	var half: float = quests.HALF
	if quests.is_complete():
		# 愛の空間: 中心(家族の杉)から光の輪が広がり、境界が金色に縁取られる。
		# 秋の草地は黄色いので、面の塗りではなく輪と太い縁で見せる
		for k in range(1, 6):
			draw_arc(Vector2.ZERO, 300.0 * k, 0, TAU, 96, Color(1.0, 0.92, 0.55, 0.55 - 0.08 * k), 14.0)
		var c := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
		for i in range(4):
			draw_line(c[i], c[(i + 1) % 4], Color(1.0, 0.95, 0.70, 0.5), 48)  # 外側のにじみ
			draw_line(c[i], c[(i + 1) % 4], Color(1.0, 0.78, 0.10, 1.0), 20)
		return
	match quests.current_id():
		"hedge":
			# 40 区画の印: 埋まった区画は緑の丸、まだの区画は白い輪(土地全体に引いても見える大きさ)
			var filled: Array = quests.hedge_filled()
			for i in range(quests.HEDGE_SEGMENTS):
				if filled[i]:
					draw_circle(quests.segment_center(i), 30.0, Color(0.10, 0.50, 0.12, 0.9))
				else:
					draw_arc(quests.segment_center(i), 30.0, 0, TAU, 24, Color(1, 1, 1, 0.9), 8.0)
		"family_cedar":
			# 中心 5m の目印
			draw_arc(Vector2.ZERO, quests.FAMILY_CEDAR_RADIUS, 0, TAU, 48, Color(1.0, 0.95, 0.6, 0.9), 3.0)
