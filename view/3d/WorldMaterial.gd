extends ShaderMaterial

# ── 3D の共通の材質: トゥーン + 奥へ丸く曲がる世界 ───────────────────────
# カメラが見ている場所から離れるほど、頂点を下へ下げて描く。地面も木も小屋も同じように曲がる。
# 曲がるのは見た目だけで、ロジックの座標・当たり判定・影の計算のもとになる法線はそのまま平らな世界のまま。
# 法線を変えないので、地面の光と影の塗り分けは曲がっても変わらない。
# 曲げる中心は全シェーダー共通の値 bend_center(project.godot の shader_globals)で、Player3D が毎フレーム渡す。
# StandardMaterial3D と同じ名前の項目を持たせて、view 側は今までどおりに書ける
const BEND_Z := 0.0035  # 南北(画面の奥行き)の曲がり。中心から d m 離れると d² × これだけ下がる
const BEND_X := 0.0015  # 東西の曲がり
const TOON_SOFTNESS := 0.1  # 光と影の境目のぼかし(トゥーンでは roughness がこの幅になる。小さいほどくっきり)

# 透明かどうか・光を受けるかどうかで 4 通りのシェーダーを使い回す
static var _shaders := {}

var unshaded := false
var albedo_color := Color.WHITE:
	set(c):
		albedo_color = c
		set_shader_parameter("albedo", c)
		_pick_shader()
var albedo_texture: Texture2D:
	set(t):
		albedo_texture = t
		set_shader_parameter("albedo_tex", t)
var vertex_color_use_as_albedo := false:
	set(on):
		vertex_color_use_as_albedo = on
		set_shader_parameter("use_vertex_color", on)
var emission_enabled := false:
	set(on):
		emission_enabled = on
		set_shader_parameter("emission_on", on)
var emission := Color.BLACK:
	set(c):
		emission = c
		set_shader_parameter("emission_color", c)
var emission_energy_multiplier := 1.0:
	set(e):
		emission_energy_multiplier = e
		set_shader_parameter("emission_energy", e)

func _init(c := Color.WHITE, is_unshaded := false) -> void:
	unshaded = is_unshaded
	albedo_color = c
	emission_energy_multiplier = 1.0

# 平らな世界で (dx, dz) 離れた場所が、どれだけ下に描かれるか(m)
static func drop(dx: float, dz: float) -> float:
	return BEND_Z * dz * dz + BEND_X * dx * dx

func _pick_shader() -> void:
	var alpha := albedo_color.a < 1.0
	var key := "%s_%s" % [alpha, unshaded]
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = _code(alpha, unshaded)
		_shaders[key] = s
	if shader != _shaders[key]:
		shader = _shaders[key]

static func _code(alpha: bool, is_unshaded: bool) -> String:
	var modes := "world_vertex_coords, " + ("unshaded" if is_unshaded else "diffuse_toon, specular_disabled")
	return """shader_type spatial;
render_mode %s;

global uniform vec3 bend_center;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_vertex_color = false;
uniform bool emission_on = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;

void vertex() {
	vec2 d = VERTEX.xz - bend_center.xz;
	VERTEX.y -= %f * d.y * d.y + %f * d.x * d.x;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec4 tint = use_vertex_color ? COLOR : vec4(1.0);
	ALBEDO = albedo.rgb * tex.rgb * tint.rgb;
	ROUGHNESS = %f;
	if (emission_on) {
		EMISSION = emission_color * emission_energy;
	}
	%s
}
""" % [modes, BEND_Z, BEND_X, TOON_SOFTNESS, "ALPHA = albedo.a * tex.a * tint.a;" if alpha else ""]
