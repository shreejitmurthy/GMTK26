# GMTK26 — Plague Doctor (LÖVE2D)

Top-down hack-and-slash jam game. **Countdown timer is health** (damage later drains that timer; physics only needs to detect damaging contact).

## What works today

- Grey empty room (`love.graphics` background)
- Player rectangle sprite in `main.lua` (actor/player pattern)
- Arrow-key movement stub: **manual** `pos.x` / `pos.y` mutation — no collision
- Camera follow (`lib/camera`) locked to player position
- Windfield / STI already vendored under `lib/` but **not wired into gameplay yet**

Physics will replace the manual position stub: input → Windfield velocity → collider position → draw/camera sync.

---

## Workstreams

| Workstream | Owner this pass | Notes |
|---|---|---|
| **Map loading (STI)** | Shree | Unless physics is blocked waiting on walls |
| **Animations** | Animator| Keep draw hooks simple; anims attach later |
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

### Source of truth for position
- The **Windfield collider** owns position.
- Each frame after `world:update(dt)`: sync actor draw/camera from `collider:getX()` / `getY()` (or equivalent).
- Do **not** mutate `pos` / `x` / `y` for movement; set collider linear velocity (or impulses) from input instead.

### Collision classes (create now — use these exact names)

| Class | Role |
|---|---|
| `Player` | Player body |
| `Enemy` | Enemy body |
| `Wall` | Static blockers |
| `PlayerAttack` | Player attack **sensor** (hitbox; no solid push) |
| `EnemyHit` | Enemy hurt / attack **sensor** (no solid push) |

Wire filters so solids block solids, and sensors detect without resolving as walls. Sensors must not shove the player/enemies.

### World update
- Call **`world:update(dt)` every frame during gameplay** (same path as actor updates). Skipping this breaks collision and movement.

### Walls ↔ STI coordination
- Until STI map loading lands, walls may be **hardcoded stubs** (e.g. room rectangle static colliders).
- Expose a small API, e.g. `addWall(x, y, w, h)` / `addWallsFromObjects(objects)`, so STI object-layer → static `Wall` colliders is a **drop-in later** without rewriting player movement.

### Later hook (do not build full systems now)
- Damaging contact (`Player` ∩ `EnemyHit`, or `PlayerAttack` ∩ `Enemy`) can later drain the countdown-health timer. Physics this pass: detect / fire enter-exit callbacks or equivalent; no plague-meter UI, builds, or class trees in this workstream.

---

## Physics acceptance checklist

Pass/fail against a playable build:

- [ ] World created with **zero gravity**; player does not fall or drift downward at rest
- [ ] Arrow (or WASD if already bound) movement drives **collider velocity**, not manual `pos` writes
- [ ] After update, sprite + camera match collider position (no visible desync)
- [ ] **Walls block** the player (and enemies if present); cannot walk through stubs
- [ ] Player ↔ Enemy solid contact does not tunnel through walls oddly (basic separation OK)
- [ ] **`PlayerAttack` / `EnemyHit` are sensors**: overlap events fire; they do **not** push bodies
- [ ] Attack sensor can be toggled on briefly (even a debug key) and overlap with Enemy is detectable
- [ ] `world:update(dt)` runs every gameplay frame
- [ ] Debug draw of colliders can be **toggled** (e.g. key) without breaking camera
- [ ] Wall-creation helper exists so STI can feed the same path later

---

## How to test physics

Once implemented (adjust keys only if README is updated to match code):

1. Run the game (`love .` from project root).
2. Move with **arrow keys** (and **WASD** if bound). Confirm smooth top-down motion, no gravity.
3. Walk into stub walls: player must stop / slide along edges, not pass through.
4. Toggle collider debug draw (recommended: **`F1`** or reuse existing `DEBUG` flag). Confirm Player / Wall / sensor shapes match expectation.
5. Trigger a short **PlayerAttack** sensor (recommended debug: hold **`J`** or space). Overlap an Enemy or a stand-in collider marked `Enemy` / `EnemyHit` — sensor overlap should report (print/log OK); neither body should get shoved by the sensor.
6. Stand still: player stays put (no drift). Release movement: velocity clears cleanly.
7. Camera still follows the player after physics sync.

---

## Out of scope this pass

STI map polish, animation sets, countdown UI, plague meter, builds/classes — except leaving clean contact hooks for damage → timer drain later.
