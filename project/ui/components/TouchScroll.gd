extends RefCounted

## Makes a ScrollContainer behave properly under a finger.
##
## The problems this fixes (all confirmed with simulated touch events):
##
##  1. Swipes that start on anything interactive don't scroll. Godot's PanelContainer, Button
##     and plain Control default to mouse_filter STOP, which stops touch events from reaching the
##     ScrollContainer. Rows, cards, buttons and even spacer Controls are all like that, so a
##     swipe only worked if the finger happened to start on a bare label. Everything inside the
##     container is switched to PASS (still handles its own taps, but lets the event through).
##
##  2. A swipe that starts on a Button also presses it, and lifting the finger over it counts as
##     a tap, so scrolling could select a row or start a game. When the finger has clearly
##     started dragging, any button still in its pressed state is cancelled.
##
##     The finger's emulated mouse also stays "attached" to that button for the whole gesture, so it
##     kept re-lighting with its hover/pressed style while the page scrolled, and stayed lit after
##     the finger lifted. The held button is silenced for the rest of the gesture and its hover is
##     cleared when the finger lifts.
##
##  3. scroll_deadzone defaults to 0, so a tap with a little finger jitter scrolls the page.
##
##  4. The app hides its scrollbars, but AUTO mode still reserves space for them (and leaves an
##     invisible bar on the screen edge that grabs touches). SHOW_NEVER keeps scrolling and drops both.
##
## Call TouchScroll.apply(scroll) once after creating the container. Content added later
## (rebuilt leaderboard rows, loaded data) is covered too.

## Finger travel (px) before a touch counts as a scroll rather than a tap
const DEADZONE := 10

static func apply(scroll: ScrollContainer) -> void:
	scroll.scroll_deadzone = DEADZONE
	if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	if scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

	_let_touches_through(scroll, scroll)
	var tree := Engine.get_main_loop() as SceneTree
	var on_node_added := func(node: Node):
		if is_instance_valid(scroll) and scroll.is_ancestor_of(node):
			_let_touches_through(node, scroll)
	tree.node_added.connect(on_node_added)
	scroll.tree_exiting.connect(func():
		if tree.node_added.is_connected(on_node_added):
			tree.node_added.disconnect(on_node_added))

	# Per-touch bookkeeping: how far has this finger travelled, and which buttons did we silence?
	var travel := [0.0]
	var silenced := []
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch:
			if event.pressed:
				travel[0] = 0.0
				silenced.clear()
			else:
				_end_gesture(scroll, silenced)
		elif event is InputEventScreenDrag:
			travel[0] += event.relative.length()
			if travel[0] > DEADZONE and silenced.is_empty():
				_silence_pressed_buttons(scroll, silenced))

## Switches STOP controls under `node` (inclusive) to PASS, so touches reach `scroll`.
static func _let_touches_through(node: Node, scroll: ScrollContainer) -> void:
	if node is Control and node != scroll and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	# the (hidden) scrollbars must never grab a touch
	if node == scroll:
		scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.get_h_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_let_touches_through(child, scroll)

## Cancels the press of any button the dragging finger is holding, and makes it ignore input until
## the finger lifts. Hiding a button for an instant resets its pressed/hover state (and sends it a
## mouse-exit), so lifting over it doesn't count as a tap; ignoring input stops the finger's emulated
## mouse from immediately hovering it again on the next move.
static func _silence_pressed_buttons(node: Node, silenced: Array) -> void:
	if node is BaseButton and node.visible:
		var mode: int = node.get_draw_mode()
		if mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED or mode == BaseButton.DRAW_HOVER:
			node.visible = false
			node.visible = true
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			silenced.append(node)
	for child in node.get_children():
		_silence_pressed_buttons(child, silenced)

## The finger lifted: give silenced buttons their input back, and clear whatever is still hovered
## (a finger has no hover, but the emulated mouse stays parked where the finger last was).
static func _end_gesture(scroll: ScrollContainer, silenced: Array) -> void:
	var tree := scroll.get_tree()
	if tree == null:
		return
	await tree.process_frame
	for button in silenced:
		if is_instance_valid(button):
			button.mouse_filter = Control.MOUSE_FILTER_PASS
	silenced.clear()
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	var hovered := scroll.get_viewport().gui_get_hovered_control()
	if hovered == null or not (hovered == scroll or scroll.is_ancestor_of(hovered)) or not hovered.visible:
		return
	# Hiding a control drops its focus. Never do that to a text field (it would close the keyboard
	# the instant it was tapped) or to anything else the player has just focused.
	if hovered is LineEdit or hovered is TextEdit or hovered.has_focus():
		return
	hovered.visible = false
	hovered.visible = true
