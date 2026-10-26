# Clan — Architecture of the overworld-encounter prototype

Godot **4.7.2**, GDScript, GL Compatibility renderer, 320×180 virtual resolution (1280×720 window).

**Two stretch modes.** The overworld uses `viewport` stretch (everything rendered on the 320×180
grid, scaled ×4 — pixel-perfect). The battle switches the window to `canvas_items` stretch in
`BattleManager._enter_tree()` (restored on exit): layout, UI and the 16-colour art keep the same
320×180 coordinates and ×4 look, but HD battle sprites (`CombatantStats.battle_frames`, drawn for
1280×720, shown at scale 0.25) render at full resolution. Pixel-perfect HD needs a window that is a
multiple of 1280×720 (720p, 1440p, 2160p); at 1080p the ×6 factor shows HD art at 1.5×.

## 0. What the two reference repos actually are (and how they are used)

| Repo | What it is | How this project uses it |
|---|---|---|
| [sekaikx/ForgeSkills](https://github.com/sekaikx/ForgeSkills) | 20 *agent skills* (procedures + Python tools) for building games: gameplay systems, Godot pipeline, testing, VFX/impact, verification. It is **not** a Godot skill-tree library. | Its rules shape the code: spec-first systems (PURPOSE/INPUTS/STATE/RULES/FEEDBACK blocks in the scripts), one self-reporting script per system with `debug_state()`, events/signals instead of cross-calls, balance in data (`.tres`), telegraphed enemy attacks, hit confirmation (flash + shake + hitstop), input-map actions, and an automated loop test per system that is proven to fail when a rule breaks. |
| [crsolver/claude-pxl](https://github.com/crsolver/claude-pxl) | "Pixel art as code": a Node CLI that renders `.px.js` files to PNGs, sprite strips and sheets. It ships **no Godot shaders**. | Every sprite, tile, the battle backdrop, the 16-colour palette strip and the UI font atlas are generated from `art/clan.px.js`. The shaders are written for this project in the same spirit: integer pixel grid, ordered dither instead of alpha, colours snapped to the same palette strip pxl exports. |

The skill/ability system (`scripts/skills/`) is therefore this project's own, built the ForgeSkills way.

## 1. Scene tree

```
root (Window)
├── GameState            autoload  scripts/autoload/game_state.gd
│                        hero Combatant, overworld snapshot, defeated ids, pending encounter
├── BattleTransition     autoload  scripts/autoload/battle_transition_manager.gd
│   ├── CrtLayer (CanvasLayer 90)  └── CrtRect (ColorRect + palette_crt.gdshader)    [F2]
│   └── FxLayer  (CanvasLayer 100) └── FxRect  (ColorRect + battle_transition.gdshader)
│
└── <current scene>  — one of:

    Overworld (Node2D)                       scenes/overworld/overworld.tscn
    ├── Map (Node2D, OverworldMap)           ground drawn from an ASCII layout
    ├── Actors (Node2D, y_sort_enabled)      trees/rocks (StaticBody2D) are added here at runtime
    │   ├── Player (CharacterBody2D)         scenes/overworld/player.tscn
    │   │   ├── Sprite (Sprite2D, 2-frame strips)
    │   │   ├── Collision (feet box)
    │   │   ├── StrikeArea (Area2D, mask = enemies)
    │   │   └── Camera (Camera2D, limits = map)
    │   ├── SlimePath / SlimeGrove / RedSlime (OverworldEnemy)   scenes/overworld/overworld_enemy.tscn
    │   │   ├── Sprite
    │   │   ├── Collision (feet box, layer = enemies)
    │   │   ├── Icon (Sprite2D: "?" / "!")
    │   │   ├── SightRay (RayCast2D, mask = world)   line-of-sight check
    │   │   └── ContactArea (Area2D, mask = player)  touch → encounter
    │   └── (trees, rocks)
    └── HUD (CanvasLayer): Status panel, Hint, Toast, Debug [F1]

    Battle (Node2D, BattleManager)           scenes/battle/battle.tscn
    ├── Background (Sprite2D, pxl scene)
    ├── PartySlots/Hero, EnemySlots/E0..E2 (Marker2D)
    ├── Actors (BattleActorView per Combatant, built at runtime)
    ├── FX (damage numbers)
    └── UI (CanvasLayer): Banner, TurnOrder, Log, HeroPanel (HP/MP PixelBars), Commands (buttons built from skill data)
```

Physics layers: 1 `world`, 2 `player`, 3 `enemies`. Player and enemies do not block each other; contact is detected by areas so a collision never "pushes" a battle away.

## 2. The skill system (`scripts/skills/`)

| File | Role |
|---|---|
| `skill_data.gd` | `SkillData` Resource: kind, target, power, MP cost, cooldown, accuracy, optional status + chance, skill-tree fields (`requires`, `unlock_cost`), passive status. |
| `status_effect_data.gd` | `StatusEffectData` Resource: duration, ATK/MAG/DEF/SPD multipliers, `skip_turn`, damage-per-turn, `persists_outside_battle`. |
| `combatant_stats.gd` | Base stats + skill list + battle sprite. |
| `combatant.gd` | Runtime HP/MP/cooldowns/statuses/turn clock. The hero's instance lives in `GameState`, so it crosses scene changes unchanged. |
| `skill_executor.gd` | The one pipeline: **validate → pay MP + start cooldown → per target: accuracy → amount → apply → status roll → events**. Player and AI both use it. |
| `turn_queue.gd` | Charge-time turns: lowest clock acts, then `clock += 100 / SPD`. Speed statuses reorder turns immediately. |
| `encounter_rules.gd` | Overworld advantage → battle opening (see §3). |

Data lives in `data/skills`, `data/statuses`, `data/combatants`. New skill or status = new `.tres`, no code.

### Combat balance spec (edit the spec, then the data)

```
Hero      HP 60  ATK 9  MAG 8  DEF 5  SPD 12
Slime     HP 22  ATK 7  MAG 5  DEF 3  SPD 9
Red Slime HP 34  ATK 9  MAG 7  DEF 5  SPD 11

physical = power + ATK − DEF/2      magic = power + MAG − DEF/4      ±10% spread
Hero Attack vs Slime  ≈ 4 + 9 − 1.5 = 11.5   → 2 hits to kill (TTK target: 2)
Slime Tackle vs Hero  ≈ 3 + 7 − 2.5 = 7.5    → hero survives ~8 hits
```

## 3. Overworld encounters

### Enemy perception (`overworld_enemy.gd`)

```
PATROL ──awareness ≥ 0.3──▶ SUSPICIOUS ──awareness = 1──▶ ALERT ──0.45 s telegraph──▶ CHASE
   ▲                            │  ▲                                                      │
   └────── awareness = 0 ───────┘  └──────────── lost sight 2.2 s ───────────────────────┘
```

* Vision cone: distance 84 px, ±38°, blocked by `world` bodies via `SightRay`.
* Awareness fills faster the closer the player is; **sneaking (Shift) halves it** and mutes "hearing" (22 px, 360°).
* Feedback: cone colour, "?" / "!" icon, 12 px awareness meter, hop on ALERT.

### Advantage rules (`encounter_rules.gd`)

| Event | Condition | Result | Applied in battle |
|---|---|---|---|
| Player strike (Z) | enemy **not** ALERT/CHASE **and** player behind it | `PLAYER` | hero clock = 0, **Surprise** (+50% SPD, +25% ATK, 2 turns); enemies **Stunned** (lose first turn) |
| Enemy touches player | enemy in CHASE **and** it comes from behind the player | `ENEMY` | enemy clocks = 0, hero **Off-Guard** (DEF ×0.5, SPD ×0.75, 2 turns); can't run for 2 turns |
| Anything else | frontal strike, aware enemy, walking into a patroller | `NEUTRAL` | normal clocks |

"Behind" = `facing · direction_to_other < −0.25` (rear ~150° arc), so a side hit is not a back attack.

### Hand-off

```
OverworldEnemy._trigger_battle(adv)
  └─▶ BattleTransition.start_battle(enemy_id, encounter, adv, player_pos, player_facing)
        ├─ GameState.begin_encounter(...)           # snapshot + enemy list + advantage
        ├─ freeze tree, 3-frame flash (gold/red/white by advantage)
        ├─ shatter + pixelate OUT (0.75 s)
        ├─ change_scene_to_file(battle)              # BattleManager._ready reads GameState
        └─ pixelate IN (0.45 s), unfreeze
BattleManager._finish(result)
  └─▶ BattleTransition.return_to_overworld(result)
        ├─ GameState.finish_encounter(result)        # drops battle-only statuses, marks defeat,
        │                                            # keeps HP/MP/cooldowns/Poison, 1.5 s grace
        └─ dither-iris transition → Overworld._ready restores position/facing
```

## 4. Shader integration guide

All three shaders are in `shaders/` and work on the **virtual 320×180 grid**, so every effect step is exactly one art pixel.

1. **Project settings (pixel snap)** — already in `project.godot`:
   `stretch/mode = viewport`, `stretch/scale_mode = integer`, `default_texture_filter = Nearest`,
   `snap_2d_transforms_to_pixel = true`, `snap_2d_vertices_to_pixel = true`. Sprites use
   `centered = false` with whole-pixel offsets, battle sprites use integer `scale = 2`.
2. **Palette** — `assets/sprites/palette.png` (16×1) is exported by pxl from the same `pal()` used
   for the art. Both screen shaders take it as `palette_tex`; change the palette in `clan.px.js`,
   rebuild, and the shaders follow.
3. **`battle_transition.gdshader`** on a full-rect `ColorRect` in a top `CanvasLayer`, reading
   `hint_screen_texture`. Drive `progress` 0→1 (cover), swap scenes, 1→0 (reveal).
   `mode = 0` shatter + pixelate (encounter), `mode = 1` dither iris (return). `flash` gives the hit frame.
   Passes: integer-block pixelate → palette snap with stepped darkening → 16 px shards dropping out
   with a Bayer-4×4 dithered edge.
4. **`palette_crt.gdshader`** — optional always-on pass (F2): Bayer dither into the palette,
   thin scanlines, vignette. Lives on layer 90, under the transition.
5. **`hit_flash.gdshader`** — per-sprite on `BattleActorView`: `flash = 1` paints the silhouette
   white for a few frames (no alpha blending).
6. **HD battles + CRT** — during a battle with HD sprites, `BattleTransition.set_display_grid()`
   runs the CRT pass on the output grid and adds the HD palettes (`battle_frames_palette`) to
   clan16, so F2 does not crush HD art into 4×4 blocks of 16 colours.

## 4b. HD battle sprites

`CombatantStats.battle_frames` (SpriteFrames) replaces the pixel strip when set. All cells are
224 px tall and share one origin, the point between the feet: `battle_frames_origin = (96, 222)`.
`BattleActorView` maps game events to animations:

| Event | Animation |
|---|---|
| waiting | `idle` (`defend` while Guarding) |
| skill with `approach = true` (Attack, Power Slash) | `advance` run to `MELEE_GAP` px in front of the target → `SkillData.user_anim` → stays there while damage resolves → runs back (`advance`, mirrored) |
| skill without approach (Fire; Heal for future healers) | `user_anim` in place (`skill`) |
| hit | `hurt` + flash + shake |
| KO | `death` (holds the last frame) |
| victory | `victory` (holds the cheer) |

Which animation a skill uses is data: `SkillData.user_anim` / `approach` in `data/skills/*.tres`. Sheets, frame
timings and how they were produced: `assets/sprites/knight/`, `tools/build_knight_frames.gd`,
`tools/sprite_pipeline/README.md`.

To use the transition elsewhere (cutscenes, doors): call `BattleTransition._run(scene_path, mode, flash_color)`
or copy its tween; the shader has no scene-specific code.

## 4c. Battle HUD (pixel bars)

The bars and status icons come from one AI sheet (`art/hud/hud_sheet.jpg`) turned into real pixel
art by `tools/sprite_pipeline/make_hud.py` → `assets/ui/hud/` + `hud_palette.png` (merged into the
CRT palette through `BattleManager.hud_palette`).

| Piece | Where |
|---|---|
| `HudBarStyle` (`data/ui/bar_hp/bar_mp/bar_short.tres`) | frame + fill + trail textures, channel columns |
| `PixelBar` (`scripts/ui/pixel_bar.gd`) | draws frame → trail → fill, `art_scale` 0.5 grid px per art px (2 screen px at 720p) |
| HeroPanel | HP and MP bars + numbers for `party[0]` |
| `BattleActorView.hp_bar` | short bar under each enemy (party members use the panel) |
| `StatusEffectData.icon` | shield (Guard), star (Stunned) before the status name |

Rules: fill width is whole art pixels and never 0 while the value is above 0; on a loss the fill
drops at once and the orange trail holds `TRAIL_DELAY` 0.35 s, then slides in `TRAIL_TIME` 0.4 s
(tweens run in game time, so hitstop freezes them); a gain snaps both.

## 5. Verification

```
godot --headless --path . res://tests/test_runner.tscn          # 166 checks, exit code 0/1
xvfb-run godot --path . --rendering-driver opengl3 res://tests/capture.tscn -- /tmp/shots
```

`test_runner` (166 checks) covers the HUD bars (art aligned to the channel, palette, whole-pixel fill, damage trail timing), the battle background (320x180, colors in the CRT palette), HD frames (every animation, shared origin), the HD battle view
(stretch mode, 1:1 scale, idle/defend/attack/death), Guard lasting until the next turn, the skill pipeline, cooldowns, status modifiers, advantage geometry, both
openings, persistence across battle, a full automated battle (loop test), and three overworld
scenarios (cone → suspicious → alert → chase; back strike = PLAYER; chased from behind = ENEMY).
Flipping the sign of `BEHIND_DOT` makes it fail, so the test is checking the rule.
`capture` drives a scripted run and saves screenshots of each stage.
