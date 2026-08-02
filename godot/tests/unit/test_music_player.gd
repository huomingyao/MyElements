# 全局背景音乐（MusicPlayer autoload）：注册存在、流加载、循环、播放中。
extends GutTest


func _autoload() -> Node:
	var root: Node = Engine.get_main_loop().root
	return root.get_node_or_null(NodePath("MusicPlayer"))


func _audio_player(node: Node) -> AudioStreamPlayer:
	if node == null:
		return null
	for child in node.get_children():
		if child is AudioStreamPlayer:
			return child as AudioStreamPlayer
	return null


func test_music_player_autoload_registered() -> void:
	assert_not_null(_autoload(), "MusicPlayer autoload 缺失")


func test_bgm_stream_loaded_looping_and_playing() -> void:
	var node: Node = _autoload()
	if node == null:
		fail_test("MusicPlayer 缺失，无法校验 BGM")
		return
	var player: AudioStreamPlayer = _audio_player(node)
	assert_not_null(player, "MusicPlayer 下没有 AudioStreamPlayer")
	if player == null:
		return
	assert_not_null(player.stream, "BGM stream 未加载")
	if player.stream is AudioStreamMP3:
		assert_true((player.stream as AudioStreamMP3).loop, "MP3 应开启循环")
	assert_true(player.playing, "BGM 应处于播放状态")
