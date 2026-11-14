extends RefCounted

# ── 道具: ジョウロ・斧・ガソリンで動く機械(描画を持たない) ─────────────
# 2026-11-11 とむ決定:
# - ジョウロははじめ 5L(1 杯で 5 か所)。10L のジョウロ(10 か所)を市場で安く買える。空になったら井戸か池のそばで汲む
# - 斧で伐れるのは 1 日 3 本。チェーンソーなら何本でも
# - エンジンポンプ・チェーンソー・薪割り機は市場で買い、燃料のガソリンも市場で買う(使うと減る)
# ガソリンは 0.1L を 1 として整数で持つ。文言は Main、見た目は view/ が決める
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const CAN_SMALL := 5     # はじめのジョウロ(L)。1L で 1 か所(区画 1 つか木 1 本)
const CAN_BIG := 10      # 市場で買える大きいジョウロ(L)
const AXE_PER_DAY := 3   # 斧で伐れる木の数(1 日)
const MAX_GAS := 200     # 持てるガソリン(0.1L 単位。20L の携行缶 1 つ)
# 1 回に使うガソリン(0.1L 単位。仮の数字): ポンプ 1 回 0.5L・チェーンソー 1 本 0.2L・薪割り機 1 回 0.5L
# 製粉機 1 回 0.5L(2026-11-14 穀物と粉で足した)
const GAS_USE := {"pump": 5, "chainsaw": 2, "splitter": 5, "mill": 5}
const MACHINES := ["pump", "chainsaw", "splitter", "mill"]
const ITEMS := ["big_can", "pump", "chainsaw", "splitter", "quern", "mill"]  # 市場で買う道具(ひとつずつ)。quern = 石臼

var forest: Forest  # GameWorld が設定する

var can_water := CAN_SMALL  # ジョウロに入っている水(L)
var owned := []             # 買った道具(ITEMS の id)
var gas := 0                # ガソリン(0.1L 単位)
var axe_day := ""           # 斧で伐った日(YYYY-MM-DD)
var axe_count := 0          # その日に斧で伐った本数
var last_machine := ""      # 直前の作業で使った機械(文言と動き用・保存しない)

func _commit() -> void:
	dirty.emit()
	changed.emit()

func has(id: String) -> bool:
	return id in owned

func has_machine() -> bool:
	return MACHINES.any(func(m): return has(m))

# ── ジョウロ ─────────────────────────────────────────────
func can_size() -> int:
	return CAN_BIG if has("big_can") else CAN_SMALL

func can_full() -> bool:
	return can_water >= can_size()

# 井戸か池で満杯まで汲む。汲んだ量(L)を返す
func fill_can() -> int:
	var n: int = can_size() - can_water
	if n <= 0:
		return 0
	can_water = can_size()
	_commit()
	return n

# 1 か所ぶん(1L)注ぐ。空なら false
func pour() -> bool:
	if can_water <= 0:
		return false
	can_water -= 1
	_commit()
	return true

# ── 斧 ─────────────────────────────────────────────────
# 今日あと何本、斧で伐れるか
func axe_left() -> int:
	if axe_day != forest.today():
		return AXE_PER_DAY
	return maxi(0, AXE_PER_DAY - axe_count)

# 木を 1 本伐る道具を決めて使う。結果: chainsaw / axe / tired(斧は今日はもう振れない)
# チェーンソーがあってガソリンが足りれば、チェーンソー。なければ斧
func use_cutter() -> String:
	if use_gas("chainsaw"):
		return "chainsaw"
	if axe_left() <= 0:
		return "tired"
	if axe_day != forest.today():
		axe_day = forest.today()
		axe_count = 0
	axe_count += 1
	last_machine = ""
	_commit()
	return "axe"

# ── ガソリンで動く機械 ─────────────────────────────────────
func gas_needed(machine: String) -> int:
	return int(GAS_USE[machine])

# その機械を今動かせるか(持っていて、ガソリンが足りる)
func can_run(machine: String) -> bool:
	return has(machine) and gas >= gas_needed(machine)

# その機械を 1 回動かす(ガソリンを使う)。動かせなければ false
func use_gas(machine: String) -> bool:
	if not can_run(machine):
		return false
	gas -= gas_needed(machine)
	last_machine = machine
	_commit()
	return true

# 市場で買ったものを受け取る。結果: bought / owned(道具はひとつずつ) / full(ガソリンはもう入らない) / unknown
func receive(id: String, amount := 0) -> String:
	if id == "gasoline":
		if gas + amount > MAX_GAS:
			return "full"
		gas += amount
		_commit()
		return "bought"
	if not (id in ITEMS):
		return "unknown"
	if has(id):
		return "owned"
	owned.append(id)
	if id == "big_can":
		can_water = CAN_BIG  # 買ったときは満杯(店の水で)
	_commit()
	return "bought"

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"can_water": can_water, "owned": owned, "gas": gas, "axe_day": axe_day, "axe_count": axe_count}

# 道具の記録がないセーブ(2026-11-14 より前)は、5L のジョウロが満杯・機械なし・ガソリンなしから
func from_save(d: Dictionary) -> void:
	owned = SaveRead.ids(d.get("owned"), ITEMS)
	can_water = clampi(SaveRead.whole(d, "can_water", can_size()), 0, can_size())
	gas = clampi(SaveRead.whole(d, "gas"), 0, MAX_GAS)
	axe_day = SaveRead.text(d, "axe_day")
	axe_count = clampi(SaveRead.whole(d, "axe_count"), 0, AXE_PER_DAY)
	changed.emit()
