# The Land of Ezerian 2

The Land of Ezerian, made again with richer graphics. It is still a Mac-native,
single-player, turn-based RPG in the spirit of **Ultima VI** in which, for now, you
explore: walk an endless, randomly generated land of meadows, forests, rivers,
mountains, towns, taverns and caves, and talk to the people you meet. There is no
combat and there are no items yet.

The look follows the high-resolution Ultima VI remake in the reference screenshots
(kept in `screens/`, which git ignores): 32-pixel tiles with painterly textures, thick
walls seen in Ultima's leaning overhead view, hip roofs that lift away when you step
indoors, ink-outlined objects, and torchlit nights.

![](docs/screenshot.png)

![](docs/night.png)

![](docs/wilds.png)

![](docs/people.png)

## Build and run

Requires macOS 13 or later and Swift 5.9+ (Xcode or the Command Line Tools).

```bash
./build_app.sh
```

```bash
open "build/Land of Ezerian 2.app"
```

During development you can also run it straight from SwiftPM:

```bash
swift run -c release Ezerian
```

## Controls

| Key | Action |
| --- | --- |
| Arrow keys / WASD | Walk (hold two arrows to walk diagonally) |
| Q E Z C, numpad | Walk diagonally |
| Click / hold on the map | Walk toward the pointer |
| Right-click | Look at whatever (or whoever) is under the pointer |
| T, or walk into someone | Talk to them |
| 1–6, 0 or Esc | In a conversation: choose what to say, or leave |
| Space | Wait a turn |
| L | Look at the tile ahead |
| M | Map of the lands you have explored (+/- or scroll to zoom) |
| G | Show region borders on the map view |
| H or ? | Help |
| ⌘N | Begin a new world |
| ⌘S | Save (the game also saves automatically) |

A new game (first launch or ⌘N) begins by asking your character's name; it appears in
the side panel, under the Avatar's portrait, and is kept in the save file.

Walk into a door to go inside, into a sign to read it, and into a cave mouth to go
underground. A ladder brings you back up. The Avatar glides from tile to tile, but the
game is still turn-based: every step is a turn of two minutes.

## People

Ezerian is home to four races: **humans**, **elves**, **dwarves** and **orcs**. Every
NPC has a friendliness score from -100 (extremely hostile) to 100 (adoring), drawn from
a bell curve around their race's average: humans 25, elves 0, dwarves -25, orcs -50.
The score falls into five moods — hostile, unfriendly, neutral, friendly, adoring —
which decide how they answer you.

* **Where they live:** keepers in every shop, tavern, inn, smithy, temple and home
  (dwarves favour the forge), patrons in the taverns, townsfolk in the streets, elves
  in the woods, dwarf prospectors in the hills, orc bands at campfires and in caves,
  and travellers on the roads.
* **Each turn** they go about their business: most wander a little, hostile ones close
  in on you and growl, adoring ones come over to wave.
