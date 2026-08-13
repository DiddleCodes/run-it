# run-it.

Campus deliveries, powered by peers already heading your way.

RUN-It connects students to in-school canteens, cafés, and shops — and to
each other. Every student can request a delivery or flip into runner mode
and earn by carrying an order along a route they're already walking.

## Stack

- **Flutter** (Dart 3) — iOS + Android, web enabled for fast local preview
- **Riverpod** — state management
- **go_router** — navigation
- **Firebase** — auth, Firestore, storage
- **flutter_animate** — micro-interactions and motion

## Structure

```
lib/
  core/
    theme/       # colors, typography, motion constants, light+dark ThemeData
    widgets/      # shared UI: buttons, text fields, the runner brand mark
    routing/      # go_router route table
  features/
    splash/
    onboarding/
    auth/
    campus/
```

Each feature is self-contained under `presentation/`; add `domain/` and
`data/` layers as backend integration lands.

## Design system

- **Type:** GeneralSans (display/headlines) + Satoshi (body/UI) — both
  bundled locally under `assets/fonts/`.
- **Color:** one warm amber brand hue carried across both themes. Light mode
  is a deliberate warm-ivory palette, not an inverted dark theme.
- **Motion:** every animation pulls duration/curve constants from
  `lib/core/theme/app_motion.dart` so the app moves as one system.
- Follows the device's system light/dark setting by default
  (`ThemeMode.system` in `main.dart`); a manual override belongs in Settings
  once that screen exists.

## Getting started

```bash
flutter pub get
flutter run                # iOS/Android device or simulator
flutter run -d chrome       # fast web preview during UI work
```

## Status

Splash, onboarding, phone/email auth, and campus selection are built.
Home, ordering, live tracking, runner mode, and the vendor/admin surfaces
are next.
