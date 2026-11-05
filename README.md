# Feral Kingdom

A turn-based strategy game made with Godot. This repository contains the client,
game rules and the artwork needed to play. Multiplayer uses the existing
Cloudflare relay; players do not need to run a server or forward ports.

## Open and play in Godot

1. Install the **standard edition of Godot 4.7** (the project is configured for
   Godot 4.7; the development installation is 4.7.2). The .NET edition is not required.
2. Download this repository using **Code → Download ZIP**, then extract the entire
   ZIP. Alternatively, clone it:

   ```sh
   git clone --depth 1 https://github.com/lord-cepo/feral-kingdom.git
   ```

3. In Godot's Project Manager, choose **Import** and select `project.godot` from
   the extracted/cloned folder. Open the project and wait for the first artwork
   import to finish.
4. Press **F5** or click **Run Project** to open the game menu.

All runtime assets are included. Normal play requires no Python, Node.js,
PixelLab account, Cloudflare account or API keys. Godot itself is not bundled.

Character animations use the optimized sprite sheets in
`assets/characters/sheets/`. Original individual character frames are excluded
from this repository; they are needed only for artwork editing and rebuilding
the sheets. Other individual images, including interface, terrain and effects,
remain included because the game uses them.

## Play with another person

Both players should download the **same commit/version** of this repository and
run it in Godot.

1. In **Build**, save an army of distinct cards containing exactly one hero.
   Army sizes are **8, 12 or 16** cards.
2. One player chooses **Host**, selects the army size and an initial pool of
   **8, 10 or 12 deployments**, then chooses **Create game**.
3. The other player chooses **Find** and joins the listed game.
4. Each chooses a saved army matching the room size and presses **Ready**.
5. The host presses **Start game**. Deploy your hero first, then play using the
   highlighted units, actions and targets.

The host runs the existing game rules; the relay forwards messages. Each player
controls their own choices. When a trigger asks for acknowledgement, each player
presses Space or clicks the blink once. Use **Reconnect** after losing the
connection; seats are reserved for two minutes. **Leave** closes room membership.

The live relay address is already configured in the client:
`wss://guerra-relay.feral-kingdom.workers.dev/v1/socket`.
Compatible waiting games appear in Find automatically. If a game does not appear,
check that both players downloaded the same version.

Multiplayer client scripts compile, but a full two-device match and reconnect
have not yet been verified. This is a development build.

## Files and development

- [Game rules](docs/GENERAL_RULES.md)
- [Multiplayer client and reconnect details](docs/MULTIPLAYER.md)
- [Project file guide](docs/FILE_GUIDE.md)
- [Relay deployment instructions](relay/README.md) — for maintainers only;
  players use the deployed relay.

Saved armies, reconnect credentials and offline snapshots live in Godot's local
user-data folder, outside the repository. Keep reconnect credentials private.

When changing game rules or networking, regenerate the compatibility fingerprint
before distributing a new client:

```sh
python tools/generate_network_fingerprint.py
```

Godot automatically imports source assets and builds its local `.godot` cache.
Generated caches, local tools, exported bundles and credentials are excluded from
Git. Tests are opt-in under this project's `AGENTS.md` instructions.

The character import/alignment/sheet-building tools require the original source
frames in addition to Python/Pillow. Those source frames are kept separately
from the playable client.
