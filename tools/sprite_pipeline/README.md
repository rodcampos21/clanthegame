# Sprite pipeline (HD battle sprites)

How `assets/sprites/knight/*.png` were made. Sources live in `art/knight/`.

1. **Seed** — `art/knight/seed_pixel.jpg`: one AI-generated "pixel art" frame (Gemini app),
   approved by eye. `to_pixel.py` turns it into real pixel art: white background removed,
   palette quantised *before* downscaling, downscale by majority vote (keeps colours pure),
   pale halo removed, 1 px dark outline, placed with the feet at **(96, 190)** in a 192×192
   cell → `art/knight/knight_192.png` (192 px cell; placed 32 px lower in the 224 px sheets), palette locked in `art/knight/knight_palette.png`.
   ```
   python to_pixel.py seed_pixel.jpg knight_192.png --cell 192 --height 174 --colors 28 --save-palette knight_palette.png
   ```
2. **Idle** — by code, not AI (AI-redrawn idle frames "boil"): `make_idle.py knight_192.png idle.png`.
3. **Strips** — one AI strip per animation (`art/knight/strip_*.jpg`), attached seed as reference,
   single row with wide gaps. `process_pixel_strip.py` (run from a folder holding
   `knight_192.png` and `knight_palette.png`): splits frames (+ trails), ONE scale per strip,
   locked palette, aligns every frame to the same origin, widens the cell when the pose
   reaches forward (attack = 256 px), saves a sheet + preview GIF.
   ```
   python process_pixel_strip.py strip_attack.jpg attack  --frames 5 --ref 4
   python process_pixel_strip.py strip_hurt.jpg   hurt_h  --frames 3 --ref 2
   python process_pixel_strip.py strip_advance.jpg advance --frames 4 --rows 2 --scale-by head --anchor body
   python process_pixel_strip.py strip_death.jpg  death   --frames 5 --scale-by head --anchor mass
   python process_pixel_strip.py strip_defend.jpg defend  --frames 2 --ref 0
   python process_pixel_strip.py strip_skill.jpg  skill   --frames 6 --ref 0 --extra-colors 6 --cell-h 224
   python process_pixel_strip.py strip_victory.jpg victory --frames 4 --ref 0 --cell-h 224
   ```
   `--extra-colors` adds up to N colours that are far from the locked palette (the golden glow
   of the skill) for that animation only. Cells are 224 px tall (victory raises the sword above
   the 192 px cell); the 192-tall sheets were padded with 32 empty rows on top, origin (96, 222).
   Manual touches (documented, not scripted): the last attack frame and the first defend frame
   and the last skill frame were replaced by the exact idle frame (animations start/end in
   the idle pose); the first hurt frame was dropped (the AI forgot the sword) and the idle
   frame appended.
4. **Godot** — `godot --headless --path . --script res://tools/build_knight_frames.gd` builds
   `knight_frames.tres` (frame timings live in that script).

Rules that keep animations from "jumping": same origin (96, 190) in every sheet, one scale per
strip (head size for poses with no standing frame), locked palette for every animation.

## Backgrounds — `bg_to_grid.py`

AI "pixel art" backgrounds come as big images with fake ~8 px pixels. `bg_to_grid.py` turns
one into real pixel art on the game grid: reduce to a short palette (median cut, no dither),
then each grid cell becomes the most-voted color of its center.

```bash
python3 tools/sprite_pipeline/bg_to_grid.py art/backgrounds/battle_field_dusk.jpg \
    assets/sprites/battle_bg.png --w 320 --h 180 --colors 40 \
    --palette-out assets/sprites/battle_bg_palette.png
```

The palette goes to `BattleManager.background_palette` (battle.tscn) so the CRT filter (F2)
keeps the scenery colors.

## HUD — `make_hud.py`

`python3 tools/sprite_pipeline/make_hud.py art/hud/hud_sheet.jpg assets/ui/hud` samples every
piece of the AI HUD sheet on its native grid (~8 px AI pixels), removes the white background,
snaps all pieces to one 32-color palette and rebuilds the bar fills inside each frame's channel.
It prints the channel of every frame: copy `channel_x` / `channel_w` into `data/ui/bar_*.tres`.
The piece boxes (`BOXES`) belong to this sheet; a new sheet needs new boxes.
