# 包 E2：占位美术生成器的静态保障。
# 生成器需人工执行（./gen_placeholders.sh），本测试只保证两件事：
# 1) 脚本可编译加载（防止生成器本身语法/类型错误烂在仓库里）；
# 2) 尺寸与调色板常量符合 SPEC-08 §1/§2（图标 16×16、立绘 240×320、小人 32×32）。
# 用 load() 按路径取脚本而不是 class_name：实现缺失时是断言失败而非编译错误（SPEC-06 §2）。
extends GutTest

const GENERATOR_PATH: String = "res://scripts/tools/gen_placeholders.gd"


func test_generator_script_loads() -> void:
	var script: GDScript = load(GENERATOR_PATH) as GDScript
	assert_not_null(script, "占位美术生成器应可编译加载：%s" % GENERATOR_PATH)


func test_sizes_match_spec_08() -> void:
	var script: GDScript = load(GENERATOR_PATH) as GDScript
	assert_not_null(script)
	if script == null:
		return
	var instance: SceneTree = script.new() as SceneTree
	assert_not_null(instance, "生成器应可实例化（extends SceneTree）")
	if instance == null:
		return
	assert_eq(instance.get("ICON_SIZE"), Vector2i(16, 16), "图标尺寸应为 SPEC-08 §1 的 16×16")
	assert_eq(instance.get("AVATAR_SIZE"), Vector2i(240, 320), "立绘尺寸应为 SPEC-08 §1 的 240×320")
	assert_eq(instance.get("PIXEL_SIZE"), Vector2i(32, 32), "小人尺寸应为 SPEC-08 §1 的 32×32")
	instance.free()
