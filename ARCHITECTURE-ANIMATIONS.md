# Hanamimi (花耳) — Animations & Mascot Buddies (guide)

> How Hanamimi's animations work and how to add more — new mascot
> expressions, and **code-drawn animal "buddies"** (an indie dog, a cat,
> a rabbit that hops on the download bar, cats & dogs playing). No
> artist, no Rive/Lottie, no image assets: everything is geometry drawn
> with `CustomPainter` and driven by a `Ticker`.
>
> The **rabbit on the download bar is the shipped worked example** —
> `lib/ui/components/mascot/buddies.dart` + its use in
> `downloads_screen.dart`. Copy it to build the rest.

---

## 1. The two-layer pattern (everything follows it)

Every animated thing in Hanamimi is split in two:

1. **A painter** — a `CustomPainter` that draws one *static frame* from a
   set of parameters (pose, phase, amplitude). No time, no state; given
   the same inputs it draws the same picture. Pure and cheap.
2. **An animation host** — a `StatefulWidget` with a **`Ticker`** that
   advances a phase/time each frame (~60 fps) and feeds it to the
   painter via `setState` → `CustomPaint`.

That's it. The mascot is `MascotPainter` (painter) + `HanamimiMascot`
(host). A buddy is `RabbitPainter` (painter) + `DownloadRabbit` (host).
Adding an animation = write a painter, drive it from a host.

### Shared conventions

- **Design space**: paint in a fixed local coordinate box (the mascot
  uses ~120×132; the rabbit uses 32×32), then the painter scales to the
  real `size`. Draw at nice round numbers, let scale handle the rest.
- **Palette**: reuse `HanaColors` (`mascot_painter.dart`) — `blush`,
  `tan`, `earDark`, `muzzle`, `eye`, `nose`, `tongue` — so buddies match
  the mascot's look. Add new named colors there, don't hardcode hex.
- **Baseline & facing**: buddies draw feet on the bottom edge, facing
  right, and stay within `size` so a host can place them anywhere.
