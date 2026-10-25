# Agent Sprite Forge in this project

[Agent Sprite Forge](https://github.com/0x0funky/agent-sprite-forge) (MIT, commit `5324342`) is
installed as **project skills** in `.claude/skills/`, so Claude Code sessions opened in this repo
load them automatically:

| Skill | Use it for |
|---|---|
| `generate2dsprite` | a character's master still, then idle/walk/attack... sets, pixel finish, Godot SpriteFrames export |
| `video2dsprite` | turning image-to-video clips (or clips you supply) into keyed, looped sprite animations |
| `generate2dmap` | maps and tilesets, exported for Godot / Tiled / LDtk |
| `generate2dmedia` | the router every image/video request goes through (`route_media.py`), plus `forge_doctor.py` |
| `codeart2d` | code-drawn art, the fallback when no image model is available |

## Setup

```sh
python -m pip install -r tools/sprite-forge-requirements.txt   # numpy, Pillow, scipy
# video steps also need ffmpeg 5.1+ on PATH
python .claude/skills/generate2dmedia/scripts/forge_doctor.py   # shows which routes work
```

The forge **does not draw by itself**: images and clips come from an image/video model. Give it one route:

* an API key in the environment: `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, `ARK_API_KEY` or `FAL_KEY`, or
* a signed-in Codex CLI or Grok CLI on the same machine.

Without a route it falls back to `codeart2d` (code-drawn), which is the same kind of art we make
with claude-pxl in `art/`.

## Example request

```text
Use $generate2dsprite to make a master still of the Clan hero: a young knight with spiky white
hair, teal eyes, silver pauldrons, a blue tabard with a gold emblem, brown belt and a blue cape.
Side view, facing right, pixel finish, 48x64. Then make idle and walk, and export for Godot.
```

## Updating

```sh
git clone https://github.com/0x0funky/agent-sprite-forge && cd agent-sprite-forge
python tools/install_skills.py --apply --dest ../clanthegame/.claude/skills
python tools/install_skills.py --check --dest ../clanthegame/.claude/skills   # drift report
```
