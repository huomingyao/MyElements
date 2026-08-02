# 导师美术加载与占位（FR-M-01/M-02）：立绘/小人图未交付（P4 排队中）时
# 生成确定性的纯色占位图，不崩溃、不留空白（SPEC-04 §1 兜底约定）。
# 真实素材就位后路径存在即自动使用，无需改代码。
extends RefCounted

# ==== 常量区 ====
const ANIM_IDLE: StringName = &"idle"
# idle 两帧的播放帧率（占位期也能看出"两帧切换"的观感）。
const IDLE_FPS: float = 2.0
# 占位图着色参数（纯展示，不参与玩法调参）。
const PLACEHOLDER_SATURATION: float = 0.45
const PLACEHOLDER_VALUE: float = 0.75
const HUE_CIRCLE: int = 360


# ==== 逻辑区 ====
# 路径存在则加载真实纹理；否则生成按 key 确定性着色的占位图。
static func texture_or_placeholder(path: String, size: Vector2i, key: String) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			return loaded as Texture2D
	return _placeholder(size, key)


# 房间小人 idle 动画：素材是横向两帧 sprite sheet 时切成两帧；
# 否则（含占位期）同一纹理放两帧，保持"两帧 idle"的结构不变。
static func idle_frames(path: String, frame_size: Vector2i, key: String) -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.add_animation(ANIM_IDLE)
	frames.set_animation_speed(ANIM_IDLE, IDLE_FPS)
	frames.set_animation_loop(ANIM_IDLE, true)
	var texture: Texture2D = texture_or_placeholder(path, frame_size, key)
	if texture.get_width() >= frame_size.x * 2 and texture.get_height() >= frame_size.y:
		var first: AtlasTexture = AtlasTexture.new()
		first.atlas = texture
		first.region = Rect2(0.0, 0.0, frame_size.x, frame_size.y)
		var second: AtlasTexture = AtlasTexture.new()
		second.atlas = texture
		second.region = Rect2(frame_size.x, 0.0, frame_size.x, frame_size.y)
		frames.add_frame(ANIM_IDLE, first)
		frames.add_frame(ANIM_IDLE, second)
	else:
		frames.add_frame(ANIM_IDLE, texture)
		frames.add_frame(ANIM_IDLE, texture)
	return frames


static func _placeholder(size: Vector2i, key: String) -> ImageTexture:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(_color_for(key))
	return ImageTexture.create_from_image(image)


static func _color_for(key: String) -> Color:
	var hue: float = float(absi(key.hash()) % HUE_CIRCLE) / float(HUE_CIRCLE)
	return Color.from_hsv(hue, PLACEHOLDER_SATURATION, PLACEHOLDER_VALUE)
