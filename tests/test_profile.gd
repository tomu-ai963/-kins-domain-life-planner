extends SceneTree

# 自分の名前と性別(決める・付け直す・セーブ・決める画面)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_profile.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const GameWorld = preload("res://logic/GameWorld.gd")
const Profile = preload("res://logic/Profile.gd")
const ProfilePicker = preload("res://view/ProfilePicker.gd")

const TEST_SAVE := "user://test_profile.json"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_choose()
	_test_rename()
	_test_save()
	_test_picker()
	_remove_save()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _world() -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	return w

func _test_choose() -> void:
	print("自分の名前と性別を決める")
	var w := _world()
	var p := w.profile
	_check(not p.chosen and p.name == "" and p.sex == "", "決める前は名前も性別もない")
	_check(w.choose_profile("   ", "f") == "empty" and not p.chosen, "名前が空なら決められない")
	_check(w.choose_profile("あいうえおかきくけ", "f") == "too_long", "%d 文字をこえる名前は決められない" % Profile.NAME_MAX)
	_check(w.choose_profile("とむ", "x") == "unknown", "性別は 男性・女性・決めない のどれか")
	_check(w.choose_profile(" とむ\n", "f") == "chosen", "名前と性別を決める")
	_check(p.chosen and p.name == "とむ" and p.sex == "f", "前後の空白と改行は取る(とむ・女性)")
	_check(p.parent_word() == "お母さん", "女性なら子どもは「お母さん」と呼ぶ")
	_check(w.choose_profile("べつ", "m") == "already" and p.name == "とむ" and p.sex == "f", "あとから決め直せない")
	var w2 := _world()
	w2.choose_profile("たろう", "m")
	_check(w2.profile.parent_word() == "お父さん", "男性なら「お父さん」")
	var w3 := _world()
	_check(w3.choose_profile("みずき", "") == "chosen" and w3.profile.sex == "" and w3.profile.parent_word() == "", "性別は決めなくてもよい(呼び方は付けない)")

func _test_rename() -> void:
	print("名前を付け直す")
	var w := _world()
	var p := w.profile
	_check(p.rename("x") == "unknown", "決める前は付け直せない")
	p.choose("とむ", "m")
	_check(p.rename("トム") == "renamed" and p.name == "トム", "名前を付け直せる")
	_check(p.rename("トム") == "same", "同じ名前なら変わらない")
	_check(p.rename(" ") == "empty" and p.name == "トム", "空にはできない")
	_check(p.rename("あいうえおかきくけ") == "too_long", "長すぎる名前にはできない")
	_check(p.sex == "m", "性別は変わらない")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	w.choose_profile("とむ", "f")
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.profile.chosen and w2.profile.name == "とむ" and w2.profile.sex == "f", "名前と性別を読み直せる")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_check(data.has("profile"), "セーブに profile がある")
	data.erase("profile")
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(not w3.profile.chosen, "自分の記録がないセーブは、まだ決めていない")
	data["profile"] = {"chosen": true, "name": "", "sex": "f"}
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	w3.load_game()
	_check(not w3.profile.chosen, "名前のない記録は、まだ決めていないことにする")
	data["profile"] = {"chosen": true, "name": "とむ", "sex": "zzz"}
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	w3.load_game()
	_check(w3.profile.chosen and w3.profile.sex == "", "知らない性別は「決めない」にする")

func _test_picker() -> void:
	print("自分のことを決める画面")
	var picker := ProfilePicker.new()
	root.add_child(picker)
	var got := []
	picker.chosen.connect(func(n, s): got.append([n, s]))
	picker.open()
	_check(picker.visible and picker.step == "input", "はじめは名前と性別")
	_check(picker._sex_buttons.size() == 3 and picker._sex_buttons[""].text.contains("決めない"), "男性・女性・決めない から選ぶ")
	_check(picker.sex == "", "はじめは「決めない」")
	picker.next()
	_check(picker.step == "input" and picker.body_text().begins_with("名前を入れてください"), "名前が空なら先へ進まない")
	picker.type_name("とむ")
	picker.set_sex("f")
	_check(picker._sex_buttons["f"].text == "● 女性", "選んだ性別に印")
	picker.press("次へ")
	_check(picker.step == "confirm" and picker.body_text().contains("性別: 女性"), "確かめる")
	picker.press("直す")
	_check(picker.step == "input" and picker.typed_name() == "とむ" and picker.sex == "f", "直すと、入れた中身が残っている")
	picker.next()
	picker.press("これで始める")
	_check(got == [["とむ", "f"]] and not picker.visible, "決めると閉じて、名前と性別を出す")
	picker.queue_free()
