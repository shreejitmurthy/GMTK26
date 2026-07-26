# GMTK26 — Plague Doctor (LÖVE2D)

Top-down hack-and-slash jam game. **Countdown timer is health** — the time you can withstand the plague. Enemy hits drain seconds; at 0 the company extracts you.

## What works today

- Grey room + camera follow
- Windfield world (`scripts/physics.lua`): **zero gravity**, collision classes, stub arena walls
- Player (`scripts/player.lua`): WASD + arrows, **normalized** diagonal velocity, collider-owned movement, Shift dash with yellow flash/white smears, and directional run/held-idle/attack animations from `plagueDoctorSheetAttack.png`
- Sword (`scripts/sword.lua`): separate actor using frame one of the 16×16 sword atlas; a continuous outward turnover finishes in mirrored 15° resting tilts without crossing the player
- Slash trail (`scripts/slash_trail.lua`): procedural fading ribbon generated from the sword's hilt/tip pose and split across behind/front player layers
- Enemies: soft barriers + `EnemyHit` sensor hurtboxes; resistance increases near their body and contact permits only a tiny, momentum-free nudge
- Enemies can **move** via shared locomotion (`moveToward` / `moveAway` / `stop`); after intentional AI motion each frame, `pushAnchorX/Y` is refreshed to the collider so soft contact still works and AI is not yanked back to spawn
- **Kinematic wall policy:** Enemy bodies are kinematic (Box2D does not resolve Enemy vs Wall). Motion uses `slideEnemyAgainstWalls` / `constrainEnemyMotion`; soft-push uses `trySetEnemyPosition` (never teleports into walls). `clampEnemyToPlayable` + per-frame `clampAllEnemiesToPlayable` keep every enemy inside the stub arena interior and clear of Wall colliders (unstick prefers arena center — never ejects OOB).
- Four enemy types (`scripts/enemy_types.lua`): **chaser**, **fleer**, **keeper**, **ranger** — polished locomotion; ranger cornered melee drains the plague timer
- **Plague countdown** (`scripts/countdown.lua`): top-center timer is health (default **90s**) with a thin **Plague Tolerance** fuse. Enemy hits → `state:applyPlayerDamage` → `countdown:damage` (**5s** default, **0.6s** i-frames). **H** debug-damages **3s** (bypasses i-frames). Player sword hits do **not** drain your timer. At 0 → **EXTRACTED**
- **Period HUD type:** `res/fonts/Italianno-Regular.ttf` (OFL) — copperplate / roundhand cursive for timer, labels, extract, help text
- **F1** / backtick toggles collider debug draw (+ C/F/K/R type letters); **F2** re-runs console PASS/FAIL selftest
- **STI map:** `res/maps/map.lua` — one Victorian decaying courtyard; districts by props (Ash Market / Plague Well / Watch Yard)
- **Nest cleanse loop** (`scripts/nests.lua`): stand in nest + **Hold E** for 2s to seal (serum cost 2s once); kill infected → `+1s`; 3/3 → **SECTOR CLEANSED**; timer 0 → **EXTRACTED**
- **Courtyard collapse** (`scripts/collapse.lua`): tiles crack (1s telegraph) then fall into black abyss; standing on a fallen cell → **EXTRACTED**. Fountain + nest centers never fall.

Physics loop: input → normalize → `setLinearVelocity` → swing pose + sync sensors → `world:update(dt)` → hit enter poll → sync draw/camera from collider.

---

## Workstreams

| Workstream | Owner this pass | Notes |
|---|---|---|
| **Map loading (STI)** | Shree | Unless physics is blocked waiting on walls |
| **Animations** | Animator | Keep draw hooks simple; anims attach later |
| **Physics movement (Windfield)** | **Bharat** | Scope below is locked |

---

## Physics (locked decisions)

### Engine
- **LÖVE2D** + **`lib/windfield`** (already vendored). Do not add another physics lib.

### Architecture
- Keep the existing **actor / player** pattern in `main.lua` and `scripts/`.
- **Do not** port the full ECS from `example_reference_scripts/ref1` for the jam.
- `ref1` / `ref2` are reference only: steal Windfield usage patterns, not frameworks or platformer feel.