- **Motion vocabulary** (what makes it feel alive, all in `HanamimiMascot`):
  - **squash & stretch** — scale about the feet by `1 ± k·hop`.
  - **secondary motion** — parts lag the body (the mascot's ears trail
    the head bob; the rabbit's ears flop back at the top of a hop).
  - **eased transitions** — never snap; lerp toward targets each frame.
  - **idle life** — the mascot blinks every 4–7 s; give buddies small
    randomized idles so they're never frozen.

---

## 2. The mascot, as reference

`mascot_painter.dart`
- `MascotPainter.paint` composes `_drawBody`, `_drawEars`, `_drawHead`,
  `_drawFace`, `_drawAccessory`. Inputs: a `MascotPose` (`EyeKind`,
  `BrowKind`, `MouthKind`, `tilt`), `bob`, `bodyBounce`, `sleepPhase`,
  `accessory`.
- Expressions are **data**: the `_poses` map in `hanamimi_widget.dart`
  maps each `MascotState` (idle/playing/paused/changing/sleeping/loading)
  to a `MascotPose`. Add an expression by adding a pose.

`hanamimi_widget.dart` (`HanamimiMascot`)
- A single `Ticker` drives `_time`; from it: the **blink scheduler**
  (`_nextBlinkAt`, random 4–7 s), the **amplitude head-bop** (`_bob`
  from `widget.amplitude`, i.e. the visualizer), **lagging ears**
  (secondary motion), **eased tilt** toward the pose's target, and the
  **floating zzz** while sleeping.
- Amplitude comes from `amplitudeProvider` (low-band visualizer energy),
  so the mascot bounces to the beat for free.

---

## 3. The buddy system — `buddies.dart`

```dart
abstract class BuddyPainter extends CustomPainter {
  const BuddyPainter(this.phase);   // 0..1 looped animation phase
  final double phase;
  @override bool shouldRepaint(covariant BuddyPainter old) => old.phase != phase;
}
```

The **rabbit** (`RabbitPainter`) draws body/head/ears/tail/face and reads
`phase` through `hop = sin(phase·π)` (0→1→0 per cycle):
- `lift = hop·9` — height off the baseline.
- `squash = 1 − hop·0.12` — stretch at the apex (scaled about the feet).
- ears `sway = hop·6` — flop backward as it springs.
- back foot `tuck` — rises toward the belly mid-hop.

The **host** (`DownloadRabbit`) owns a `Ticker` that advances `phase`
once per `hopPeriod`, and a `LayoutBuilder` that positions the rabbit at
`x = progress · width` so it **rides the fill edge** of the bar. Used in
`downloads_screen.dart`:

```dart
if (downloading) DownloadRabbit(progress: task.progress),
LinearProgressIndicator(value: task.progress, ...),
```

---

## 4. Recipe: add a new buddy (dog, cat, …)

1. **Draw the painter.** In `buddies.dart`, add
   `class DogPainter extends BuddyPainter`. Sketch it in a small design
   box (e.g. 32×32), feet on the bottom, facing right. Use `HanaColors`.
   Start static (ignore `phase`), get the silhouette right, then wire
   one motion: e.g. a tail wag = rotate the tail path by
   `sin(phase·2π)·angle`; a trot = two legs out of phase.
   - The **indie dog**: start from the mascot's own `_drawBody`/ears in
     `mascot_painter.dart` (it's already a beagle) — copy the paths, drop
     the cap/face detail, add a wagging tail and a trot cycle.
   - The **cat**: slimmer body, upright triangle ears, a long tail that
     curls (`quadraticBezierTo` with a phase-driven control point), a
     slow blink and an occasional stretch.
2. **Drive it.** Either reuse a host like `DownloadRabbit` (rename/param)
   or add a generic one:
   ```dart
   class BuddyStage extends StatefulWidget {
     final BuddyPainter Function(double phase) build;
     final Duration period;  // one loop
     // Ticker advances phase 0..1; CustomPaint(painter: build(phase))
   }
   ```
   Prefer one shared `BuddyStage` so every buddy gets the same 60 fps
   loop and you only write painters after this.
3. **Place it.** Drop the host wherever it belongs (see §5).
4. **Respect reduce-motion.** Gate idle loops on
   `MediaQuery.disableAnimations` (the mascot already hides motion under
   reduce-motion) — keep a calm static frame.

## 5. Ideas & where they live

| Idea | Painter(s) | Host / placement |
|---|---|---|
| 🐇 Rabbit hops on the download bar | `RabbitPainter` ✅ | `DownloadRabbit` in the active-download card ✅ |
| 🐶 Indie dog trots across the mini-player | `DogPainter` | a thin host pinned to the mini-player, x looping |
| 🐱 Cat naps on the Now-Playing art corner | `CatPainter` (sleep + ear-twitch) | a `Positioned` on `now_playing_screen` |
| 🐶🐱 Dog & cat *playing* | both painters + a shared `phase` | one `BuddyStage`; drive both from the same phase so their bounces interleave (chase = x-offset that swaps lead) |
| 🎉 Buddy pops in on a liked song | any, one-shot | trigger an `AnimationController` (not a loop) from the heart tap |

"Playing together" is just **two painters sharing one phase**: give each
an x-offset and a bounce derived from the same `phase`, offset by π, and
they'll chase/bounce in sync — no physics needed.

## 6. Costs & rules

- CustomPainter at 60 fps over a tiny box is cheap; keep `shouldRepaint`
  tight (compare only `phase`/inputs) and don't allocate `Path`s you can
  precompute. The mascot runs one Ticker total — prefer **one shared
  Ticker/host** over many.
- Never block the UI thread; painters must stay pure (no IO, no async).
- Everything stays **code-drawn** — if an artist ever appears, a buddy
  can swap its `paint` for an image/Rive without touching hosts, because
  the painter is the only thing that knows how it's drawn.

## 7. Milestone

Folded into future polish: **buddies pack** — indie dog, cat, and the
dog×cat "playing" pair, plus the shipped download-bar rabbit; a shared
`BuddyStage` host; reduce-motion honored. *Verified: the rabbit hops
along the real download bar, tracking progress (shipped).* 

---

*Document version: 0.1. Companion to the mascot code in
`lib/ui/components/mascot/`.*
*Last updated: July 2026.*
