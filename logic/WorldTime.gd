extends RefCounted

# ── ゲームの「今」(描画を持たない) ───────────────────────────────
# 今日の日付と今の時刻は、ここからだけ読む(Forest・GameWorld・DayClock が使う。2026-11-11。レビュー C1)。
# ふだんは現実の時計そのまま。テストと検証では shift_days で日付を進めたり戻したりして、何日も遊んだ様子を確かめられる。
# ずらした量は保存しない(ゲームでは使わない)
const DAY := 86400

var offset_seconds := 0  # 現実の時計からずらす秒数(テストと検証用)

# 今の UNIX 時刻(UTC の秒)。木を植えた時刻などに使う
func now_unix() -> int:
	return int(Time.get_unix_time_from_system()) + offset_seconds

# 今の現地時刻の {year, month, day, hour, minute, second}
func now_local() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(now_unix() + _bias_seconds())

# 今日の現地の日付(YYYY-MM-DD)
func today() -> String:
	return Time.get_date_string_from_unix_time(now_unix() + _bias_seconds())

func month() -> int:
	return int(now_local().month)

# 日付を days 日ずらす(マイナスで戻す)。テストと検証用
func shift_days(days: int) -> void:
	offset_seconds += days * DAY

# 今日が date(YYYY-MM-DD)になるようにずらす。時刻は今のまま。テストと検証用
func set_today(date: String) -> void:
	var now_day: int = int(Time.get_unix_time_from_datetime_string(today()) / float(DAY))
	var goal_day: int = int(Time.get_unix_time_from_datetime_string(date) / float(DAY))
	shift_days(goal_day - now_day)

func is_shifted() -> bool:
	return offset_seconds != 0

# 現地時刻と UTC の差(秒)
static func _bias_seconds() -> int:
	return int(Time.get_time_zone_from_system().bias) * 60
