extends Node

# ── 音を鳴らす(3D だけ) ──────────────────────────────────────
# 音そのものは audio/(tools/make_sounds.gd で作る)。ここは場所・天気・作業に合わせて鳴らすだけで、ルールには関わらない。
# 流し続ける音: 風・葉(まわりの葉のある木の数で変わる)・雨・ストーブの火(小屋の中で仕込み中だけ)。
# 遠くの川(土地に川はない)はずっとは鳴らさず、ときどき聞こえてくる。
# 小屋の中では外の音を小さくする。足音は歩く場所(草・畑の土・小屋の床)で変わる。
# 音楽と、鳥・虫・生き物の声はまだない(2026-11-06 とむ: あとから)。
# **今は作業音だけを鳴らす**(2026-11-06 とむ: 自然音・足音・画面の音は一度止めて、音はあとから実装する)。
# 止めた音も作ってあるので、下の 3 つを true にすれば鳴る。直したい点は ROADMAP の「音の続き」
const AUDIO_DIR := "res://audio/"
const VOICES := 8            # 同時に鳴らせる短い音の数
const AMBIENT_SECONDS := 0.5 # 流し続ける音の強さを見直す間隔
const FADE_PER_SECOND := 0.5 # 流し続ける音の強さが変わる速さ
const STEP_SECONDS := 0.33   # 足音の間隔(歩きの振りに合わせた)
const LEAF_NEAR := 15.0      # この距離の木の葉の音が聞こえる(m)
const LEAF_FULL_TREES := 4.0 # この本数で葉の音がいちばん大きくなる
const INDOOR_OUTSIDE := 0.3  # 小屋の中で聞こえる外の音の割合
const BROOK_LEVEL := 0.08       # 遠くの川の大きさ
const BROOK_FADE_PER_SECOND := 0.02  # 川がゆっくり出入りする速さ(4 秒ほど)
const BROOK_ON_SECONDS := [15.0, 30.0]    # 川が聞こえている時間(最短と最長)
const BROOK_OFF_SECONDS := [60.0, 120.0]  # 川が聞こえない時間(最短と最長)

const LOOPS := ["wind", "leaves", "brook", "rain", "fire"]
# 短い音の音量(1 = そのまま)
const VOLUMES := {
	"water": 0.25, "dig": 0.35, "chop": 0.4, "build": 0.3, "pick": 0.3, "plant": 0.28, "pull": 0.3,
	"tree_fall": 0.45, "click": 0.15, "open": 0.18, "coin": 0.2,
	"step_grass": 0.14, "step_soil": 0.16, "step_wood": 0.22,
}
const ALIASES := {"pick_high": "pick", "prune": "pick", "feed": "plant", "shovel": "dig"}  # 作業の動きの名前 → 音の名前
const STEP_VARIANTS := 3
const UI_SOUNDS := ["click", "open", "coin"]

var ambient_enabled := false  # 風・葉・川・雨・火。set_ambient_enabled で切り替える
var steps_enabled := false    # 足音
var ui_enabled := false       # 画面の音

var world        # GameWorld
var _player: Node3D
var _loops := {}         # 音の名前 → {player, level, goal}
var _voices := []        # 短い音の AudioStreamPlayer
var _streams := {}       # 読み込んだ音
var _ambient_timer := 0.0
var _step_timer := 0.0
var brook_on := false    # 今、川が聞こえる番か
var _brook_timer := 0.0  # 川の番が変わるまでの時間
var last_played := ""    # 直前に鳴らした短い音(テスト用)
var last_surface := ""   # 直前の足音の場所(テスト用)

func setup(w, player: Node3D) -> void:
	world = w
	_player = player
	for sound in LOOPS:
		var stream: AudioStreamWAV = _stream(sound)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		var p := AudioStreamPlayer.new()
		p.name = "Loop_" + sound
		p.stream = stream
		p.volume_db = linear_to_db(0.001)
		add_child(p)
		_loops[sound] = {"player": p, "level": 0.0, "goal": 0.0}
	for i in range(VOICES):
		var v := AudioStreamPlayer.new()
		v.name = "Voice_%d" % i
		add_child(v)
		_voices.append(v)
	_brook_timer = randf_range(10.0, 30.0)  # はじめは静かで、少しすると聞こえてくる
	set_ambient_enabled(ambient_enabled)

# 流し続ける音を鳴らす / 止める
func set_ambient_enabled(on: bool) -> void:
	ambient_enabled = on
	for sound in _loops:
		var l: Dictionary = _loops[sound]
		if on:
			if not l.player.playing:
				l.player.play()
		else:
			l.player.stop()
			l.level = 0.0
			l.goal = 0.0
			l.player.volume_db = linear_to_db(0.001)
	update_ambient()

