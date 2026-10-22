# src/net: sessions, hot-seat, online play

The host machine owns the `GameState` and `RulesEngine`. Everyone else, and every seat played
on the host, only ever sees `ViewFilter.view_for(state, seat)` plus the events that seat may
see (`NetEventFilter`). Clients send actions; the host judges them.

```
NetHost ── transport ──► NetClient          (one per remote player)
  │ local_update(seat, view, events)        (seats played on this machine)
  └─ HotSeat                                (several local seats, pass-the-screen)
Transports: LoopbackTransport (tests, in-process)   WebRtcTransport (online, peer-to-peer)
```

## UI entry point: the `Net` autoload

| Call | Returns | Then listen to |
|---|---|---|
| `Net.start_local(state, engine, ["p1"])` | `NetHost` | `local_update(seat, view, events)` |
| `Net.start_hot_seat(state, engine, ["p1", "p2"])`, then `hot.start()` | `HotSeat` | `handoff_requested(seat, name)`, `view_updated(seat, view, events)` |
| `Net.open_online(host)` | | `host.room_opened(code)`, `host.open_failed(reason)`, `host.seats_changed(table)` |
| `Net.join_online(code, name, seat = "")` | `NetClient` | `joined(seat)`, `view_updated(view, events)`, `action_answered(id, result)`, `refused(code, reason)`, `join_failed(reason)`, `connection_lost(retrying)`, `seats_changed(table)` |
| `Net.leave()` | | |
| `Net.online_available()` | `bool` | false if the WebRTC add-on is missing |

Sending actions:
- On the host: `host.submit(seat, action)` returns `{"result": RuleResult, "events": Array}`.
  The procedural GM uses seat `"gm"`. A seat may only command units whose `controller` is that seat.
- Hot-seat: `hot.submit(action)` (as the seat at the screen).
- Client: `client.submit(action)` returns a request id; the answer comes as
  `action_answered(id, result)` with `result` = `RuleResult.to_dict()`, and the events arrive in
  the next `view_updated`.
- After changing the state outside `submit()` (battle setup, loading a save), call
  `host.send_updates()` so every seat gets a fresh view.

Hot-seat flow: `handoff_requested` → hide the board, show "Pass to <name>" with a Ready
button → `hot.confirm_handoff()` → `view_updated` draws that seat's view and replays the events
it missed. The screen passes automatically when the active unit belongs to another local seat;
`hot.pass_to(seat)` passes it by hand.

`seat_table()` / `seats_changed(table)`: `seat -> {name, side, player, where: "local" | "remote" | "open", connected}`.

Refusal codes (`NetProtocol.REFUSE_*`): `version_mismatch` (tell them to update via the
launcher), `no_free_seat`, `seat_taken`.

## Online details

- Matchmaking: PeerJS Cloud (`0.peerjs.com`, free, no account). It only relays the connection
  offers when someone joins; game traffic is direct. Its messages must look like the official
  PeerJS client's or it drops the sender, so `WebRtcTransport` builds them that way.
- NAT: Google STUN only. No TURN relay yet, so players on very strict networks may not
  connect. Add one without a new build via `user://net_config.json` (see `NetConfig`).
- Room code: 6 characters, host id on the server is `lancerautogm-<CODE>`.
- Reconnect: a client keeps its seat token and retries (1, 2, 4, 8, 15, 30 s); the host holds
  the seat. A host that loses the matchmaking server keeps its connected players and retries.
- Big messages are split into 12k-character chunks on the data channel.
- Version: `NetProtocol.game_version()` = `application/config/version` (set from the git tag by
  the release workflow, "dev" otherwise) + protocol number. Hosts refuse other versions.
- Real end-to-end check (needs internet):
  `godot --headless --path . -s res://src/net/tools/online_smoke_test.gd`
- The WebRTC add-on isn't committed: `bash addons/fetch_webrtc_native.sh` (pinned + SHA-256).
