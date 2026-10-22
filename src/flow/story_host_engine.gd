class_name StoryHostEngine
extends StoryEngine
## The host's stand-in for StoryEngine in the hub UI: every action goes through the
## StorySession, so friends connected online get the new view and events (StoryClient is the
## same idea on their side). Checks (validate) run on the real story as usual.

var session: StorySession


func _init(content: ContentDB, story_session: StorySession) -> void:
	super(content)
	session = story_session


func submit(_story: StoryState, _campaign: Campaign, action: Dictionary) -> Dictionary:
	return session.submit(str(action.get("seat", "gm")), action)
