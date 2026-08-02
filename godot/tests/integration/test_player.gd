# FR-P-03 AC2 / B7：ViewLight 兜底纹理——_ready 时若 PointLight2D 无纹理，
# 程序创建 GradientTexture2D 径向渐变占位（白芯透明边），P4 交付后替换。
extends GutTest

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"


func test_view_light_has_fallback_texture_after_ready() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		fail_test("尚未实现 %s" % PLAYER_SCENE)
		return
	var player: Node = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(player)
	await wait_process_frames(2)
	var light: PointLight2D = player.get_node_or_null(^"%ViewLight") as PointLight2D
	assert_not_null(light, "玩家应有 %ViewLight（PointLight2D）")
	if light == null:
		return
	assert_not_null(light.texture, "ViewLight 应有纹理（无美术时程序生成兜底渐变）")
	if light.texture != null:
		assert_true(light.texture is GradientTexture2D,
			"兜底纹理应为 GradientTexture2D 径向渐变，实际：%s" % light.texture)
		if light.texture is GradientTexture2D:
			var gradient_tex: GradientTexture2D = light.texture as GradientTexture2D
			assert_eq(gradient_tex.fill, GradientTexture2D.FILL_RADIAL, "兜底纹理应为径向填充")
			var gradient: Gradient = gradient_tex.gradient
			assert_not_null(gradient, "兜底纹理应有 Gradient")
			if gradient != null:
				assert_almost_eq(gradient.get_color(0).a, 1.0, 0.001, "渐变中心应为不透明（白芯）")
				assert_almost_eq(gradient.get_color(gradient.get_point_count() - 1).a, 0.0, 0.001,
					"渐变边缘应为全透明")
