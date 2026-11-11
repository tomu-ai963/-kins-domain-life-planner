extends RefCounted

# ── 土地のある都道府県と気候(描画を持たない) ─────────────────────
# ゲームのはじめに 47 都道府県から 1 つ選ぶ(2026-11-11 とむ決定。あとから変えられない)。
# 太陽の位置(日の出・日の入り)は県庁所在地の緯度・経度で計算し、
# 季節の区切り・雪・霜・雨の多さは 8 つの気候区分(ZONES)で決める。
# どの木を植えられるかは、木の側(Forest.SPECIES の zones)に気候区分の一覧で持つ。植物を足すときは zones を書けばよい
# まだ選んでいない(pref = "")ときは、選ぶ前の今までのルール(LEGACY)。テストもこれで動く

# 季節: 月(1〜12)ごとの季節。添字 0 が 1 月
const SP := "spring"
const SU := "summer"
const AU := "autumn"
const WI := "winter"

# 気候区分。数字は代表の都市の平年値を目安にした仮の数字(気象庁の平年値 1991-2020 の目安)
#   name: 画面に出す名前 / months: 月ごとの季節
#   snow: 冬は雪が積もる・地面が凍る・池が凍る(雨の日は雪になる。雪かきができる)
#   frost: 冬に霜が降りる(霜に弱い野菜が枯れる)。南西諸島は降りない
#   rain: 日替わりの発見で雨(雪)になる重み(100 のうち。今までは 25)。降水 1mm 以上の日数の目安から
#   wind_seed: 風や鳥が運んでくる広葉樹の種 / nut_seed: リスや風が運んでくる針葉樹の種(日替わりの発見)
#   family: 「家族の木」のクエストで中心に植える木
const ZONES := {
	"hokkaido": {
		"name": "北海道", "months": [WI, WI, WI, SP, SP, SU, SU, SU, AU, AU, WI, WI],  # 札幌: 11 月に初雪、根雪は 12〜3 月
		"snow": true, "frost": true, "rain": 35, "wind_seed": "birch", "nut_seed": "ezomatsu", "family": "cedar",
	},
	"tohoku": {
		"name": "東北の太平洋側", "months": [WI, WI, WI, SP, SP, SU, SU, SU, AU, AU, AU, WI],  # 盛岡・仙台: 3 月まで霜と雪
		"snow": true, "frost": true, "rain": 28, "wind_seed": "birch", "nut_seed": "cedar", "family": "cedar",
	},
	"snowy": {
		"name": "日本海側", "months": [WI, WI, WI, SP, SP, SU, SU, SU, AU, AU, AU, WI],  # 秋田・新潟・金沢: 冬は雪の日が多い
		"snow": true, "frost": true, "rain": 40, "wind_seed": "birch", "nut_seed": "cedar", "family": "cedar",
	},
	"highland": {
		"name": "中央高地", "months": [WI, WI, WI, SP, SP, SU, SU, SU, AU, AU, AU, WI],  # 長野・甲府: 冬は冷えて地面が凍る。雨は少ない
		"snow": true, "frost": true, "rain": 22, "wind_seed": "birch", "nut_seed": "cedar", "family": "cedar",
	},
	"pacific": {
		"name": "太平洋側", "months": [WI, WI, SP, SP, SP, SU, SU, SU, AU, AU, AU, WI],  # 東京・名古屋: 冬は晴れて乾く。雪はまれ
		"snow": false, "frost": true, "rain": 25, "wind_seed": "konara", "nut_seed": "sugi", "family": "sugi",
	},
	"setouchi": {
		"name": "瀬戸内・近畿", "months": [WI, WI, SP, SP, SP, SU, SU, SU, AU, AU, AU, WI],  # 大阪・岡山・高松: 一年を通して雨が少ない
		"snow": false, "frost": true, "rain": 20, "wind_seed": "konara", "nut_seed": "sugi", "family": "sugi",
	},
	"south": {
		"name": "九州・四国の南", "months": [WI, WI, SP, SP, SP, SU, SU, SU, SU, AU, AU, WI],  # 福岡・鹿児島・高知: 夏が長く雨が多い
		"snow": false, "frost": true, "rain": 30, "wind_seed": "konara", "nut_seed": "sugi", "family": "sugi",
	},
	"nansei": {
		"name": "南西諸島", "months": [WI, WI, SP, SP, SU, SU, SU, SU, SU, SU, AU, WI],  # 那覇: 霜も雪もない。冬も野菜が育つ
		"snow": false, "frost": false, "rain": 32, "wind_seed": "gajumaru", "nut_seed": "ryukyu_pine", "family": "gajumaru",
	},
}
# まだ選んでいないとき(今までのルール): 12〜2 月が冬で雪が積もる。木はどれでも植えられる
const LEGACY := {
	"name": "", "months": [WI, WI, SP, SP, SP, SU, SU, SU, AU, AU, AU, WI],
	"snow": true, "frost": true, "rain": 25, "wind_seed": "birch", "nut_seed": "cedar", "family": "cedar",
}
const LEGACY_LAT := 35.0   # 日本のまんなかあたり(今までの DayClock の値)
const LEGACY_LON := 137.0

