class_name NetProtocol
extends RefCounted
## Messages between host and clients. Every message is a JSON-safe Dictionary with a "t"
## (type) field. The host is authoritative: clients only ever send `hello` and `action`.
##
## client -> host
##   hello    {version, name, token, seat}   join, or rejoin with the token from `welcome`
##   action   {id, action}                   an action for the rules engine
## host -> client
##   welcome  {seat, token, room, version}   you have a seat; keep the token to reconnect
##   refused  {code, reason}                 not let in (see REFUSE_*); connection closes
##   update   {view, events}                 your filtered view + events you may see
##   result   {id, result}                   answer to your `action` (RuleResult.to_dict())
##   seats    {seats}                        who is sitting where (lobby / reconnect info)

## Bump when the message format changes in a way old builds can't read.
const PROTOCOL := 1

const HELLO := "hello"
const ACTION := "action"
const WELCOME := "welcome"
const REFUSED := "refused"
const UPDATE := "update"
const RESULT := "result"
const SEATS := "seats"

const REFUSE_VERSION := "version_mismatch"
const REFUSE_FULL := "no_free_seat"
const REFUSE_SEAT_TAKEN := "seat_taken"
const REFUSE_BAD_MESSAGE := "bad_message"

## Room codes avoid look-alike characters (0/O, 1/I/L) so they can be read out loud.
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6


## The build's version. Release builds get it from the git tag (the release workflow writes
## application/config/version); editor and test runs report "dev".
static func game_version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return "%s+p%d" % [v if v != "" else "dev", PROTOCOL]


static func new_room_code() -> String:
	# Not game randomness (that's state.dice): codes and tokens must be unguessable.
	var bytes := Crypto.new().generate_random_bytes(CODE_LENGTH)
	var code := ""
	for b in bytes:
		code += CODE_ALPHABET[b % CODE_ALPHABET.length()]
	return code


## Accepts "abc-123", " ABC123 " and the like; returns "" if it can't be a room code.
static func normalize_room_code(text: String) -> String:
	var code := ""
	for ch in text.to_upper():
		if ch in CODE_ALPHABET:
			code += ch
	return code if code.length() == CODE_LENGTH else ""


static func new_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
