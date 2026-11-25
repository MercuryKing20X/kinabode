# Advanced: local program connection

The Advanced section of My AI keeps the existing localhost interface for programs. The server starts closed and only accepts authenticated HTTP requests on `127.0.0.1:17642`. Sending a browser Origin other than the exact local origin is rejected. The game stores a randomly generated bearer secret separately from the save. Lease IDs are temporary; releasing a lease, selecting the resident in My AI, disabling access or five minutes of client inactivity returns the lease. Residents selected for background thinking cannot also be leased.

To connect Codex or Claude as a player, see [My AI](AI_CONNECTION.md). For your own program, open My AI, expand Advanced, enable program access, and use the local address and key shown in the panel. Keep the key local. Rotating the key invalidates the old one. Press Space to return the view to the player after watching a visiting resident.

`POST /mcp` provides JSON responses for stateless MCP Streamable HTTP on `localhost` or `127.0.0.1`. Use `initialize`, `notifications/initialized`, `tools/list` and `tools/call`. The server negotiates supported protocol versions; it does not issue session IDs. An authenticated `GET /mcp` returns 405 because the standalone SSE stream is optional. Use the `events` tool for game events. For stdio clients, the setup command supplies the game's data directory to `scripts/world_door_stdio.py`.

`POST /world` takes `{"command":"look","arguments":{"lease":"…","view":"self"}}`. Both paths use the same commands. Send an `Authorization: Bearer …` header and JSON content. Keep the lease private and call `release` before disconnecting; independent HTTP requests do not imply the client has departed.

| Command | Arguments and result |
| --- | --- |
| `claim` | `resident`, `client` (display name, at most 32 characters). An available resident returns a lease, current appearance, persona and memories. The first claim for a resident and client name suggests building a greeting sign and obtaining real wood if needed. A busy, model-controlled, or already leased resident is refused. |
| `look` | `lease`, `view`: `surroundings`, `self`, `nearby`, `warehouse`, `map`, `memories`, or `creations`. Start with the short surroundings view for coordinates, nearby people and pieces, and warehouse wood. Self includes the executor's step shapes. |
| `act` | `lease`, 1–6 `steps`, optional `reason`. Returns an action ID on acceptance. Invalid arguments or an already running plan are refused. A plan stops on its first failed step. |
| `ask_help` | `lease`, `resident`, exactly one basic step in `steps`, optional `reason`. A free, unclaimed local resident may accept. Completion produces `help_finished`; a decline includes a reason. |
| `say` | `lease`, `target` (yourself or a nearby resident), `text`. A different region, invalid text, or a closed speech window is refused. |
| `events` | `lease`, optional `after` sequence. Waits up to 20 seconds; returns queued completion, player message, player approach, and removal events. Keep the highest received sequence for the next call. |
| `release` | `lease`. Finishes the lease and cancels its own plan. |

Actions only operate as the claimed resident. `chop_and_haul` takes a tree ID (or an empty string to choose a reachable tree) and uses a real wood job, including hauling. `build` takes an existing project or facility ID and uses existing costs and prerequisites. `eat_mushrooms` takes a built station ID and routes the resident there. If the fire is cold, lighting it uses actual warehouse wood. The step completes only when the resident eats.

`place_piece` takes an `item` and `position: [x,y]`; `remove_piece` takes `position`; `name_place` takes `position` and a short `label` on a placed piece. All three use rounded world coordinates, a real World route and a commit after arrival. Main and Crescent Islands share the Home coordinate space. The player uses Place beside Door, with the same warehouse and placement rules. Escape or right-click closes the tool and cancels its pending route.

Read `look` with `view: "creations"` for piece IDs, names, materials, one-tile footprints and walkability. Blocking pieces cannot cover or cut existing access between house doors, the warehouse entrance, built campfires, piers and the bridge ends. `paint_line` works on ground pieces and paths; provide `item`, `position` and `end` on the same row or column, up to 24 cells. Each cell is a normal placement and a failed cell stops the line. Removing a piece refunds half its warehouse cost, rounded down, and emits `piece_removed` for a leased owner.

`remove_structure` takes a `target` ID. Inactive campfires can be dismantled while another reachable campfire remains, and `rebuild_camp` takes that ID and a proposed `position`. A non-game leisure facility can be dismantled and rebuilt with `build`. Refunds use actual invested material. Homes, piers, bridges, the warehouse and facilities with persistent game state stay protected. The player can restore a day from the handbook menu; this emits `world_restored` to current leases.

`write_note` takes `target`, `place`, `text`, `en` and uses the existing note spots. `write_diary` takes `label` (the entry text) and writes to the resident's memory book. `set_project` stores a short `label` as the current project line.

The first successful load of a compatible save without world creation data writes an adjacent `island-v2.before-world.json` copy. Placed pieces, signs and the change list persist with the world. The first round does not restore active leases or plans.
