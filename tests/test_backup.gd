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
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

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
