# cloth_effect

https://github.com/user-attachments/assets/351b7e9f-13d2-4a07-9446-87031d721f4a

Turn any widget into a sheet of fabric taped to the wall.

Drag it and the fabric lifts, folds and flows back. Drag hard and hold, and the
tape tears out and the whole screen falls away.

It is a real simulation, not a canned animation: a 3D Verlet mass-spring cloth,
rendered as a lit, depth-sorted mesh textured with a snapshot of your widget.

| | |
|---|---|
| **Drag** | the fabric lifts off the wall, folds, and flows back over about half a second |
| **Drag hard and hold** | the tape tears out and the screen falls away |
| **`reset()`** | tapes it back up, flat |

## Usage

```dart
import 'package:cloth_effect/cloth_effect.dart';

final ClothController controller = ClothController();

Cloth(
  controller: controller,
  child: const MyScreen(),
)
```

That is the whole setup. Nothing else is required — a hard enough drag takes the
screen off the wall on its own.

The child can be anything, including an image. For the common case of hanging a
picture there is a shorthand:

```dart
Cloth.image(
  controller: controller,
  image: const AssetImage('assets/poster.jpg'),
  fit: BoxFit.cover,
)
```

Images with visible structure — lines, edges, texture — show the folds far
better than a flat gradient does.

The controller is there when you want to drive it from code:

```dart
controller.pullPins();  // weaken the tape so the next tug takes it down
controller.knockOff();  // take it off the wall now, no pointer needed
controller.reset();     // tape it back up, flat
controller.disturb();   // resume simulating, e.g. from a shake handler

controller.pinsIn;      // false once the tape is weakened or torn out
controller.dismissed;   // true once the sheet has fallen clear
```

`ClothController` is a `ChangeNotifier`, so surrounding UI can rebuild when the
sheet comes down or settles.

## While it is flat, it is still your widget

The child is only rasterized while it is moving. At rest, `Cloth` paints the real
widget, so text stays crisp and taps still work. The first drag past the touch
slop snapshots it and swaps in the mesh; when the fabric settles it returns to
exactly flat and hands control back.

That means you can wrap a whole screen and lose nothing when nobody is playing
with it.

While the fabric is in motion the child stops receiving pointer events, so a
button being torn off the wall cannot be tapped on its way down. Interaction
returns the moment the sheet settles.

## Tuning

Every knob lives on `ClothSimulation`, reachable through the controller:

```dart
final ClothController controller = ClothController(
  simulation: ClothSimulation(cols: 32, rows: 48)
    ..anchorToughness = 1200
    ..bendStiffness = 0.2,
);
```

| Field | Default | Effect |
|---|---|---|
| `cols`, `rows` | 28, 42 | Mesh resolution. Finer folds cost proportionally more; below about 24x36 it stops reading as fabric. |
| `gravity` | 2400 | Logical px/s². |
| `wallSupport` | 0.06 | How much of its weight fabric lying against the wall keeps. Raise it and the sheet hangs looser. |
| `wallCling` | 0.0015 | Cling to the wall, so the sheet settles exactly on its rest position. |
| `pinnedFriction` | 0.86 | Damping while it hangs. Heavy, so it settles without overshooting. |
| `freeFriction` | 0.995 | Damping once it is falling. |
| `iterations` | 8 | Constraint passes per substep. Lower starts to look rubbery. |
| `maxStretch` | 0.04 | Hard ceiling on weave stretch. The biggest single lever on cloth versus rubber. |
| `bendStiffness` | 0.14 | Fold wavelength. Higher is broader and smoother. |
| `grabRadius` | 38 | Size of a pinch, in logical px. Too small pulls the fabric into a needle. |
| `grabDepth` | 130 | How far toward the viewer a pinch lifts the fabric. |
| `grabStiffness` | 0.08 | How firmly the pinch pulls. |
| `anchorToughness` | 2500 | Load one anchor survives. The knob to reach for if the tear feels wrong. |
| `anchorYield` | 0.9 | Load an anchor shrugs off entirely. |
| `pinReleaseFraction` | 0.35 | How much of the top edge must tear before the rest gives way. |

The simulation steps at a fixed 120 Hz with an accumulator, so behaviour does not
change with display refresh rate. It costs roughly 1.4 ms per frame for the
default 1247 nodes in the debug VM, several times less in release.

## How it works

The sheet is simulated in 3D. The wall is the plane `z == 0`, the viewer sits at
negative z, and the top edge is taped to the wall. Fabric that is only allowed to
deform in the plane has nowhere to put the material it gathers when you pull it,
so it stretches and reads as rubber; given a third axis, compressed cloth buckles
out of plane into the folds real fabric makes, and those folds can be lit and can
occlude each other.

Everything else follows from that:

- **Rendering.** The child is rasterized into a texture with `SnapshotWidget`,
  then drawn with `Canvas.drawVertices` over a perspective-projected mesh.
  Lighting uses a real surface normal per node, expressed relative to how a flat
  sheet would light, so an undisturbed sheet renders as exactly the original
  picture. Highlights go on as a second additive pass, since modulating a texture
  can only darken it. Triangles are depth-sorted each frame so folds occlude.
- **Inextensibility.** Real fabric stretches a few percent and then refuses, so
  it gathers into folds instead and stores no energy to twang back with. A hard
  ceiling on stretch, plus a pinch that pulls with a spring rather than a hard
  constraint, is what keeps it from behaving like elastic.
- **Tearing.** Each anchor carries whatever the weave hangs on it and wears out
  under sustained load; its share then moves to its neighbours, so a tear spreads
  along the top edge.
- **Support.** A sheet lying flat against a wall is mostly held up by the wall,
  not by the tape. Without that the tape carries everything and peels off under
  the sheet's own weight. Pulling a fold clear of the wall is what loads it.

## Limitations

- `SnapshotWidget` cannot rasterize platform views, so a child containing a map,
  web view or camera preview will not deform.
- The effect is pointer-driven. It does not currently expose a keyboard or
  semantics affordance, so do not make it the only way to perform an action.

## Example

```sh
cd example
flutter run
```

A player screen taped to a wall, with a message behind it you can only read by
tearing the screen down. There is no button for that — drag the artwork hard and
hold. `RESET` puts it back.

Tap the artwork to swap between painted art and a photo, and tap the title to
see that the child really is still live while the sheet hangs flat.

## Tests

```sh
flutter test
```

The suite covers the simulation's state machine — that an ordinary drag deforms
the sheet and flows back without tearing, that a hard sustained drag rips it off,
that the weave stays near-inextensible under load — and the widget's contract:
the child stays live and tappable at rest, stops receiving pointers while the
fabric moves, and the whole thing disposes cleanly mid-animation.