### Movement style
- **Top-down, zero gravity.** World gravity must be `(0, 0)`.
- **Do not** copy platformer gravity / jump from `example_reference_scripts/ref2`.
- Controls table (ref2-style), WASD **and** arrows:
  ```lua
  p.controls = {
      left  = {"a", "left"},
      right = {"d", "right"},
      up    = {"w", "up"},
      down  = {"s", "down"},
  }
  ```
- **Normalize direction before multiplying by speed** (diagonal must not be √2 faster).

### Source of truth for position
- The **Windfield collider** owns position.
- Each frame after `world:update(dt)`: sync actor draw/camera from `collider:getX()` / `getY()`.
- Do **not** mutate `pos` / `x` / `y` for movement; set collider linear velocity from input instead.

### Collision classes (exact names)

| Class | Role |
|---|---|
| `Player` | Player body |
| `Enemy` | Non-impulse body with configurable soft resistance |
| `Wall` | Static blockers |
| `PlayerAttack` | Player attack **sensor** (hitbox; no solid push) |
| `EnemyHit` | Enemy hurt / attack **sensor** (no solid push) |

Helpers: `physics.newPlayerCollider`, `physics.newEnemyCollider`, `physics.addWall` / `addWallsFromObjects`, `physics.newSensor`.

Enemy options can include type, AI tunables, and soft-contact tuning:
```lua
enemy:new(x, y, { type = "chaser" })
enemy:new(x, y, {
    type = "keeper",
    speed = 70,
    preferredDistance = 70,
    band = 18,
    softPadding = 16,
    maxPushDistance = 2,
})
```

| Type | Behavior | Default tunables |
|---|---|---|
| `chaser` | Chase when `distance <= aggroRange`; spread out while holding inside `stopDistance` (+ deadzone hysteresis); idle outside aggro | speed 75, aggroRange 140, stopDistance 28, stopDeadzone 6, separationDistance 28, separationSpeed 24 |
| `fleer` | Run away when `distance <= fleeRange` (+ fleeDeadzone hysteresis); idle farther out; never chases | speed 95, fleeRange 90, fleeDeadzone 10 |
| `keeper` | Hold ring at `preferredDistance ± band` while in `aggroRange`; idle outside aggro | speed 70, aggroRange 160, preferredDistance 70, band 18 |
| `ranger` | Holds a safe LOS position, but when cornered it stops, faces the player, and makes cooldown-limited melee hits | speed 65, aggroRange 190, safeDistance 95, meleeRange 32, meleeReleaseRange 39, meleeCooldown 0.8 |

Placeholder draw colors differ per type; the ranger is purple and flashes gold when hitting. F1/DEBUG shows a tiny **C** / **F** / **K** / **R** above each enemy. Art assets and other enemy attacks still later.

**Soft-anchor rule:** when an enemy intentionally moves, every frame after setting motion set `collider.pushAnchorX/Y` to the current collider position (via `enemy:refreshPushAnchor`).

### Enemy AI
Tune in `scripts/enemy_types.lua` (`defaults`) or per-spawn overrides in `enemy:new(x, y, { type=..., speed=..., ... })`.

- **Speeds / ranges:** raise `speed` for snappier pressure; widen `aggroRange` / `fleeRange` so types engage sooner; grow `stopDistance` / `band` / `*Deadzone` if you see vibrate at equilibrium.
- **Pack spacing:** `physics.enemyMinSep` (~28) — light lateral avoidance while moving so blobs don't stack. Chasers also shuffle apart at low speed while holding near the player; enemies outside their active behavior still hard-zero velocity (no drift).
- **Spawns:** `physics.pickSpawnPoint` places enemies inside arena bounds away from walls/player.
- **Known non-goals:** no full navigation/pathfinding around interior blocks (the ranger only strafes to restore LOS); other enemy types still lack attack hooks (ranger melee already drains the plague timer).