# 地方(選ぶ画面の 1 段目)。北から順
const AREAS := [
	{"name": "北海道", "prefs": ["hokkaido"]},
	{"name": "東北", "prefs": ["aomori", "iwate", "miyagi", "akita", "yamagata", "fukushima"]},
	{"name": "関東", "prefs": ["ibaraki", "tochigi", "gunma", "saitama", "chiba", "tokyo", "kanagawa"]},
	{"name": "中部", "prefs": ["niigata", "toyama", "ishikawa", "fukui", "yamanashi", "nagano", "gifu", "shizuoka", "aichi"]},
	{"name": "近畿", "prefs": ["mie", "shiga", "kyoto", "osaka", "hyogo", "nara", "wakayama"]},
	{"name": "中国", "prefs": ["tottori", "shimane", "okayama", "hiroshima", "yamaguchi"]},
	{"name": "四国", "prefs": ["tokushima", "kagawa", "ehime", "kochi"]},
	{"name": "九州・沖縄", "prefs": ["fukuoka", "saga", "nagasaki", "kumamoto", "oita", "miyazaki", "kagoshima", "okinawa"]},
]

# 都道府県: name / lat・lon: 県庁所在地の緯度・経度(度) / zone: 気候区分(県庁所在地の気候で決めた)
const PREFS := {
	"hokkaido": {"name": "北海道", "lat": 43.06, "lon": 141.35, "zone": "hokkaido"},
	"aomori": {"name": "青森県", "lat": 40.82, "lon": 140.74, "zone": "snowy"},
	"iwate": {"name": "岩手県", "lat": 39.70, "lon": 141.15, "zone": "tohoku"},
	"miyagi": {"name": "宮城県", "lat": 38.27, "lon": 140.87, "zone": "tohoku"},
	"akita": {"name": "秋田県", "lat": 39.72, "lon": 140.10, "zone": "snowy"},
	"yamagata": {"name": "山形県", "lat": 38.24, "lon": 140.36, "zone": "snowy"},
	"fukushima": {"name": "福島県", "lat": 37.75, "lon": 140.47, "zone": "tohoku"},
	"ibaraki": {"name": "茨城県", "lat": 36.34, "lon": 140.45, "zone": "pacific"},
	"tochigi": {"name": "栃木県", "lat": 36.57, "lon": 139.88, "zone": "pacific"},
	"gunma": {"name": "群馬県", "lat": 36.39, "lon": 139.06, "zone": "pacific"},
	"saitama": {"name": "埼玉県", "lat": 35.86, "lon": 139.65, "zone": "pacific"},
	"chiba": {"name": "千葉県", "lat": 35.61, "lon": 140.12, "zone": "pacific"},
	"tokyo": {"name": "東京都", "lat": 35.69, "lon": 139.69, "zone": "pacific"},
	"kanagawa": {"name": "神奈川県", "lat": 35.45, "lon": 139.64, "zone": "pacific"},
	"niigata": {"name": "新潟県", "lat": 37.90, "lon": 139.02, "zone": "snowy"},
	"toyama": {"name": "富山県", "lat": 36.70, "lon": 137.21, "zone": "snowy"},
	"ishikawa": {"name": "石川県", "lat": 36.59, "lon": 136.63, "zone": "snowy"},
	"fukui": {"name": "福井県", "lat": 36.07, "lon": 136.22, "zone": "snowy"},
	"yamanashi": {"name": "山梨県", "lat": 35.66, "lon": 138.57, "zone": "highland"},
	"nagano": {"name": "長野県", "lat": 36.65, "lon": 138.18, "zone": "highland"},
	"gifu": {"name": "岐阜県", "lat": 35.39, "lon": 136.72, "zone": "pacific"},
	"shizuoka": {"name": "静岡県", "lat": 34.98, "lon": 138.38, "zone": "pacific"},
	"aichi": {"name": "愛知県", "lat": 35.18, "lon": 136.91, "zone": "pacific"},
	"mie": {"name": "三重県", "lat": 34.73, "lon": 136.51, "zone": "pacific"},
	"shiga": {"name": "滋賀県", "lat": 35.00, "lon": 135.87, "zone": "setouchi"},
	"kyoto": {"name": "京都府", "lat": 35.02, "lon": 135.76, "zone": "setouchi"},
	"osaka": {"name": "大阪府", "lat": 34.69, "lon": 135.52, "zone": "setouchi"},
	"hyogo": {"name": "兵庫県", "lat": 34.69, "lon": 135.18, "zone": "setouchi"},
	"nara": {"name": "奈良県", "lat": 34.69, "lon": 135.83, "zone": "setouchi"},
	"wakayama": {"name": "和歌山県", "lat": 34.23, "lon": 135.17, "zone": "setouchi"},
	"tottori": {"name": "鳥取県", "lat": 35.50, "lon": 134.24, "zone": "snowy"},
	"shimane": {"name": "島根県", "lat": 35.47, "lon": 133.05, "zone": "snowy"},
	"okayama": {"name": "岡山県", "lat": 34.66, "lon": 133.93, "zone": "setouchi"},
	"hiroshima": {"name": "広島県", "lat": 34.40, "lon": 132.46, "zone": "setouchi"},
	"yamaguchi": {"name": "山口県", "lat": 34.19, "lon": 131.47, "zone": "setouchi"},
	"tokushima": {"name": "徳島県", "lat": 34.07, "lon": 134.56, "zone": "setouchi"},
	"kagawa": {"name": "香川県", "lat": 34.34, "lon": 134.04, "zone": "setouchi"},
	"ehime": {"name": "愛媛県", "lat": 33.84, "lon": 132.77, "zone": "setouchi"},
	"kochi": {"name": "高知県", "lat": 33.56, "lon": 133.53, "zone": "south"},
	"fukuoka": {"name": "福岡県", "lat": 33.61, "lon": 130.42, "zone": "south"},
	"saga": {"name": "佐賀県", "lat": 33.25, "lon": 130.30, "zone": "south"},
	"nagasaki": {"name": "長崎県", "lat": 32.74, "lon": 129.87, "zone": "south"},
	"kumamoto": {"name": "熊本県", "lat": 32.79, "lon": 130.74, "zone": "south"},
	"oita": {"name": "大分県", "lat": 33.24, "lon": 131.61, "zone": "south"},
	"miyazaki": {"name": "宮崎県", "lat": 31.91, "lon": 131.42, "zone": "south"},
	"kagoshima": {"name": "鹿児島県", "lat": 31.56, "lon": 130.56, "zone": "south"},
	"okinawa": {"name": "沖縄県", "lat": 26.21, "lon": 127.68, "zone": "nansei"},
}

