class_name PostOffice
extends RefCounted
## Pelipper Post Office counters.
##   help_counter(): the guide Pelipper (post_office_guide1.c CreateHelperPelipperMenu): Post Office /
##     Bulletin Board / Delivery / Friend Rescue guides, then Friend Rescue Info / Go rescue / Get help /
##     Deleting Mail Info, all with Red's text. The remake's Wonder Mail entry and Make Wonder Mail stay
##     reachable here (Red takes Wonder Mail on the title menu).
##   FriendRescue.counter(): the Friend Rescue counter (SPECIAL_TEXT_FRIEND_RESCUE).

const G := "post_office_guide1:"
const PELIPPER := "0279"

static func _nm() -> String:
	return str(DB.species.get(PELIPPER, {}).get("name", "Pelipper"))

static func _ask(root: Control, key: String, opts: Array, sel := 0) -> int:
	return await RedText.ask(root, G + key, _nm(), PELIPPER, opts, {}, sel)

static func _say(root: Control, key: String) -> void:
	await RedText.say(root, G + key, _nm(), PELIPPER)

static func help_counter(root: Control) -> void:
	var first := true
	var sel := 0
	while true:
		var opts: Array = ["Post Office", "Bulletin Board", "Delivery", RedText.line("{COLOR YELLOW}Friend Rescue{RESET}"),
			"Wonder Mail", "Make Wonder Mail", "Cancel"]
		var c := await _ask(root, "sImYourGuide" if first else "sAnythingElse", opts, sel)
		first = false
		if c < 0 or c == 6:
			return
		sel = c
		match c:
			0: await _say(root, "sPostOfficeExplanation")
			1: await _say(root, "sBulletinBoardExplanation")
			2: await _say(root, "sDeliveryExplanation")
			3: await _friend_rescue_guide(root)
			4: await load("res://scripts/ui/wonder_mail_ui.gd").enter_code(root)
			5: await load("res://scripts/ui/wonder_mail_ui.gd").maker(root)
		if TeamScreens.auto_on():
			return

static func _friend_rescue_guide(root: Control) -> void:
	var sel := 0
	while true:
		var c := await _ask(root, "sWhatdYouWantToKnow", ["Friend Rescue Info", RedText.line("{COLOR YELLOW}Go rescue{RESET}"),
			RedText.line("{COLOR YELLOW}Get help{RESET}"), "Deleting Mail Info", "Exit"], sel)
		if c < 0 or c == 4:
			return
		sel = c
		match c:
			0: await _say(root, "sFriendRescueExplanation")
			1: await _sub_guide(root, [["Rescue Procedures", "sRescueProceduresExplanation"], ["Receive SOS Mail", "sReceiveSOSMailExplanation"],
				["Leave for Rescue", "sLeaveForRescueExplanation"], ["Send A-OK Mail", "sSendAOKMailExplanation"],
				["Get Thank-You Mail", "sGetThankYouMailExplanation"]])
			2: await _sub_guide(root, [["Getting Help", "sGettingHelpExplanation"], ["Send SOS Mail", "sSendSOSMailExplanation"],
				["Receive A-OK Mail", "sReceiveAOKMailExplanation"], ["Send Thank-You Mail", "sSendThankYouMailExplanation"]])
			3: await _say(root, "sDeletingMailExplanation")
		if TeamScreens.auto_on():
			return

static func _sub_guide(root: Control, items: Array) -> void:
	var labels: Array = []
	for it in items:
		labels.append(it[0])
	labels.append("Exit")
	var sel := 0
	while true:
		var c := await _ask(root, "sWhatdYouWantToKnow", labels, sel)
		if c < 0 or c >= items.size():
			return
		sel = c
		await _say(root, items[c][1])
		if TeamScreens.auto_on():
			return