### World update
- Call **`world:update(dt)` every frame during gameplay** (via `physics.update`). Skipping this breaks collision and movement.

### Walls ↔ STI coordination
- Map colliders come from object layers via `game_map.addColliders` → `physics.addWallsFromObjects` (fountain ellipse today; rectangles when walls/props land).
- Playable clamp uses `game_map.getPlayableArea` → `physics.setPlayableArea`. Open plaza = **full map bounds** until outer walls exist.

### Map contract (`res/maps/map.lua`) — one infested courtyard

**One continuous Victorian/plague courtyard** on shared ornate cobble (`dungeon_tiles2`). Fountain is the eternal focal point (Nest B / Plague Well). West / center / east are **discernable by props + sparse decals**, not by foreign biome packs.

**Primary tilesets only** for floors / walls / decay:

| Tileset | firstgid | Role |
|---|---|---|
| `dungeon_tiles` | 1 | Props, soot/crack/wet decals, torches, ruin stubs |
| `dungeon_tiles2` | 553 | Full-map cobble floor + fountain stamp |

Do not reintroduce foreign biome packs (grass / hives / cartoon dungeon wallpaper). Districts are props + sparse decals on shared cobble.

| Layer | Type | Role |
|---|---|---|
| `Floor Layer` | tile | Every cell 30×24 non-zero cobble (no gid 0 voids) |
| `Decals A/B/C` | tile | A ash-market soot, B plague-well wet ring, C watch runners |
| `Props` | tile | Dense west clutter / open center / sparse east torches |
| `Fountain Layer` | tile | Center fountain stamp; perspective-sorted |
| `Circle Colliders` | object | Fountain oval (keep position/tiles) |
| `Rectangle Colliders` | object | Sparse solid props/ruins only — open flow |
| `Spawns` | object | `player_start`, nests, enemies |

**Art reset / re-export:**
```bash
love . -- --patch-nests
```

**Tiled:** edit `res/maps/map.tmx` → Export As `map.lua`. Keep fountain stamp + Circle Colliders ellipse.

### Courtyard collapse (`scripts/collapse.lua`)

As plague tolerance fails, floor tiles literally fall away — unique pressure vs closing walls.

| Rule | Detail |
|---|---|
| Telegraph | **1.0s** crack overlay + shake; death only after the tile falls |
| Drop | Tile quad falls off-screen; cell becomes a rimmed abyss hole (not flat black cobble) |
| Death | Player center on a **fallen** cell → **EXTRACTED** (abyss). Not a soft shove. |
| Protected | Fountain stamp (cols 13–16, rows 10–13) + nest pads (±1–2) never collapse |
| Fairness | Never starts cracking under the player (Chebyshev ≥ 2). Nest approach corridors + no-isolation BFS until late. Cap ~48% fallen. |
| Escalation | First wave at **t=20s** or ratio &lt; 0.85 (whichever first). Wave size/interval scale with `(1 - ratio)` + uncleansed nests. |
| Debug | **V** forces one crack near the player (not underfoot) |

### Plague timer (health)

- Module: `scripts/countdown.lua`, owned by gameplay as `state.countdown`.
- **Default duration: 90 seconds** (jam feel; tune ~60–120).
- Display: large **top-center** clock (`M:SS`, tenths under 10s) in Italianno cursive + thin segmented **Plague Tolerance** fuse (width = `getRatio()`, same color family — not a heart HP bar).
- Feedback: `:damage()` sets `damagePulse` (~0.4s) — digit/fuse flash + floating `-Xs`. Ratio < 0.15 → subtle screen-edge tint.
- Urgency: warmer tint below 25% remaining; subtle pulse below 10%.
- **Combat drain (done):** `player:onHitByEnemy` → `state:applyPlayerDamage(amount, source)` → `countdown:damage`. Default hit: **`PLAYER_HIT_DAMAGE_SECONDS` / `player.HIT_DAMAGE_SECONDS` = 5**. I-frames: **`PLAYER_HURT_IFRAME` / `player.HURT_IFRAME` = 0.6s** (`player.hurtIFrame`). Player sword → enemy does **not** drain the player timer.
- **Debug:** **H** → −3s (bypass i-frames); **G** → +5s; **V** → force one floor crack near the player.
- At 0: `state.extracted = true`, show **EXTRACTED**, freeze player/enemy AI, stop further damage; Esc still quits.

