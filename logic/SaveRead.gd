extends RefCounted

# ── セーブの値を 1 つずつ確かめて読む(2026-11-11。レビュー S3) ───────────
# 前は、木 1 本に x がないだけで読み込みが止まり、その種類が全部消えて、そのまま保存されていた。
# ここの関数は、形や型がおかしい値を決まった値に置き換えるか、null を返す(呼ぶ側がその 1 件だけ飛ばす)。
# 手で書き換えたセーブや、将来の版との違いに備える

# 数として読める値か(数のほか、"12.5" のような数の文字も読む)
static func is_num(v) -> bool:
	match typeof(v):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v).is_valid_float()
	return false

# d[key] を小数で。読めなければ fallback
static func num(d: Dictionary, key: String, fallback := 0.0) -> float:
	var v = d.get(key)
	return float(v) if is_num(v) else fallback

# d[key] を整数で。読めなければ fallback
static func whole(d: Dictionary, key: String, fallback := 0) -> int:
	var v = d.get(key)
	return int(float(v)) if is_num(v) else fallback

# 持ち物などの数(マイナスにしない)
static func count(d: Dictionary, key: String) -> int:
	return maxi(0, whole(d, key, 0))

# d[key] を文字で。文字でなければ fallback
static func text(d: Dictionary, key: String, fallback := "") -> String:
	var v = d.get(key)
	return String(v) if typeof(v) in [TYPE_STRING, TYPE_STRING_NAME] else fallback

# d[key] を真偽で。読めなければ fallback
static func flag(d: Dictionary, key: String, fallback := false) -> bool:
	var v = d.get(key)
	if typeof(v) == TYPE_BOOL:
		return v
	return float(v) != 0.0 if is_num(v) else fallback

# {x, y} の位置。読めなければ null
static func point(d: Dictionary):
	if not is_num(d.get("x")) or not is_num(d.get("y")):
		return null
	return Vector2(float(d.x), float(d.y))

# [x, y] の位置。読めなければ null
static func pair(v):
	if typeof(v) != TYPE_ARRAY or v.size() != 2 or not is_num(v[0]) or not is_num(v[1]):
		return null
	return Vector2(float(v[0]), float(v[1]))

static func dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func list(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []

# 文字の id の並び(allowed に入っているものだけ。重なりは 1 つに)
static func ids(v, allowed) -> Array:
	var out := []
	for id in list(v):
		if typeof(id) in [TYPE_STRING, TYPE_STRING_NAME] and String(id) in allowed and not (String(id) in out):
			out.append(String(id))
	return out
