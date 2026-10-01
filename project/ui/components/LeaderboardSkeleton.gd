extends RefCounted

## Pulsing placeholder for the leaderboard while scores load.
##
## Built from plain grey blocks that mirror the real podium and table rows
## (same widths, heights and gaps), so the layout doesn't jump when data lands.
## The pulse is the spec's `pulse` motion: 2 s loop, opacity 1 -> 0.5 -> 1.
## One tween drives the whole skeleton by fading its containers, rather than one
## animation per block.

const SkeletonBarClass = preload("res://ui/components/SkeletonBar.gd")
const BLOCK_COLOR := SkeletonBarClass.BLOCK_COLOR
const PULSE_SECONDS := SkeletonBarClass.PULSE_SECONDS
const PULSE_LOW := SkeletonBarClass.PULSE_LOW

## Fills `container` (an HBox) with 3 podium columns in 2nd, 1st, 3rd order.
static func fill_podium(container: BoxContainer) -> void:
	# [height of the podium block, bar width for the name]
	for spec in [[70, 44], [100, 56], [50, 40]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_END
		col.add_theme_constant_override("separation", 0)
		container.add_child(col)

		col.add_child(_block(Vector2(48, 48), Control.SIZE_SHRINK_CENTER))       # badge
		col.add_child(_gap(4))
		col.add_child(_bar_slot(spec[1], 10, 15))                                # name
		col.add_child(_bar_slot(34, 8, 14))                                      # score
		col.add_child(_gap(8))
		col.add_child(_block(Vector2(0, spec[0]), Control.SIZE_EXPAND_FILL))     # podium block

## Fills `container` (a VBox) with `count` placeholder table rows.
static func fill_rows(container: BoxContainer, count: int) -> void:
	for i in count:
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_width_bottom = 1
		sb.border_color = Tokens.LINE
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		row.add_theme_stylebox_override("panel", sb)
		container.add_child(row)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		row.add_child(hbox)

		# Rank column (36 wide)
		var rank_slot := Control.new()
		rank_slot.custom_minimum_size = Vector2(36, 36)
		hbox.add_child(rank_slot)
		var rank_bar := _block(Vector2(22, 22), Control.SIZE_SHRINK_BEGIN)
		rank_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rank_slot.add_child(rank_bar)
		rank_bar.position = Vector2(0, 7)

		# Badge + name/tag
		var player := HBoxContainer.new()
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player.add_theme_constant_override("separation", 8)
		hbox.add_child(player)
		player.add_child(_block(Vector2(32, 32), Control.SIZE_SHRINK_CENTER))

		var names := VBoxContainer.new()
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.add_theme_constant_override("separation", 6)
		player.add_child(names)
		# Vary the name width a little so the rows don't look stamped
		names.add_child(_block(Vector2(90 + (i * 23) % 50, 12), Control.SIZE_SHRINK_BEGIN))
		names.add_child(_block(Vector2(48, 8), Control.SIZE_SHRINK_BEGIN))

		# Score + date (right aligned)
		var score := VBoxContainer.new()
		score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		score.add_theme_constant_override("separation", 6)
		hbox.add_child(score)
		score.add_child(_block(Vector2(60, 16), Control.SIZE_SHRINK_END))
		score.add_child(_block(Vector2(36, 8), Control.SIZE_SHRINK_END))

## Starts the looping pulse over `targets` (Controls). Returns the Tween; kill it
## and reset `modulate.a` when real content replaces the skeleton.
static func start_pulse(owner: Node, targets: Array) -> Tween:
	var tween := owner.create_tween()
	tween.set_loops()
	var apply := func(alpha: float):
		for t in targets:
			if is_instance_valid(t):
				t.modulate.a = alpha
	var half := PULSE_SECONDS * 0.5
	tween.tween_method(apply, 1.0, PULSE_LOW, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(apply, PULSE_LOW, 1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

static func _block(min_size: Vector2, h_flag: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = BLOCK_COLOR
	r.custom_minimum_size = min_size
	r.size_flags_horizontal = h_flag
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func _gap(h: int) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

## A bar centred in a fixed-height slot, so it occupies the same space as the real label.
static func _bar_slot(width: float, bar_h: float, slot_h: float) -> Control:
	var slot := CenterContainer.new()
	slot.custom_minimum_size = Vector2(0, slot_h)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_block(Vector2(width, bar_h), Control.SIZE_SHRINK_CENTER))
	return slot
