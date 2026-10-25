// Clan — pixel art source (claude-pxl DSL). Build:
//   node <claude-pxl>/bin/pxl.js build art/clan.px.js
// Outputs land in art/out/. tools/sync_art.sh copies them into assets/.
//
// One shared 16-colour palette ("clan16"). The Godot palette shader quantises the
// whole screen to the SAME strip (sprite "palette"), so in-engine colours never drift.
pal({
  k: "#1a1423", // ink / outline
  n: "#3b2d4f", // night purple
  p: "#6b4f8a", // violet
  g: "#5a9e4b", // grass
  G: "#3a6b3f", // grass dark
  l: "#9fd16b", // leaf light
  t: "#2c4a3a", // tree shadow
  d: "#8a6a4a", // dirt
  D: "#5e4632", // dirt dark
  s: "#f2c79a", // skin
  S: "#c98f6b", // skin shadow
  c: "#c8434b", // clan red
  C: "#842f3d", // clan red dark
  y: "#f5d26b", // gold
  b: "#4a8fd1", // blue
  w: "#f4f0e6", // white
})
ramps("kntGgl", "kDdy", "kCcy", "kSsw", "knpb")

// ---------- palette strip (read by the Godot palette shader) ----------
sprite("palette", "knpgGltdDsScCybw")

// ---------- hero (overworld, 3 facings x 2-frame walk) ----------
const HERO_DOWN = `
  ....hhh
  ..hhhhh
  .hhhHhh
  .hHssss
  .hssksS
  ..sssss
  ...SSSS
  ..ccCcc
  .cccCcc
  .sccCcc
  .sCCyCC
  ..cccCc
  ..BBB..`
pal({ h: "#5e4632", H: "#3b2d4f", B: "#3b2d4f" })
anim("hero_down", { mx: true, outline: "k", fps: 6 }, HERO_DOWN,
  frame(), frame(grid(2, 12, "B.."), grid(4, 12, "...")))
anim("hero_up", { mx: true, outline: "k", fps: 6 }, `
  ....hhh
  ..hhhhh
  .hhhhhh
  .hhhhhh
  .hhhhhh
  ..Hhhhh
  ...SSSS
  ..ccccc
  .cccCcc
  .scccCc
  .sCCyCC
  ..cccCc
  ..BBB..`,
  frame(), frame(grid(2, 12, "B.."), grid(4, 12, "...")))
anim("hero_side", { outline: "k", fps: 6 }, `
  ...hhhh...
  .hhhhhhh..
  hhhhhHhhh.
  hhhhsssss.
  .hhssskss.
  ..hsssssS.
  ...SSSSS..
  ...cccc...
  ..cccCcc..
  ..ccsCcc..
  ..CCyCCC..
  ..ccccCc..
  ..BB..BB..`,
  frame(), frame(grid(2, 12, ".BBBB.....")))

// ---------- enemy: slime (overworld + battle) ----------
anim("slime", { mx: true, outline: "k", fps: 4 }, `
  .......
  ....ppp
  ..ppbpp
  .ppbbpp
  .pppppp
  pppkwpp
  pppkkpp
  npppppp
  .nnnnnn`,
  frame(), frame(grid(0, 0, `
  .......
  .......
  ....ppp
  .ppbbpp
  ppbbppp
  pppkwpp
  pppkkpp
  npppppp
  .nnnnnn`)))
sprite("slime_red", { base: "slime", swap: { p: "c", n: "C", b: "s" } })

// ---------- status icons over enemies ----------
sprite("icon_alert", { outline: "k" }, `
  .y.
  .y.
  .y.
  ...
  .y.`)
sprite("icon_question", { outline: "k" }, `
  www
  ..w
  .ww
  ...
  .w.`)

// ---------- overworld tiles (16x16) ----------
sprite("tile_grass", { w: 16, h: 16 }, rect(0, 0, 16, 16, "g"),
  px(3, 4, "l"), px(4, 3, "l"), px(11, 10, "l"), px(12, 9, "l"), px(7, 13, "G"), px(13, 2, "G"))
sprite("tile_path", { w: 16, h: 16 }, rect(0, 0, 16, 16, "d"),
  px(2, 5, "D"), px(9, 11, "D"), px(13, 3, "D"), px(6, 14, "y"))
sprite("tile_flowers", { base: "tile_grass" },
  px(4, 10, "y"), px(5, 9, "w"), px(10, 4, "c"), px(11, 5, "w"))
sprite("tree", { w: 16, h: 18, outline: "k" },
  circ(8, 7, 7, "G"), circ(7, 6, 5, "g"), circ(5, 4, 2, "l"),
  rect(6, 13, 4, 5, "D"), shade([8, 13, 4, 5]))
sprite("rock", { w: 14, h: 10, outline: "k" },
  ellipse(7, 5, 6, 4, "D"), ellipse(5, 4, 3, 2, "d"), px(4, 3, "y"), hline(2, 8, 11, "k"))

// ---------- battle backdrop (320x180) ----------
scene("battle_bg", { w: 320, h: 180, bg: "n" },
  grad(0, 0, 320, 110, "n", "p"),
  layer("hills", ellipse(60, 120, 110, 40, "t"), ellipse(250, 125, 120, 45, "t")),
  layer("ground", { y: 110 }, rect(0, 0, 320, 70, "G"), rect(0, 0, 320, 3, "g"),
    ellipse(80, 40, 50, 10, "t"), ellipse(235, 35, 50, 10, "t")),
  px(40, 20, "w"), px(120, 12, "w"), px(210, 30, "w"), px(290, 14, "w"), px(170, 8, "y"))

sheet("overworld", ["hero_*", "slime*", "icon_*", "tile_*", "tree", "rock"], { pad: 1 })

// ---------- UI font atlas (pxl's built-in 3x5 font) ----------
// 64 glyphs (ASCII 32..95) in a 16x4 grid of 4x6 cells. scripts/ui/pixel_font.gd
// slices this into a Godot FontFile at runtime, so every label uses the same pixels.
sprite("font_atlas", { w: 64, h: 24 }, (c) => {
  for (let i = 0; i < 64; i++) {
    const ch = String.fromCharCode(32 + i)
    c.text((i % 16) * 4, Math.floor(i / 16) * 6, ch, "w")
  }
})
