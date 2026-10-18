class_name FogOfWarOverlay
extends Node2D

const SHADER: Shader = preload("res://assets/shader/fog_of_war.gdshader")

@export_range(4.0, 32.0, 1.0) var feather_width: float = 16.0
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.76
@export var wind_velocity: Vector2 = Vector2(5.0, 2.0)

var mask_texture: ImageTexture
var fog_material: ShaderMaterial
var mask_revision: int = 0

var _mask_image: Image
var _board_cells: Dictionary[Vector2i, bool] = {}
var _visible_cells: Dictionary[Vector2i, bool] = {}
var _bounds: Rect2 = Rect2()
var _noise: NoiseTexture2D


func configure(ground: HexagonTileMapLayer, grid_size: Vector2i, board_cells: Array[Vector2i]) -> void:
	_board_cells.clear()
	_visible_cells.clear()
	mask_revision = 0
	if grid_size.x <= 0 or grid_size.y <= 0:
		_mask_image = null
		mask_texture = null
		fog_material = null
		material = null
		_bounds = Rect2()
		queue_redraw()
		return
	global_transform = ground.global_transform
	var half_tile: Vector2 = Vector2(ground.tile_set.tile_size) * 0.5
	var initialized: bool = false
	for cell: Vector2i in board_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
			continue
		_board_cells[cell] = true
		var center: Vector2 = ground.map_to_local(cell)
		var cell_bounds: Rect2 = Rect2(center - half_tile, half_tile * 2.0)
		if initialized:
			_bounds = _bounds.merge(cell_bounds)
		else:
			_bounds = cell_bounds
			initialized = true
	_mask_image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RG8)
	_mask_image.fill(Color.BLACK)
	for cell: Vector2i in _board_cells:
		_mask_image.set_pixelv(cell, Color(1.0, 1.0, 0.0, 1.0))
	mask_texture = ImageTexture.create_from_image(_mask_image)
	_create_material()
	fog_material.set_shader_parameter("visibility_mask", mask_texture)
	fog_material.set_shader_parameter("grid_size", Vector2(grid_size))
	fog_material.set_shader_parameter("tile_size", Vector2(ground.tile_set.tile_size))
	fog_material.set_shader_parameter("cell_origin", ground.map_to_local(Vector2i.ZERO))
	mask_revision += 1
	queue_redraw()


func update_visibility(visible_cells: Array) -> void:
	if _mask_image == null:
		return
	var next_visible: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in visible_cells:
		if _board_cells.has(cell):
			next_visible[cell] = true
	if next_visible == _visible_cells:
		return
	for cell: Vector2i in _visible_cells:
		if not next_visible.has(cell):
			_mask_image.set_pixelv(cell, Color(1.0, 1.0, 0.0, 1.0))
	for cell: Vector2i in next_visible:
		if not _visible_cells.has(cell):
			_mask_image.set_pixelv(cell, Color(1.0, 0.0, 0.0, 1.0))
	_visible_cells = next_visible
	mask_texture.update(_mask_image)
	mask_revision += 1


func _create_material() -> void:
	if _noise == null:
		var noise: FastNoiseLite = FastNoiseLite.new()
		noise.seed = 6049
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.018
		noise.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = noise
	fog_material = ShaderMaterial.new()
	fog_material.shader = SHADER
	fog_material.set_shader_parameter("cloud_noise", _noise)
	fog_material.set_shader_parameter("feather_width", feather_width)
	fog_material.set_shader_parameter("opacity", opacity)
	fog_material.set_shader_parameter("wind_velocity", wind_velocity)
	fog_material.set_shader_parameter("hdr_2d", get_viewport().use_hdr_2d)
	var palette: Dictionary = TerrainPalette.PALETTE.data["families"]["grid_fog"]
	var colors: Array = palette["colors"]
	for index: int in range(3):
		var color: Color = Color(str(colors[index + 2]))
		var parameter: String = ["shadow_color", "body_color", "light_color"][index]
		fog_material.set_shader_parameter(parameter, Vector4(color.r, color.g, color.b, color.a))
	material = fog_material


func _draw() -> void:
	if mask_texture != null and not _board_cells.is_empty():
		draw_rect(_bounds, Color.WHITE)
