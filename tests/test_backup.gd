extends SceneTree

# セーブの控えのテスト。本物のセーブ・本物の控えには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_backup.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const GameWorld = preload("res://logic/GameWorld.gd")

const TEST_SAVE := "user://test_backup.json"
const TEST_DIR := "user://test_backups"
const REAL_DIR := "user://backups"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	var real_before := _real_backups()
	_clean()
	_test_backup()
	_test_broken_save()
	_test_keep()
	_test_off_by_default()
	_test_atomic_write()
	_test_restore_from_backup()
	_test_restore_skips_broken_backup()
	_test_no_backup()
	_test_restore_from_tmp()
	_test_missing_save_with_tmp()
	_test_stale_tmp()
	_test_truncated_real_like()
	_clean()
	_check(_real_backups() == real_before, "本物の控えのフォルダは変わっていない")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _list(dir: String) -> Array:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return []
	var list := Array(DirAccess.get_files_at(dir))
	list.sort()
	return list

func _real_backups() -> Array:
	return _list(REAL_DIR)

func _files() -> Array:
	return _list(TEST_DIR)

func _clean() -> void:
	for n in _files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR + "/" + n))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR))
	# テストのセーブ・書きかけ(.tmp)・読めなかったセーブ(.broken_…)を消す
	for n in _side_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + n))

# user:// にある、テストのセーブから派生したファイル
func _side_files() -> Array:
	var list := []
	for n in DirAccess.get_files_at("user://"):
		if n == "test_backup.json" or n.begins_with("test_backup.json.") or n.begins_with("test_backup.broken_"):
			list.append(n)
	list.sort()
	return list

func _broken_files() -> Array:
	return _side_files().filter(func(n): return n.begins_with("test_backup.broken_"))

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _world() -> GameWorld:
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.backup_dir = TEST_DIR
	return w

func _test_backup() -> void:
	print("控えを取る")
	var first := _world()
	first.load_game()
	_check(_files().is_empty(), "セーブがまだなければ控えはない")

	var original := JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": [], "market": {"money": 111}})
	_write(TEST_SAVE, original)
	var w := _world()
	w.load_game()
	var name := "kins_domain_save_%s.json" % w.forest.today()
	_check(_files() == [name], "読み込むと、今日の日付の控えができる")
	var backup := TEST_DIR + "/" + name
	_check(_read(backup) == original, "控えの中身は読み込んだときのセーブ")
	_check(w.market.money == 111, "読み込み自体はふつうに終わる")

	w.market.money = 222
	w.save_game()
	_check(_read(TEST_SAVE) != original and _read(backup) == original, "そのあと保存しても、控えは変わらない")
	var w2 := _world()
	w2.load_game()
	_check(_read(backup) == original and _files().size() == 1, "同じ日に開き直しても、朝の控えを上書きしない")

func _test_broken_save() -> void:
	print("壊れたセーブ")
	_clean()
	_write(TEST_SAVE, "{ こわれている")
	var w := _world()
	w.load_game()
	_check(_files().is_empty(), "読めないセーブは控えない")
	_check(w.load_notice != "", "読めなかったことを知らせる文がある")

func _test_keep() -> void:
	print("残す数")
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	for d in range(1, 11):
		_write("%s/kins_domain_save_2020-01-%02d.json" % [TEST_DIR, d], "{}")
	_write(TEST_DIR + "/other.txt", "keep")
	_write(TEST_SAVE, JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": []}))
	var w := _world()
	w.load_game()
	var today := "kins_domain_save_%s.json" % w.forest.today()
	var names := _files()
	print("    残った控え: ", names)
	_check(names.size() == 8 and names.has("other.txt"), "控えは 7 つまで(ほかのファイルは消さない)")
	_check(names.has(today), "今日の控えは残る")
	_check(not names.has("kins_domain_save_2020-01-04.json") and names.has("kins_domain_save_2020-01-05.json"), "古いものから消える")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR + "/other.txt"))

func _test_off_by_default() -> void:
	print("控えを取らない場合")
	_clean()
	_write(TEST_SAVE, JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": []}))
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	_check(w.backup_dir == "", "はじめは控えを取らない設定")
	w.load_game()
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TEST_DIR)), "テストのセーブでは控えができない")

func _save_text(money: int) -> String:
	return JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": [], "market": {"money": money}})

func _put_backup(date: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	_write("%s/kins_domain_save_%s.json" % [TEST_DIR, date], text)

func _test_atomic_write() -> void:
	print("別の名前で書いてから付け替える")
	_clean()
	var w := _world()
	w.market.money = 345
	w.save_game()
	_check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "保存したあと .tmp は残らない")
	var w2 := _world()
	w2.load_game()
	_check(w2.market.money == 345 and w2.load_notice == "", "保存した中身をそのまま読める")
	w2.market.money = 678
	w2.save_game()
	var w3 := _world()
	w3.load_game()
	_check(w3.market.money == 678, "上書きの保存も読める")

