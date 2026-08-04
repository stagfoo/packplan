# PackPlan

Plan how camping and EDC gear fits in your containers, before you start
stuffing things into a bag.

You keep a **library** of gear, measured once and tagged. You describe a
**container** — a pack, a dry bag, a pouch, a pocket — and drop gear into it.
PackPlan lays it out and draws the result, so you can see what fits and what
has to stay behind.

## How it works

**Dimensions.** Width and height are required, depth is optional. A container
with depth gets a **side view** next to the front view and a volume check;
without depth it stays a flat plan with a single view and an area check.

**Two views, three axes.** The front view looks at the container head on (width
across, height up). The side view looks at it from the left (depth across,
height up). Between them every axis is covered, which is why dragging in either
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

**The library.** Gear is defined once and used in any number of containers, so
correcting a measurement corrects it everywhere. Tag things (`camp`, `cook`,
`edc`) and filter by tag — gear has to carry *every* selected tag, since
narrowing is what makes tags useful once you own a few dozen things. A
container can hold two of the same item, and each copy is placed separately.

**Recipes.** A named set of gear — "Overnight hike", "Summer minimal" — that
drops into any container in one go, placing each piece in free space so
anything you arranged by hand stays put. You can also save what a container
currently holds as a new recipe.

**Tolerance.** Per container, the gap kept clear of every wall *and* between
any two pieces of gear. Zero lets things sit flush, which fits on paper but
rarely in the bag. The diagram outlines the margin it reserves. Changing it
re-packs the container, because it invalidates every position. A flat plan's
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
| `lib/models.dart` | `GearItem`, `GearContainer`, `ContainerEntry`, `Recipe`, `Plan` |
| `lib/units.dart` | Built-in and custom units, conversion and formatting |
| `lib/packer.dart` | Packing, tolerance, placement-issue detection |
| `lib/diagram.dart` | Coordinate mapping, painter, drag handling |
| `lib/store.dart` | State and every mutation, saves after each change |
| `lib/repository.dart` | The data file on disk, and schema migration |

A container holds **entries**, not gear — each entry points at a library item
and carries its own id, which is what lets one container hold two of the same
thing. `Plan` is a container with its entries resolved against the library, and
is what the packer and the diagram actually work with.

Plan y is measured **up from the container floor**, so a packed container
settles on its base instead of hanging from its lid. `ViewGeometry` does the
flip.

## Running it

```sh
flutter pub get
flutter run
flutter test
```

Android only. Pushes and PRs build a debug APK — see `.github/workflows`.
