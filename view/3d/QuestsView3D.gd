extends Node3D

# ── 段階クエストの 3D 表示(いまの段階の目印と、完成の演出) ─────────────
# 状態とルールは logic/Quests.gd(座標は m)。生垣の印は木の増減でも変わるので、木と土地の変化でも作り直す
const Quests = preload("res://logic/Quests.gd")
const Look = preload("res://view/3d/Look.gd")

const MARK_R := 1.0  # 生垣の区画の印の半径(m)

var quests: Quests
var _done_mat := Look.mat(Color(0.10, 0.50, 0.12), true)
var _todo_mat := Look.mat(Color(1, 1, 1, 0.95), true)
var _stake_mat := Look.mat(Color(0.95, 0.95, 0.92))
var _guide_mat := Look.mat(Color(1.0, 0.95, 0.6, 0.9), true)
var _glow := 0.0
var _rings := []  # 完成の光の輪(ゆっくり明滅させる)

func setup(q: Quests) -> void:
	quests = q
	quests.changed.connect(_rebuild)
	quests.forest.changed.connect(_rebuild)
	quests.land.changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	if _rings.is_empty():
		return
	_glow += delta
	for i in range(_rings.size()):
		var m = _rings[i].material_override
		m.emission_energy_multiplier = 0.6 + 0.4 * sin(_glow * 1.2 - i * 0.6)

func _rebuild() -> void:
	Look.clear_children(self)
	_rings.clear()
	var half: float = quests.HALF
	if quests.is_complete():
		# 愛の空間: 中心(家族の杉)から光の輪が広がり、境界が金色に縁取られる
		for k in range(1, 6):
			var ring := Look.ring(Vector2.ZERO, 7.5 * k, 0.5, Look.mat(Color(1.0, 0.90, 0.50, 0.75 - 0.1 * k), true, 1.0), 0.08)
			_rings.append(ring)
			add_child(ring)
		var gold := Look.mat(Color(1.0, 0.78, 0.10), false, 0.8)
		var c := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
		for i in range(4):
			add_child(Look.strip(c[i], c[(i + 1) % 4], 0.6, 0.04, gold))
		return
	# まだのクエストの印をどれも出す(どれからでも達成できる)
	for id in quests.remaining():
		match id:
			"hedge":
				# 40 区画の印: 埋まった区画は緑の丸、まだの区画は白い輪と杭(引いても見えるように)
				var filled: Array = quests.hedge_filled()
				for i in range(quests.HEDGE_SEGMENTS):
					var p: Vector2 = quests.segment_center(i)
					if filled[i]:
						var disc := CylinderMesh.new()
						disc.top_radius = MARK_R
						disc.bottom_radius = MARK_R
						disc.height = 0.04
						disc.radial_segments = 24
						add_child(Look.mesh_node(disc, _done_mat, Look.at(p, 0.03)))
					else:
						add_child(Look.ring(p, MARK_R, 0.2, _todo_mat))
						var stake := CylinderMesh.new()
						stake.top_radius = 0.06
						stake.bottom_radius = 0.08
						stake.height = 1.2
						stake.radial_segments = 6
						add_child(Look.mesh_node(stake, _stake_mat, Look.at(p, 0.6)))
			"family_cedar":
				# 中心 5m の目印
				add_child(Look.ring(Vector2.ZERO, quests.FAMILY_CEDAR_RADIUS, 0.15, _guide_mat))
