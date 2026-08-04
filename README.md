# PackPlan

Plan how camping and EDC gear fits in your containers, before you start
stuffing things into a bag.

You describe a **container** — a pack, a dry bag, a pouch, a pocket — and the
**goods** you want in it. PackPlan lays the goods out and draws the result, so
you can see what fits and what has to stay behind.

## How it works

**Dimensions.** Width and height are required, depth is optional, everything in
centimetres. A container with depth gets a **side view** next to the front view
and a volume check; without depth it stays a flat plan with a single view and
an area check.

**Two views, three axes.** The front view looks at the container head on (width
across, height up). The side view looks at it from the left (depth across,
height up). Between them every axis is covered, which is why dragging in either
view is enough to position a good completely — drag it left and right in the
front view to set its x, in the side view to set its depth.

Goods at different depths overlap in the front view, the same way they would if
you looked into a real bag. The nearer one is drawn on top and is the one you
grab.

**Auto-pack, then adjust.** *Auto-pack* lays the whole container out from
scratch and tells you what didn't fit. From there you drag pieces wherever you
actually want them — real packing has constraints the algorithm doesn't know
about, like fragile things going on top. Drags are clamped to the container but
overlaps are allowed and flagged in red, because refusing a drag mid-rearrange
is miserable to use.

Adding one good later slots it into free space instead of re-packing, so
adjustments you made by hand survive.

## The packing algorithm

`lib/packer.dart`, pure Dart with no Flutter dependency.

Goods are sorted largest first. For each one, every free corner opened up by an
already-placed good is tried in every allowed orientation, and the position
nearest the back-bottom-left corner wins. That fills the container in depth
layers, which is what keeps the two views legible rather than a jumble.

It is a heuristic, not an optimum — bin packing is NP-hard and an exact solver
would be overkill for a bag of camping gear. It is deterministic, so the same
plan always packs the same way.

Two details worth knowing:

- A good marked **fixed orientation** is never turned. Everything else may be
  rotated to fit.
- A good with **no depth** in a container that has one is assumed to be 1 cm
  deep, and is never stood on that invented edge — otherwise a 1 cm assumption
  would turn into a 1 cm-wide item.

## Layout

| File | What it holds |
| --- | --- |
| `lib/models.dart` | `GearContainer`, `Good`, `Placement`, JSON round-trip |
| `lib/packer.dart` | Packing and placement-issue detection |
| `lib/diagram.dart` | Coordinate mapping, painter, drag handling |
| `lib/store.dart` | State and every mutation, saves after each change |
| `lib/repository.dart` | The plan file on disk |

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