* **Talking:** walk into someone or press T. The conversation window shows their
  portrait, race, trade, mood and score. Ask their **name** (hostile folk won't say),
  their **job**, the **news** (friendly folk point you to nearby towns and landmarks),
  or **directions** to an inn (friendly folk are exact, neutral ones vague, hostile ones
  lie). A **compliment** raises their friendliness (elves like flattery most, orcs
  least), an **insult** lowers it, and an NPC who loathes you (-85 or below) won't
  talk at all.
* Each race speaks its own way, from courtly elves ("thou", "mortal") and gruff dwarves
  ("aye", "surface-dweller") to blunt orcs ("pinkskin").
* People, where they stand and how they feel about you are kept in the save file.

## How the world works

* The world is a grid of **64×64-tile regions**. A region is generated the first time
  it is needed (as it comes into view, just before you cross its border) and is then
  kept: walk back and you find exactly the same map.
* The natural landscape comes from continuous noise fields seeded per world, so
  coasts, rivers and forests flow across region borders without seams. Towns,
  buildings and other sites are laid on top using a per-region random stream.
* Neighbouring regions agree on where roads cross their shared border, so the road
  network continues from one region to the next.
* **Outdoors:** grassland, scrub, forest, hills, mountain ranges, swamps, beaches,
  rivers, lakes and sea; towns of cobbled streets with a fountain or well in the
  plaza, lamp posts and stocks; farms with wheat, cabbages, beehives and scarecrows;
  shrines in a ring of standing stones, ruins, graveyards, orchards and campsites.
* **Indoors:** taverns (bar, kegs, tables, fireplace, harpsichord), inns with guest
  rooms, shops, smithies, armouries, healers, temples and homes. Every building faces
  south, so its door is on the side you see. From outside you see its roof; step
  through the door and the roofs lift off, as in Ultima VII.
* **Underground:** cave mouths in the mountainsides lead to caverns lit only by the
  Avatar's torch.
* **Day and night:** the clock starts at 8 in the morning. Dusk turns the land amber,
  then blue; torches, lamp posts, hearths and lit windows glow in the dark.
* The world, including every region you have seen, is saved to
  `~/Library/Application Support/Land of Ezerian 2/world.plist`.

## Graphics

Everything is drawn by the program itself; there are no image files. The screen is
960×540 pixels of art, scaled up with crisp square pixels, with the words set in real
fonts (Luminari and Iowan Old Style) at the display's full resolution on top.

* **The projection.** As in Ultima VI and VII, a point at height *z* is drawn *z*
  pixels up and to the left of its place on the ground, so tall things lean that way
  and you see the south and east faces of walls, cliffs and roofs.
* **Ground, walls, roofs and rock** are a height field with a column per ground
  pixel. `Ground.swift` marches a ray down through it for every screen pixel and
  keeps what it hit (material, texture coordinates, shading, height) in a cached
  32×32 "G-buffer" per tile; a frame then only looks up texels. Walls are thin slabs
  along the tile edges, giving the thin dark caps, brick and timber faces, and 45°
  corner seams of the screenshots. Mountains are fields of domed boulders with cliffs;
  cave walls are black on top with striated faces.
* **Terrain borders** are rounded and ragged: each tile's terrain fades out from the
  tile's centre and noise settles where one meets the next, so roads wind and grass
  frays over their edges.
* **Textures** (`Textures.swift`) are painted procedurally: grass of thousands of
  blades, dirt of shaded clods, cobbles from Voronoi cells, planks, flagstones,
  bricks, carpets with gold borders, shingle, slate, thatch and tiled roofs, and
  animated water with drifting crests and surf.
* **Objects** (`Art*.swift`) are modelled from spheres, boxes, cylinders, cones and
  capsules and ray traced by `Modeler.swift` into shaded, ink-outlined sprites with
  soft shadows, in several random variants each. Every sprite pixel keeps its height,
  which along a screen ray is exactly its nearness to the eye, so objects, walls and
  the Avatar hide each other correctly; when something hides the Avatar, a faint
  silhouette still shows where it is.
* **Light** (`Lighting.swift`) is computed on a coarse grid and blended smoothly:
  daylight, dawn and dusk tints, moonlight, and warm pools of light that stay inside
  the room they are in.

## Project layout

| File | Purpose |
| --- | --- |
| `main.swift`, `AppDelegate.swift`, `GameView.swift` | App, window, menus, keyboard, mouse and gliding movement |
| `Game.swift` | Avatar movement, NPC turns, conversations, messages, game clock |
| `NPC.swift`, `Dialogue.swift` | Races, friendliness, where people live, what they say |
| `World.swift`, `Tiles.swift` | Regions, lazy generation, terrain and objects |
| `WorldGen.swift`, `Settlements.swift`, `Buildings.swift`, `Sites.swift`, `Roads.swift`, `Caves.swift`, `Names.swift`, `Noise.swift` | World generation |
| `Screen.swift`, `TextRenderer.swift` | Screen layout, side panel, overlays, text |
| `MapRenderer.swift`, `Ground.swift`, `Lighting.swift`, `Framebuffer.swift` | Rendering |
| `Textures.swift`, `Modeler.swift`, `SpriteBank.swift`, `Art*.swift` | Procedural art (`ArtPeople.swift`: the four races) |
| `SaveGame.swift` | Saving and loading |
| `DevTools.swift` | Command-line developer tools |

## Developer tools

The executable has a few command-line modes that need no window:

```bash
swift run -c release Ezerian --selftest
```

Checks that regions are kept when you walk away and back, that every building in the
starting town can be walked into through a door in its south wall, that roofs lift
indoors, that each race's friendliness averages out right, that conversations follow
the NPC's mood, that caves lead down and back up, that every object has a sprite, that keys
reach the game, and that saves round-trip.

* `--render out.png [--seed N] [--walk "E5 N3"] [--hour 21] [--show map,help,grid,name] [--scale 2]`
  renders a screenshot. A walk can also contain `find:<feature>` (for example
  `find:shrine` or `find:t.forest`) to jump next to the nearest one, `npc:orc` to stand
  beside the nearest orc, and `talk` and `say:N` to hold a conversation.
* `--sheet out.png` draws every sprite; `--textures out.png` every texture.
* `--overview out.png [--radius R]` draws a one-pixel-per-tile map of the generated world.
* `--bench` times start-up art, world generation and rendering.
