shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

// 画面全体の輪郭線。カメラの前に置いた板(Player3D.tscn の Outline)で描く。
// 奥行きの差(物の外周)と、面の向きの差(箱の角など)が大きいところに線を引く。形や材質ごとの設定は要らない。
// 半透明のもの(水面・冬の樹冠など)は奥行きを持たないので、線は付かない

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;
uniform vec3 line_color : source_color = vec3(0.13, 0.09, 0.07);
uniform float line_alpha = 0.7;
uniform float thickness = 1.0;          // 線の太さ(画素)
uniform float depth_threshold = 0.012;  // 奥行きの差(今の距離に対する割合)。地面の傾きで線が出ない大きさ
uniform float normal_threshold = 0.5;   // 面の向きの差(1 - 内積)

float view_depth(vec2 uv, mat4 inv_projection) {
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, texture(depth_texture, uv).r, 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_texture, uv).xyz * 2.0 - 1.0;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 step_uv = thickness / VIEWPORT_SIZE;
	vec2 a = SCREEN_UV + step_uv * vec2(-1.0, -1.0);
	vec2 b = SCREEN_UV + step_uv * vec2(1.0, 1.0);
	vec2 c = SCREEN_UV + step_uv * vec2(1.0, -1.0);
	vec2 d = SCREEN_UV + step_uv * vec2(-1.0, 1.0);

	float da = view_depth(a, INV_PROJECTION_MATRIX);
	float db = view_depth(b, INV_PROJECTION_MATRIX);
	float dc = view_depth(c, INV_PROJECTION_MATRIX);
	float dd = view_depth(d, INV_PROJECTION_MATRIX);
	float nearest = min(min(da, db), min(dc, dd));
	// 自分より手前のものが隣にあるときだけ線にする。線は物の外側に付くので、細い幹の色をつぶさない
	float depth_edge = (view_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - nearest) / nearest;

	float normal_edge = max(
		1.0 - dot(view_normal(a), view_normal(b)),
		1.0 - dot(view_normal(c), view_normal(d)));

	float edge = max(step(depth_threshold, depth_edge), step(normal_threshold, normal_edge));
	ALBEDO = line_color;
	ALPHA = edge * line_alpha;
}
