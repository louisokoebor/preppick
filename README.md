# PrepPick

PrepPick turns the meals a household already likes into a weekly meal-prep plan
and a consolidated shopping list.

Core weekly workflow:

```
Select meal count → Plan This Week → Generated Plan → Swap if needed
→ Confirm Plan → Shopping List
```

V1 is local-first: it works fully offline, with SQLite as the source of truth.

## Getting started

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

## Architecture Rules

PrepPick uses one layering, consistently:

```
Model → Service → Provider → UI
```

- UI must not call SQLite directly.
- Providers must not contain SQL.
- Services own business logic and persistence calls.
- Models represent product/domain data.
- SQLite is the local source of truth.
- Use UUID strings as persistent IDs.

No repositories, use cases, BLoC, Riverpod, GetX, Clean Architecture layers,
dependency-injection frameworks or Supabase are used in V1.

When adding a feature, ask: what is the model, which service owns the logic,
which provider owns the state, and which UI consumes that state? If UI or a
provider starts holding SQL or planning logic, move it down into a service.

## Project structure

```
lib/
  main.dart          app entry point only
  app/               app bootstrap and routes
  models/            domain data
  services/          business logic and persistence
  providers/         screen state
  ui/                screens, grouped by flow
  widgets/           shared widgets
  theme/             design tokens and ThemeData
  utils/             helpers

test/                mirrors lib/
```

## Design tokens

All colours, spacing, radii and typography live in `lib/theme/`. Screens should
reference the tokens (`AppColors`, `AppSpacing`, `AppRadius`, `AppTypography`)
rather than hard-coding values.

The design system uses **Manrope**. The font is bundled in `assets/fonts` at the
three weights the type scale uses — 400 Regular, 500 Medium, 600 SemiBold — so it
renders offline with no network fetch and no `google_fonts` dependency. The
weights were instanced from the upstream Manrope variable font; `OFL.txt` in the
same folder carries the SIL Open Font License it ships under.

If a new text style needs a weight outside 400/500/600, add that static to
`assets/fonts` and declare it in `pubspec.yaml` rather than letting the platform
synthesise it.
