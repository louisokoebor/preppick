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

The design system uses **DM Sans**. The font files are not bundled yet, so
`AppTypography.fontFamily` is `null` and the platform default is used. To adopt
DM Sans, add the font assets to `pubspec.yaml` and set that one constant — no
other font is substituted in the meantime.
