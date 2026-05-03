# scripts/multiplayer_lobby.gd

ENet-based lobby (port 7777, max 8 players). Host creates server and shows lobby; joining client connects by IP. Host syncs the existing player list to new arrivals via `_sync_player_list` RPC, then broadcasts additions/removals to all. `start_game` RPC (authority, call_local) transitions all peers to `game.tscn`. Handles disconnect/fail by resetting peer and returning to setup panel.
