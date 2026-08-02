# 知识卡片弹窗（FR-G-06，IT-G06，TP-07 补）：合成成功弹出。
# 五字段（标题/方程式/现象/现实应用/固定底行）全部来自卡片字典（数据表经 RecipeDB.build_card 组装），
# 本脚本零文案（NFR-04）；任意键或点击跳过，跳过发 closed 信号。
extends Control

signal closed()

# ==== 逻辑区 ====

var _open: bool = false

@onready var _title: Label = %TitleLabel
@onready var _equation: Label = %EquationLabel
@onready var _body: Label = %BodyLabel
@onready var _application: Label = %ApplicationLabel
@onready var _footer: Label = %FooterLabel


func _ready() -> void:
	visible = false


# 展示一张卡片（五字段缺失时按空串处理，不崩溃）。
func show_card(card: Dictionary) -> void:
	_title.text = str(card.get("title", ""))
	_equation.text = str(card.get("equation", ""))
	_body.text = str(card.get("body", ""))
	_application.text = str(card.get("application", ""))
	_footer.text = str(card.get("footer", ""))
	_open = true
	visible = true


func is_open() -> bool:
	return _open


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


# AC3：任意键或点击跳过。
func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()