### Later (do not build full systems now)
- Other enemy types still lack attack hooks (only ranger melee drains today).
- Classes/`newSensor` helpers exist; no plague-meter bar / builds / classes this pass.

---

## Physics acceptance checklist

Pass/fail against a playable build:

- [x] World created with **zero gravity**; player does not fall or drift downward at rest
- [x] WASD **and** arrow keys drive **collider velocity**, not manual `pos` writes
- [x] Direction is **normalized before speed** (diagonal `|v|` ≈ cardinal `|v|`)
- [x] After update, sprite + camera match collider position (no visible desync)
- [x] **Walls block** the player; cannot walk through stub arena
- [x] Player ↔ Enemy soft contact (resistance ramps up; enemy nudge is capped at 3px with no momentum; nudge cannot shove enemies into Wall / OOB)
- [x] Kinematic enemies stay inside playable arena via clamp safety net (no wall embed / OOB eject)
- [x] **`PlayerAttack` / `EnemyHit` classes + `newSensor` helper** exist (full attack combat still out of scope)
- [x] Attack sensor toggled in-game with Enemy overlap detect (**Space/click swing**; console `[hit]` on `PlayerAttack`→`EnemyHit` enter; once per enemy per swing; enemy flash only — does not drain player timer)
- [x] Ranger melee → `state:applyPlayerDamage` → countdown drain + i-frames
- [x] `world:update(dt)` runs every gameplay frame
- [x] Debug draw of colliders toggled with **F1** / backtick without breaking camera
- [x] Wall-creation helper exists so STI can feed the same path later (`addWall` / `addWallsFromObjects`)

---

## How to test physics

1. Run the game: `love .` from the project root.
2. On load, console should print `[physics_selftest] ALL PASS` (or press **F2** to re-run).
3. Move with **WASD** and **arrow keys**. Confirm smooth top-down motion and **no gravity drift** when idle.
4. Walk into stub arena walls / interior blocks: walls stop immediately. Approach an enemy: movement progressively resists and contact may nudge it up to 3px, but holding input must never shove it farther, launch either actor, or push an enemy into a wall / outside the arena. Pin the purple ranger and green fleer against each outer wall and both interior blocks for 5+ seconds — no embed, no OOB.
5. Press **F1** (or **\`**): collider outlines appear for player + walls + **sensors** (`EnemyHit` always; `PlayerAttack` only during a swing, moving with the sword). HUD shows collider pos and **velocity magnitude `|v|`**.
6. **Sword direction test:** aim and swing twice. The first swing should travel from the player's relative left (behind) to right (in front), remain held there, then reverse direction and layer order on the second swing.
7. **Swing / hitbox test:** point the mouse toward an enemy, then press **Space** or **left-click**. The sword actor swings in that world-space direction. F1 shows `PlayerAttack` sweeping with the sword; idle = no attack sensor. On overlap enter, console prints `[hit] PlayerAttack entered EnemyHit (...)` (once per enemy per swing).
8. **Diagonal speed check:** hold **Right** only and note `|v|` in the debug HUD; then hold **Up+Right**. Magnitudes must match (within ~1%). If diagonal is ~1.41× faster, normalization is broken (FAIL).
9. Release movement: `|v|` returns to ~0; camera still follows the player.
10. Esc quits.
11. **Countdown / combat check:** big timer ticks at top-center. Get hit by the purple ranger — timer drops ~5s, UI flashes, ~0.6s i-frames prevent melt. **H** still subtracts 3s (ignores i-frames). Sword hits on enemies do **not** drain your timer. At 0 → **EXTRACTED**.

---

## Out of scope this pass

STI map polish, animation sets, plague meter bar, builds/classes, attacks for non-ranger types — enemy hit → countdown is wired for ranger melee.
