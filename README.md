# PackPlan

Plan how camping and EDC gear fits in your containers, before you start
stuffing things into a bag.

You keep a **library** of gear, measured once and tagged. A **plan** is one
container from that library plus the gear you want in it. PackPlan lays it out
and draws the result, so you can see what fits and what has to stay behind.

A bag is just gear that happens to hold other gear — switch on **holds other
gear** and you can build a plan around it. The same pouch can be gear inside
your pack *and* the container of its own EDC plan. (Its contents are not
counted when it is packed as gear; only its outside dimensions are.)

## How it works

**Dimensions.** Width and height are required, depth is optional. A container
with depth gets a **side view** next to the front view and a volume check;
without depth it stays a flat plan with a single view and an area check.

**Two views, three axes.** A plan with depth shows a **top** view (width across,
depth down — what you look at when you pack a tub) stacked above a **side** view
(depth across, height up). Between them they cover all three axes, which is why
dragging in either one is enough to position gear completely. They stack rather
than sit side by side because phones have far more vertical room.

Both are drawn at **one shared scale**, so the same container never reads as two
different sizes, and every shape on screen is comparable with every other.

**Swapping a view.** Each view has a swap button that transposes it — the same
two axes, turned a quarter turn on screen. A tall, narrow container makes for a
tall, narrow side view that wastes the whole screen; laying it flat is the only
way it reads on a phone. It changes nothing about where the gear sits, and is
remembered per view, per plan. Between them every axis is covered, which is why dragging in either
view is enough to position gear completely — drag left and right in the front
view to set its x, in the side view to set its depth.

Gear at different depths overlaps in the front view, the same way it would if
you looked into a real bag. The nearer piece is drawn on top and is the one you
grab.

**Auto-pack, then adjust.** *Auto-pack* lays the whole container out from
scratch and tells you what didn't fit. From there you drag pieces wherever you
actually want them — real packing has constraints the algorithm doesn't know
about, like fragile things going on top. Drags are clamped to the usable space
but clashes are allowed and flagged in red, because refusing a drag
mid-rearrange is miserable to use.

Adding one piece later slots it into free space instead of re-packing, so
adjustments you made by hand survive.

**Turning gear.** Select a piece and a turn button appears on each view's
top-right corner. It turns the gear a quarter turn *in that view* — swapping
whichever two axes that view shows, so there is never a question of which way
round it means. With the top and side views up, that is width against depth and
depth against height; two views cannot offer all three turns at once, so
standing a box up on its longest side can take more than one press. Turns that the container has
no room for are refused rather than left sticking out, and flat gear cannot be
stood on the 1 cm depth the app invents for it.

A hand turn applies to that one placement, so the same item stays as it was in
every other plan. Like a drag, it lasts until the next auto-pack. It also
deliberately ignores the gear's **can be turned** setting: that governs what
auto-pack may do on its own, and a turn by hand is you saying otherwise about
one piece.

**The library.** Gear is defined once and used in any number of plans, so
correcting a measurement corrects it everywhere. Tag things (`camp`, `cook`,
`edc`) and filter by tag — gear has to carry *every* selected tag, since
narrowing is what makes tags useful once you own a few dozen things. A plan can
hold two of the same item, and each copy is placed separately.

Deleting gear removes it from every plan that uses it. Deleting a *container*
also deletes the plans built on it, since a plan with nothing to pack into is
meaningless.

**Loadouts.** A named set of gear — "Overnight hike", "Summer minimal" — that
drops into any plan in one go, placing each piece in free space so anything you
arranged by hand stays put. You can also save what a plan currently holds as a
new loadout. A loadout is gear only, never a container, so it fits any bag.

**Tolerance.** Per plan, the slack you want left over. Every piece of gear is
treated as carrying a halo of half the tolerance on each side, so two pieces end
up a full tolerance apart while a container loses one tolerance from each
*dimension* rather than two: a 3 cm tolerance turns a 105 cm tub into 102 cm of
usable depth, which is what the number reads like. Zero lets things sit flush, which fits on paper but
rarely in the bag. The diagram outlines the margin it reserves. Changing it — or
swapping the plan's container, or resizing that container in the library —
re-packs, because it invalidates every position. A flat plan's
depth axis is a nominal 1 cm fiction, so tolerance deliberately does not eat
into it.

## Units

Everything is **stored in centimetres** and converted for display and input, so
switching units never changes your gear and nothing downstream of a text field
ever sees anything else.

Built in: cm, mm, inches (decimal). Beyond those you can define your own:

- **From a length** — "my hand is 19 cm".
- **From gear** — pick something in your library and a side of it to measure
  by. The length then *follows that gear*, so re-measuring the notebook you
  carry recalibrates everything you ever measured with it. If you delete the
  gear the unit survives, frozen at the length it last had.

A unit's own length is always entered in a built-in unit, never in itself.

## The packing algorithm

`lib/packer.dart`, pure Dart with no Flutter dependency.

Gear is sorted largest first. For each piece, every free corner opened up by
already-placed gear is tried in every allowed orientation, and the position
nearest the back-bottom-left corner wins. That fills the container in depth
layers, which is what keeps the two views legible rather than a jumble.

It is a heuristic, not an optimum — bin packing is NP-hard and an exact solver
would be overkill for a bag of camping gear. It is deterministic, so the same
plan always packs the same way.

Two details worth knowing:

- Gear marked **fixed orientation** is never turned. Everything else may be
  rotated to fit.
- Gear with **no depth** in a container that has one is assumed to be 1 cm
  deep, and is never stood on that invented edge — otherwise a 1 cm assumption
  would turn into a 1 cm-wide item.

## Layout

| File | What it holds |
| --- | --- |
| `lib/models.dart` | `GearItem`, `PlanRecord`, `PlanItem`, `Loadout`, `Plan` |
| `lib/units.dart` | Built-in and custom units, conversion and formatting |
| `lib/packer.dart` | Packing, tolerance, placement-issue detection |
| `lib/diagram.dart` | Coordinate mapping, painter, drag handling |
| `lib/store.dart` | State and every mutation, saves after each change |
| `lib/repository.dart` | The data file on disk, and schema migration |

A `PlanRecord` holds only ids: one container item, plus **entries** that each
point at a library item and carry their own id — which is what lets one plan
hold two of the same thing. `Plan` is a `PlanRecord` resolved against the
library, and is what the packer and the diagram actually work with. No
measurement is ever stored on a plan.

Plan y is measured **up from the container floor**, so a packed container
settles on its base instead of hanging from its lid. `ViewGeometry` does the
flip.

## Running it

```sh
flutter pub get
flutter run
flutter test
```

Saved data migrates forward automatically: v1 kept gear inside its container,
v2 moved gear into a shared library, v3 made containers library gear too.

Android only. Pushes and PRs build a debug APK — see `.github/workflows`.
