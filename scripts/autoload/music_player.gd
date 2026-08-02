# 全局背景音乐（autoload）：跨场景常驻，循环播放。
# 只负责 BGM；音效由各处自行实例化（参考 collectable.gd / explosion.gd）。
extends Node

const BGM_PATH: String = "res://assets/audio/background.mp3"
# 音量（调参项）：垫在音效与字幕提示之下。
const BGM_VOLUME_DB: float = -8.0

var _player: AudioStreamPlayer = null


func _ready() -> void:
	var stream: AudioStream = load(BGM_PATH) as AudioStream
	if stream == null:
		push_warning("[music] BGM 加载失败：%s" % BGM_PATH)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = BGM_VOLUME_DB
	add_child(_player)
	_player.play()