func _test_restore_from_backup() -> void:
	print("読めないセーブを控えから戻す")
	_clean()
	for d in range(1, 9):
		_put_backup("2020-01-%02d" % d, _save_text(1000 + d))
	var before := _files()
	_write(TEST_SAVE, "{ こわれている")
	var w := _world()
	w.load_game()
	_check(w.market.money == 1008, "いちばん新しい控え(1/8)の中身で始まる")
	_check(w.load_notice.contains("2020-01-08") and w.load_notice.contains("控えから戻した"), "どの控えから戻したかを知らせる: " + w.load_notice)
	var broken := _broken_files()
	_check(broken.size() == 1 and _read("user://" + broken[0]) == "{ こわれている", "読めなかったファイルは別名で中身のまま残る")
	_check(w.load_notice.contains(broken[0] if broken.size() > 0 else "?"), "残したファイルの名前を知らせる")
	_check(_read(TEST_SAVE) == _save_text(1008), "本物のセーブも控えの中身に戻る")
	_check(_files() == before, "読めなかった日は控えを取らず、古い控えも消さない(8 つのまま)")
	w.save_game()  # 開いた直後の日付の確認で保存される
	var w2 := _world()
	w2.load_game()
	_check(w2.market.money == 1008 and w2.load_notice == "", "次に開いたときは、戻した土地がふつうに読める")

func _test_restore_skips_broken_backup() -> void:
	print("いちばん新しい控えも読めない")
	_clean()
	_put_backup("2020-01-01", _save_text(501))
	_put_backup("2020-01-02", "{ これも")
	_write(TEST_SAVE, "")
	var w := _world()
	w.load_game()
	_check(w.market.money == 501 and w.load_notice.contains("2020-01-01"), "読める控えまでさかのぼる")

func _test_no_backup() -> void:
	print("戻せる控えがない")
	_clean()
	_write(TEST_SAVE, "[1, 2")
	var w := _world()
	w.load_game()
	_check(w.market.money == GameWorld.new().market.money, "新しいゲームで始まる")
	_check(w.load_notice.contains("新しく始めた"), "新しく始めたことを知らせる")
	_check(_broken_files().size() == 1, "読めなかったファイルは別名で残る")
	_clean()
	_write(TEST_SAVE, "{ こわれている")
	var nb := GameWorld.new()  # 控えを取らない設定(テスト用の確認セーブなど)
	nb.save_path = TEST_SAVE
	nb.load_game()
	_check(nb.load_notice.contains("新しく始めた") and _broken_files().size() == 1, "控えを取らない設定でも、読めなかったファイルは残して知らせる")

func _test_restore_from_tmp() -> void:
	print("書きかけの .tmp から戻す")
	_clean()
	_put_backup("2020-01-01", _save_text(1))
	_write(TEST_SAVE, "{ こわれている")
	_write(TEST_SAVE + ".tmp", _save_text(777))
	var w := _world()
	w.load_game()
	_check(w.market.money == 777, "読める .tmp があれば、控えより新しいのでそちらを使う")
	_check(w.load_notice.contains("書きかけの保存から戻した"), "知らせる: " + w.load_notice)
	_check(not FileAccess.file_exists(TEST_SAVE + ".tmp") and _read(TEST_SAVE) == _save_text(777), ".tmp は本物のセーブになる")

func _test_missing_save_with_tmp() -> void:
	print("付け替えの途中で落ちた(本物がなく .tmp だけある)")
	_clean()
	_write(TEST_SAVE + ".tmp", _save_text(888))
	var w := _world()
	w.load_game()
	_check(w.market.money == 888 and w.load_notice == "", ".tmp を黙って本物のセーブにする")
	_check(_read(TEST_SAVE) == _save_text(888) and not FileAccess.file_exists(TEST_SAVE + ".tmp"), ".tmp は本物の名前に付け替わる")
	_check(_files().size() == 1, "ふつうに読めた日として控えを取る")
	_clean()
	_write(TEST_SAVE + ".tmp", "{ 途中")
	var w2 := _world()
	w2.load_game()
	_check(w2.load_notice == "" and not FileAccess.file_exists(TEST_SAVE), "読めない .tmp だけなら、はじめて開いたのと同じ")

func _test_stale_tmp() -> void:
	print("ふつうのセーブと、古い .tmp")
	_clean()
	_write(TEST_SAVE, _save_text(10))
	_write(TEST_SAVE + ".tmp", "{ 途中")
	var w := _world()
	w.load_game()
	_check(w.market.money == 10 and w.load_notice == "", "本物のセーブを読む")
	_check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "残っていた .tmp は消える")

# レビュー(S1)の再現: ちゃんとしたセーブの前半だけが残った
func _test_truncated_real_like() -> void:
	print("途中で切れたセーブ")
	_clean()
	_write(TEST_SAVE, JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "market": {"money": 4321},
		"trees": [{"x": 1.0, "y": 2.0, "species": "birch", "planted_at": 1600000000}]}))
	var w := _world()
	w.load_game()
	w.save_game()  # ゲームが書く形のセーブにする
	var full := _read(TEST_SAVE)
	_put_backup("2020-01-01", full)
	_write(TEST_SAVE, full.substr(0, full.length() / 2))
	var w2 := _world()
	w2.load_game()
	_check(w2.market.money == 4321 and w2.forest.trees.size() == 1, "前半だけのセーブでも、控えの土地で始まる(新しいゲームで上書きしない)")
