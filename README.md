# GMTK26 — Plague Doctor (LÖVE2D)

Top-down hack-and-slash jam game. **Countdown timer is health** (damage later drains that timer; physics only needs to detect damaging contact).

## What works today

- Grey room + camera follow
- Windfield world (`scripts/physics.lua`): **zero gravity**, collision classes, stub arena walls
- Player (`scripts/player.lua`): WASD + arrows, **normalized** diagonal velocity, collider is position source of truth
- **F1** / backtick toggles collider debug draw; **F2** re-runs console PASS/FAIL selftest
- STI / animations / combat / countdown UI: not wired yet

Physics loop: input → normalize → `setLinearVelocity` → `world:update(dt)` → sync draw/camera from collider.

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
| `Enemy` | Enemy body |
| `Wall` | Static blockers |
| `PlayerAttack` | Player attack **sensor** (hitbox; no solid push) |
| `EnemyHit` | Enemy hurt / attack **sensor** (no solid push) |

Helpers: `physics.newPlayerCollider`, `physics.newEnemyCollider`, `physics.addWall` / `addWallsFromObjects`, `physics.newSensor`.

### World update
- Call **`world:update(dt)` every frame during gameplay** (via `physics.update`). Skipping this breaks collision and movement.

### Walls ↔ STI coordination
- Stub arena walls via `physics.spawnTestArena` until STI lands.
- STI object-layer → static `Wall` colliders should call `physics.addWallsFromObjects(objects)` (drop-in).

### Later hook (do not build full systems now)
- Damaging contact can later drain the countdown-health timer. Physics this pass: classes + sensor helper ready; no plague-meter UI.

---

## Physics acceptance checklist

Pass/fail against a playable build:

- [x] World created with **zero gravity**; player does not fall or drift downward at rest
- [x] WASD **and** arrow keys drive **collider velocity**, not manual `pos` writes
- [x] Direction is **normalized before speed** (diagonal `|v|` ≈ cardinal `|v|`)
- [x] After update, sprite + camera match collider position (no visible desync)
- [x] **Walls block** the player; cannot walk through stub arena
- [x] Player ↔ Enemy solid contact (idle `Enemy` bodies in arena; walk into them — they block like walls)
- [x] **`PlayerAttack` / `EnemyHit` classes + `newSensor` helper** exist (full attack combat still out of scope)
- [ ] Attack sensor toggled in-game with Enemy overlap detect (combat pass)
- [x] `world:update(dt)` runs every gameplay frame
- [x] Debug draw of colliders toggled with **F1** / backtick without breaking camera
- [x] Wall-creation helper exists so STI can feed the same path later (`addWall` / `addWallsFromObjects`)

---

## How to test physics

1. Run the game: `love .` from the project root.
2. On load, console should print `[physics_selftest] ALL PASS` (or press **F2** to re-run).
3. Move with **WASD** and **arrow keys**. Confirm smooth top-down motion and **no gravity drift** when idle.
4. Walk into stub arena walls / interior blocks: player must stop or slide, not pass through.
5. Press **F1** (or **\`**): collider outlines appear for player + walls. HUD shows collider pos and **velocity magnitude `|v|`**.
6. **Diagonal speed check:** hold **Right** only and note `|v|` in the debug HUD; then hold **Up+Right**. Magnitudes must match (within ~1%). If diagonal is ~1.41× faster, normalization is broken (FAIL).
7. Release movement: `|v|` returns to ~0; camera still follows the player.
8. Esc quits.

---

## Out of scope this pass

STI map polish, animation sets, countdown UI, plague meter, builds/classes, full attack combat — except leaving sensor/class hooks for damage → timer drain later.