var pref := ""  # 選んだ都道府県の id。"" = まだ選んでいない

func is_chosen() -> bool:
	return pref != ""

# 都道府県を決める。知らない id なら false(決めない)。一度決めたら変えない
func choose(id: String) -> bool:
	if is_chosen() or not PREFS.has(id):
		return false
	pref = id
	return true

func zone_id() -> String:
	return str(PREFS[pref].zone) if is_chosen() else ""

func zone() -> Dictionary:
	return ZONES[zone_id()] if is_chosen() else LEGACY

func pref_name() -> String:
	return str(PREFS[pref].name) if is_chosen() else ""

func latitude() -> float:
	return float(PREFS[pref].lat) if is_chosen() else LEGACY_LAT

func longitude() -> float:
	return float(PREFS[pref].lon) if is_chosen() else LEGACY_LON

# ── 季節 ──
func season_of_month(m: int) -> String:
	return zone().months[clampi(m, 1, 12) - 1]

func season_of_date(date: String) -> String:
	return season_of_month(int(date.substr(5, 2)))

# 冬に雪が積もり、地面と池が凍るか
func has_snow() -> bool:
	return bool(zone().snow)

# 冬に霜が降りるか(霜に弱い野菜が枯れる)
func has_frost() -> bool:
	return bool(zone().frost)

# その月は霜が降りるか(霜のある土地の冬の月)
func is_frost_month(m: int) -> bool:
	return has_frost() and season_of_month(m) == WI

# その月は雪が積もっているか(雪の降る土地の冬の月)
func is_snow_month(m: int) -> bool:
	return has_snow() and season_of_month(m) == WI

func rain_weight() -> int:
	return int(zone().rain)

# 冬の最初の月(霜や雪がはじまる月)
func winter_start_month() -> int:
	var months: Array = zone().months
	for m in range(1, 13):
		if months[m - 1] == WI and months[(m + 10) % 12] != WI:  # 前の月が冬でない
			return m
	return 12

# 冬が終わって最初の月(春の種の注文が届く月)
func winter_end_month() -> int:
	var months: Array = zone().months
	for m in range(1, 13):
		if months[m - 1] != WI and months[(m + 10) % 12] == WI:
			return m
	return 3

# ── 植物 ──
# その植物(Forest.SPECIES や Garden.CROPS の 1 つ)をこの土地で育てられるか。
# zones がない植物はどこでも育つ。まだ選んでいないときは、どれでも育つ(今までのルール)
func allows(plant: Dictionary) -> bool:
	if not is_chosen() or not plant.has("zones"):
		return true
	return zone_id() in plant.zones

# 野菜をその季節にまけるか。霜の降りない土地では、春か秋にまける野菜を冬にもまける(沖縄は冬が野菜の季節)
func can_sow(crop: Dictionary, season: String) -> bool:
	if not allows(crop):
		return false
	if season in crop.seasons:
		return true
	return season == WI and not has_frost() and (SP in crop.seasons or AU in crop.seasons)

func wind_seed() -> String:
	return str(zone().wind_seed)

func nut_seed() -> String:
	return str(zone().nut_seed)

func family_tree() -> String:
	return str(zone().family)

# ── セーブ用 ──
func to_save() -> String:
	return pref

func from_save(v) -> void:
	pref = str(v) if typeof(v) == TYPE_STRING and PREFS.has(v) else ""