func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		_streams[sound] = load(AUDIO_DIR + sound + ".wav")
	return _streams[sound]

# 短い音を鳴らす。kind は音の名前か、作業の動きの名前
func play(kind: String) -> void:
	if world == null:
		return
	var sound: String = ALIASES.get(kind, kind)
	if not VOLUMES.has(sound) or (sound in UI_SOUNDS and not ui_enabled):
		return
	_play_file(sound, sound, randf_range(0.94, 1.06))

func _play_file(file: String, volume_key: String, pitch: float) -> void:
	var voice: AudioStreamPlayer = _free_voice()
	voice.stream = _stream(file)
	voice.volume_db = linear_to_db(float(VOLUMES[volume_key]))
	voice.pitch_scale = pitch
	voice.play()
	last_played = volume_key

func _free_voice() -> AudioStreamPlayer:
	for v in _voices:
		if not v.playing:
			return v
	return _voices[0]

# seconds 秒あとに鳴らす
func play_after(sound: String, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(play.bind(sound))

func _process(delta: float) -> void:
	if world == null:
		return
	if steps_enabled:
		_update_steps(delta)
	if not ambient_enabled:
		return
	_ambient_timer += delta
	if _ambient_timer >= AMBIENT_SECONDS:
		_ambient_timer = 0.0
		update_ambient()
	_update_brook(delta)
	for sound in _loops:
		var l: Dictionary = _loops[sound]
		var fade: float = BROOK_FADE_PER_SECOND if sound == "brook" else FADE_PER_SECOND
		l.level = move_toward(float(l.level), float(l.goal), fade * delta)
		l.player.volume_db = linear_to_db(maxf(float(l.level), 0.001))

# 川は、聞こえる番と聞こえない番を交代する
func _update_brook(delta: float) -> void:
	_brook_timer -= delta
	if _brook_timer > 0.0:
		return
	brook_on = not brook_on
	var range_seconds: Array = BROOK_ON_SECONDS if brook_on else BROOK_OFF_SECONDS
	_brook_timer = randf_range(range_seconds[0], range_seconds[1])
	update_ambient()

# 歩いているあいだ、足音を鳴らす
func _update_steps(delta: float) -> void:
	if not _player.is_walking():
		_step_timer = 0.0  # 歩きだしてすぐ鳴る
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = STEP_SECONDS
		last_surface = surface_at(_player.ground_pos())
		_play_file("%s_%d" % [last_surface, randi() % STEP_VARIANTS], last_surface, randf_range(0.92, 1.08))

# 足元の地面: 小屋の中は床、区画の上は土、ほかは草
func surface_at(pos: Vector2) -> String:
	if world.cabin.is_inside(pos):
		return "step_wood"
	if world.land.plot_at(pos) != null:
		return "step_soil"
	return "step_grass"

# まわりの、葉のある木の本数(冬の落葉樹は葉がないので数えない。苗木や種も数えない)
func leafy_trees_near(pos: Vector2) -> int:
	var f = world.forest
	var n := 0
	for t in f.trees:
		if t.pos.distance_to(pos) > LEAF_NEAR or not f.is_established(t):
			continue
		if f.season == "winter" and not f.SPECIES[t.species].evergreen:
			continue
		if f.radius_of(t) >= 0.5:
			n += 1
	return n

# 流し続ける音の強さを決める
func update_ambient() -> void:
	if not ambient_enabled:
		return
	var f = world.forest
	var pos: Vector2 = _player.ground_pos()
	var inside: bool = world.cabin.is_inside(pos)
	var outside: float = INDOOR_OUTSIDE if inside else 1.0
	var night: float = world.wildlife.darkness()
	var raining: bool = f.is_raining() and f.season != "winter"  # 雪は音がしない
	# 音量は小さめに(2026-11-06 とむの感想で下げた)
	_loops.wind.goal = (0.26 if f.season == "winter" else 0.16) * lerpf(1.0, 0.75, night) * outside
	_loops.leaves.goal = 0.24 * minf(1.0, leafy_trees_near(pos) / LEAF_FULL_TREES) * outside * (0.6 if raining else 1.0)
	_loops.brook.goal = BROOK_LEVEL * outside if brook_on else 0.0
	_loops.rain.goal = (0.3 if raining else 0.0) * outside
	var cooking: bool = world.kitchen.days_left() > 0
	_loops.fire.goal = 0.25 if inside and cooking else 0.0
