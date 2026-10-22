class_name HouseRulesFlow
extends RefCounted
## Who decides the house rules in the open game, and how a change gets there (HouseRules).
## A human GM decides (at the host's computer, or a friend who joined as the GM); with the AI
## as GM, the host does. Everyone else sees the game's set read-only.
##
## The deciding player's own preferences (GameSettings.house_rules, `mine`) go into the game:
## in battle as the `set_house_rules` action (announced to everyone), between battles into the
## campaign (the host keeps it; a friend who is the GM sends {"house_rules": set} on the lobby
## channel, which the host takes only from the GM seat of a game with a human GM).

## This player's preferences, kept current by the menus (MenuSession, the settings page).
static var mine: Dictionary = {}


## This player's set (every rule).
static func my_set() -> Dictionary:
	return HouseRules.normalized(mine)


## Does the player at this computer decide the house rules in the open game? `client`: the
## connection of a friend not yet in a battle or story (the lobby's).
static func i_decide(campaign: Campaign, client: NetClient = null) -> bool:
	var s := GameFlow.session
	if s != null and not s.is_host and not s.over:
		return s.seat == NetHost.GM_SEAT
	if GameFlow.story_client != null:
		return GameFlow.story_client.seat == NetHost.GM_SEAT
	if client != null:
		return client.seat == NetHost.GM_SEAT
	if campaign == null:
		return true
	return not bool(campaign.options.get("human_gm", false)) or str(campaign.options.get("gm_where", "local")) == "local"


## The set in effect in the open game (what the settings page shows).
static func current(campaign: Campaign) -> Dictionary:
	var s := GameFlow.session
	if s != null and not s.over:
		var hr: Dictionary = s.host.state.house_rules if s.is_host else (s.view.get("house_rules", {}) as Dictionary)
		if not hr.is_empty():
			return HouseRules.normalized(hr)
	if GameFlow.story_client != null and GameFlow.story_client.campaign != null:
		return HouseRules.of_campaign(GameFlow.story_client.campaign)
	if campaign != null and campaign.options.has("house_rules"):
		return HouseRules.of_campaign(campaign)
	return my_set()


## Puts this player's set into the open game, if they decide. Returns "" or why not. Battle
## rules go into a running battle as `set_house_rule` actions (each announced to everyone) and
## into the campaign; story rules go through the StoryEngine `house_rule` action (which starts
## them cleanly and announces them).
static func push(campaign: Campaign, store: SaveStore = null, client: NetClient = null) -> String:
	if not i_decide(campaign, client):
		return "The GM decides the house rules in this game." if campaign == null or bool(campaign.options.get("human_gm", false)) or client != null or GameFlow.story_client != null else "The host decides the house rules in this game."
	var set := my_set()
	var s := GameFlow.session
	if s != null and not s.over:
		var st: GameState = s.host.state if s.is_host else s.mirror
		for id: String in set:
			if HouseRules.is_battle_rule(id) and (st == null or HouseRuleSwitches.on(st, id) != bool(set[id])):
				var a := {"type": "set_house_rule", "actor": "", "params": {"id": id, "on": bool(set[id])}}
				if s.is_host:
					s.host.submit(NetHost.GM_SEAT, a)
				else:
					s.client.submit(a)
	var battle_set := {}
	for id: String in set:
		if HouseRules.is_battle_rule(id):
			battle_set[id] = set[id]
	var remote: NetClient = client if client != null else (s.client if s != null and not s.is_host else null)
	if remote != null or GameFlow.story_client != null:
		# A friend who is the GM: story rules through the story, battle rules to the host.
		var sc := GameFlow.story_client
		if sc != null and sc.story != null:
			for id: String in _story_changes(sc.campaign, set):
				sc.submit(sc.story, sc.campaign, {"type": "house_rule", "params": {"id": id, "on": bool(set[id])}})
		var msg := {"house_rules": battle_set}
		if remote != null:
			msg["t"] = NetProtocol.LOBBY
			remote.transport.send(NetTransport.HOST_PEER, msg)
		elif sc != null and sc.send.is_valid():
			sc.send.call(msg)
		return ""
	if campaign == null:
		return ""
	var hr: Dictionary = (campaign.options.get("house_rules", {}) as Dictionary).duplicate()
	hr.merge(battle_set, true)
	campaign.options["house_rules"] = hr
	var story_ok := GameFlow.is_story(campaign) and GameFlow.story != null and GameFlow._story_campaign == campaign.id
	for id: String in _story_changes(campaign, set):
		var a := {"type": "house_rule", "seat": "gm", "params": {"id": id, "on": bool(set[id])}}
		if GameFlow.story_session != null and story_ok:
			GameFlow.story_session.submit("gm", a)
		elif story_ok:
			GameFlow.story_engine.submit(GameFlow.story, campaign, a)
		else:
			(campaign.options["house_rules"] as Dictionary)[id] = bool(set[id])  # no story open (missions only)
	if store != null:
		if story_ok:
			GameFlow.save_story(campaign, store)
		else:
			store.save_campaign(campaign)
	if GameFlow.story_session != null:
		GameFlow.story_session.resync()
	return ""


## Story rules whose setting differs between `set` and the campaign's.
static func _story_changes(campaign: Campaign, set: Dictionary) -> Array:
	var now := HouseRules.of_campaign(campaign)
	return set.keys().filter(func(id: String) -> bool: return not HouseRules.is_battle_rule(id) and bool(now.get(id, false)) != bool(set[id]))


## Host: a lobby-channel message. Takes {"house_rules": set} (battle rules; story rules come as
## story actions) only from the GM seat of a game with a human GM. Returns the ids that changed
## ([] if it wasn't taken).
static func on_message(host: NetHost, campaign: Campaign, seat: String, msg: Dictionary) -> Array:
	if not msg.get("house_rules") is Dictionary or seat != NetHost.GM_SEAT or host == null or not host.human_gm or campaign == null:
		return []
	var before := HouseRules.of_campaign(campaign)
	var hr: Dictionary = (campaign.options.get("house_rules", {}) as Dictionary).duplicate()
	var changed: Array = []
	for id: Variant in msg["house_rules"]:
		if HouseRules.is_battle_rule(str(id)):
			hr[str(id)] = bool(msg["house_rules"][id])
			if bool(before[str(id)]) != bool(hr[str(id)]):
				changed.append(str(id))
	campaign.options["house_rules"] = hr
	return changed
