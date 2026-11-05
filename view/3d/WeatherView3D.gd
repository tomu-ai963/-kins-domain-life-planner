extends Node3D

# ── 雨と雪の 3D 表示 ─────────────────────────────────────
# 雨の日かどうかは logic/Forest.gd(日付で決まる)。冬は同じ日が雪になる。ここは読んで降らせるだけ。
# 粒はカメラが見ている場所のまわりにだけ出し、カメラの距離に合わせて全体を拡大する。
# これで、寄っても引いても画面の上では同じ密度・同じ太さに見える。
# 半透明なので奥行きを持たず、輪郭線は付かない(outline.gdshader)
const Forest = preload("res://logic/Forest.gd")
const WorldMaterial = preload("res://view/3d/WorldMaterial.gd")

const BASE_DIST := 28.0    # カメラがこの距離のとき、下の大きさ(m)がそのままになる
const AREA := 32.0          # 降らせる範囲(半分の幅)
const HEIGHT := 14.0        # 粒が出る高さ

const RAIN_SPEED := 24.0    # m/s
const RAIN_COUNT := 2500
const RAIN_SIZE := Vector2(0.05, 1.1)
const RAIN_COLOR := Color(0.78, 0.86, 1.0, 0.5)
const RIPPLE_COUNT := 450
const RIPPLE_SIZE := 0.8
const RIPPLE_SECONDS := 0.45
const RIPPLE_COLOR := Color(0.85, 0.92, 1.0, 0.55)
const SNOW_SPEED := 2.4
const SNOW_COUNT := 1400
const SNOW_SIZE := 0.24
const SNOW_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const NIGHT_DIM := 0.4      # 夜は粒も暗くする(光を受けない材質なので、そのままだと光って見える)

var forest: Forest
var player: Node3D
var day_light: Node
var _rain: GPUParticles3D
var _ripples: GPUParticles3D
var _snow: GPUParticles3D

func setup(f: Forest, p: Node3D, d: Node) -> void:
	forest = f
	player = p
	day_light = d
	_rain = _build_rain()
	_ripples = _build_ripples()
	_snow = _build_snow()
	forest.changed.connect(refresh)
	day_light.night_changed.connect(set_night)
	set_night(maxf(day_light.night, 0.0))
	refresh(true)

# 天気を読み直す。instant なら光もすぐ切り替える(開いたときは、最初から雨の光で始める)
func refresh(instant := false) -> void:
	var falling := forest.is_raining()
	var snowing := falling and forest.season == "winter"
	_set_emitting(_rain, falling and not snowing)
	_set_emitting(_ripples, falling and not snowing)
	_set_emitting(_snow, snowing)
	day_light.set_overcast(1.0 if falling else 0.0, instant)

func is_falling() -> bool:
	return _rain.emitting or _snow.emitting

func set_night(amount: float) -> void:
	var dim := lerpf(1.0, NIGHT_DIM, amount)
	for p in [_rain, _ripples, _snow]:
		var m = p.draw_pass_1.surface_get_material(0)
		var base: Color = m.get_meta("base_color")
		m.albedo_color = Color(base.r * dim, base.g * dim, base.b * dim, base.a)

func _process(_delta: float) -> void:
	if player == null:
		return
	global_position = Vector3(player.global_position.x, 0.0, player.global_position.z)
	scale = Vector3.ONE * player.view_distance() / BASE_DIST
	visible = not player.is_indoors()  # 小屋の中には降らない

func _set_emitting(p: GPUParticles3D, on: bool) -> void:
	if p.emitting != on:
		p.emitting = on

func _material(c: Color, texture: Texture2D, billboard: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.albedo_texture = texture
	m.billboard_mode = billboard
	m.billboard_keep_scale = true  # 全体の拡大を粒にも効かせる
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	m.set_meta("base_color", c)
	return m

func _particles(node_name: String, mesh: Mesh, count: int, seconds: float, y: float, process: ParticleProcessMaterial) -> GPUParticles3D:
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(AREA, 0.0, AREA)
	process.gravity = Vector3.ZERO
	var p := GPUParticles3D.new()
	p.name = node_name
	p.draw_pass_1 = mesh
	p.process_material = process
	p.amount = count
	p.lifetime = seconds
	p.preprocess = seconds  # 降りはじめの瞬間から画面全体に降っている
	p.local_coords = true   # カメラについて動く
	p.emitting = false
	p.position.y = y
	p.visibility_aabb = AABB(Vector3(-AREA * 1.2, -HEIGHT * 1.2, -AREA * 1.2), Vector3(AREA * 2.4, HEIGHT * 2.4, AREA * 2.4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

# 雨粒: 縦に細長い板。軸を立てたままカメラを向く
func _build_rain() -> GPUParticles3D:
	var mesh := QuadMesh.new()
	mesh.size = RAIN_SIZE
	mesh.material = _material(RAIN_COLOR, null, BaseMaterial3D.BILLBOARD_FIXED_Y)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.05, -1.0, 0.0)
	process.spread = 0.0
	process.initial_velocity_min = RAIN_SPEED
	process.initial_velocity_max = RAIN_SPEED
	return _particles("Rain", mesh, RAIN_COUNT, HEIGHT / RAIN_SPEED, HEIGHT, process)

# 地面に広がる波紋: 平らな輪が広がりながら消える
func _build_ripples() -> GPUParticles3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * RIPPLE_SIZE
	# 地面に貼りつくものなので、地面と同じように曲がる材質にする
	var m := WorldMaterial.new(RIPPLE_COLOR, true)
	m.albedo_texture = _ring_texture()
	m.vertex_color_use_as_albedo = true
	m.set_meta("base_color", RIPPLE_COLOR)
	mesh.material = m
	var process := ParticleProcessMaterial.new()
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	process.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	process.color_ramp = fade_tex
	return _particles("Ripples", mesh, RIPPLE_COUNT, RIPPLE_SECONDS, 0.05, process)

# 雪: 丸くぼかした板がゆっくり落ちる。向きを少しずつ散らして、ふらついて見せる
func _build_snow() -> GPUParticles3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * SNOW_SIZE
	mesh.material = _material(SNOW_COLOR, _soft_dot_texture(), BaseMaterial3D.BILLBOARD_ENABLED)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.12, -1.0, 0.04)
	process.spread = 9.0
	process.initial_velocity_min = SNOW_SPEED * 0.8
	process.initial_velocity_max = SNOW_SPEED * 1.2
	process.scale_min = 0.6
	process.scale_max = 1.2
	return _particles("Snow", mesh, SNOW_COUNT, HEIGHT / SNOW_SPEED, HEIGHT, process)

func _radial_texture(gradient: Gradient) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = gradient
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _ring_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.72, 0.84, 0.96])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return _radial_texture(g)

func _soft_dot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return _radial_texture(g)
