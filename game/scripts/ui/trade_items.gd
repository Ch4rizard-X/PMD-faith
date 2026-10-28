class_name TradeItems
extends RefCounted
## Main menu "Trade Items" (trade_items_menu.c) as a local stand-in: Red's menus and texts up to the point where
## the Game Link cable would connect, then Red's "no response" error and a note that link trading isn't
## available (there is no second game to trade with). Nothing leaves Kangaskhan Storage.
##
##   await TradeItems.open(root)

const NO_LINK := "Trading items over a [color=#7fe0ff]Game Link cable[/color]\nisn't available in this game."

static func open(root: Control) -> void:
	while true:
		var storage_empty := Game.storage.is_empty() or Game.storage.values().all(func(v): return int(v) <= 0)
		var c := await Dialog.ask(root, "What would you like to do?", [{"text": "Send item", "disabled": storage_empty}, "Receive item"])
		if c == 0:
			if await _send(root):
				return
		elif c == 1:
			if await _link(root, "Your friend will send you an item.\nWhen you are both ready, you\nmay communicate."):
				return
		else:
			return
		if ListMenu.auto:
			return

## Send: pick a stored item, Confirm / Info / Cancel, how many, confirm, then the link attempt.
static func _send(root: Control) -> bool:
	await Dialog.say(root, "Please choose the item to be sent.")
	var ids: Array = []
	var names: Array = []
	for id in Game.storage:
		if int(Game.storage[id]) > 0:
			ids.append(id)
			names.append("%s  %d" % [DB.item_name(str(id)), int(Game.storage[id])])
	if ids.is_empty():
		return false
	var k := await IQ.paged_choose(root, "Storage", names)
	if k < 0:
		return false
	var id := str(ids[k])
	while true:
		var a := ListMenu.make("", ["Confirm", "Info", "Cancel"])
		root.add_child(a)
		a.position = Vector2(21 * 8, 4 * 8) * UITheme.PX
		var r := await a.choose()
		if r == 1:
			await Dialog.say(root, "[color=#ffdc4a]%s[/color]\n%s" % [DB.item_name(id), TeamScreens.item_desc(id)])
			continue
		if r != 0:
			return false
		break
	var n := 1
	var have := int(Game.storage[id])
	if have > 1:
		var opts: Array = []
		for i in range(1, mini(have, 99) + 1):
			opts.append(str(i))
		var h := await IQ.paged_choose(root, "How many?", opts)
		if h < 0:
			return false
		n = h + 1
	var ok := await Dialog.ask(root, "[color=#7fe0ff]%d[/color] [color=#7fff7f]%s(s)[/color]\nwill be sent.\nIs that OK?" % [n, DB.item_name(id)], ["Yes", "No"])
	if ok != 0:
		return false
	return await _link(root, "Preparing to send an item to your\nfriend. When you are both ready,\nyou may communicate.")

## The communication step: Yes / Cancel, "In communication...", then Red's no-response error.
static func _link(root: Control, prompt: String) -> bool:
	var c := await Dialog.ask(root, prompt, ["Yes", "Cancel"])
	if c != 0:
		return false
	var d := Dialog.get_box(root)
	d._show("[center]In communication...\nPlease wait with the power on.\nTo cancel, press %s.[/center]" % UITheme.glyph("B_BUTTON"), "", "Normal", "")
	d._finish_typing()
	await root.get_tree().create_timer(1.5).timeout
	d.hide_box()
	Audio.sfx("error")
	await Dialog.say(root, "There is no response from your friend.\nPlease make sure the sender and receiver\nare ready, then redo this from the start.")
	await Dialog.say(root, NO_LINK)
	return false
