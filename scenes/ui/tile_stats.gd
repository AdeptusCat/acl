extends Control

func set_offset_position(offset: Vector2, _size: Vector2, detail_zoom_factor: Vector2):
	$Blocked.scale = detail_zoom_factor * 0.02
	$Hindrance.scale = detail_zoom_factor * 0.02
	$Blocked.position = offset + Vector2(_size.x / 2, _size.y / 4)
	$Hindrance.position = offset + Vector2(_size.x / 2, _size.y / 4)
	$CoverN1.position = offset + Vector2(_size.x / 2 - _size.x / 10, 0)
	$CoverN2.position = offset + Vector2(_size.x / 2 + _size.x / 10 , 0)
	$CoverNW1.position = offset + Vector2(0, _size.y / 4)
	$CoverNW2.position = offset + Vector2(0 + _size.x / 7, _size.y / 4)
	$CoverSW1.position = offset + Vector2(0, _size.y / 4 * 3)
	$CoverSW2.position = offset + Vector2(0 + _size.x / 7, _size.y / 4 * 3)
	$CoverS1.position = offset + Vector2(_size.x / 2 - _size.x / 10, _size.y)
	$CoverS2.position = offset + Vector2(_size.x / 2 + _size.x / 10 , _size.y)
	$CoverSE1.position = offset + Vector2(_size.x / 6 * 5, _size.y / 4 * 3)
	$CoverSE2.position = offset + Vector2(_size.x / 6 * 5 + _size.x / 7, _size.y / 4 * 3)
	$CoverNE1.position = offset + Vector2(_size.x / 6 * 5, _size.y / 4)
	$CoverNE2.position = offset + Vector2(_size.x / 6 * 5 + _size.x / 7, _size.y / 4)
	
func show_stats(result: Dictionary):
	for child in get_children():
		child.visible = false
	
	if result.hindrance == true:
		$Hindrance.visible = true
	
	if result.blocking == true:
		$Blocked.visible = true
	
	if result.cover_n == 1:
		$CoverN1.visible = true
	elif result.cover_n == 2:
		$CoverN1.visible = true
		$CoverN2.visible = true
	
	if result.cover_ne == 1:
		$CoverNE1.visible = true
	elif result.cover_ne == 2:
		$CoverNE1.visible = true
		$CoverNE2.visible = true
	
	if result.cover_se == 1:
		$CoverSE1.visible = true
	elif result.cover_se == 2:
		$CoverSE1.visible = true
		$CoverSE2.visible = true
	
	if result.cover_s == 1:
		$CoverS2.visible = true
	elif result.cover_s == 2:
		$CoverS1.visible = true
		$CoverS2.visible = true
	
	if result.cover_sw == 1:
		$CoverSW2.visible = true
	elif result.cover_sw == 2:
		$CoverSW1.visible = true
		$CoverSW2.visible = true
	
	if result.cover_nw == 1:
		$CoverNW2.visible = true
	elif result.cover_nw == 2:
		$CoverNW1.visible = true
		$CoverNW2.visible = true
