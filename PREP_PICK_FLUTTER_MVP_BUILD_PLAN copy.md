# PrepPick Flutter MVP Build Plan

## 1. Purpose

PrepPick turns the meals a household already likes into a weekly meal-prep plan and a consolidated shopping list.

The MVP should stay focused on the core weekly workflow:

**Select meal count → Plan This Week → Generated Plan → Swap if needed → Confirm Plan → Shopping List**

Secondary flows:

- Meal Library
- Meal Detail
- Import Meal History
- Review Import
- Plan History

The product should be local-first for V1.

---

## 2. Agreed Technical Stack

### App
- Flutter
- Dart
- Provider for state management
- SQLite for local persistence
- UUIDs for IDs

### Later
- Supabase for:
  - authentication
  - multi-device sync
  - shared household accounts

Supabase is **not required for the first usable MVP**.

---

## 3. Architecture

Use the architecture:

```text
UI
↓
Provider
↓
Service
↓
SQLite
```

Or, in the terminology used throughout the project:

```text
Model → Service → Provider → UI
```

### Responsibilities

#### Model
Represents the main things PrepPick understands.

Examples:
- MealFamily
- MealVariant
- Ingredient
- MealIngredient
- WeeklyPlan
- WeeklyPlanItem
- ShoppingItem
- AppSettings

#### Service
Contains business logic and database access.

Examples:
- MealService
- PlanningService
- ShoppingService
- SettingsService
- ImportService

#### Provider
Owns screen state and coordinates services.

Examples:
- MealProvider
- PlannerProvider
- ShoppingProvider
- SettingsProvider
- ImportProvider

#### UI
Contains screens and reusable widgets.

The UI should **never call SQLite directly**.

---

## 4. Recommended Packages

Add only what is needed for the MVP.

```yaml
dependencies:
  flutter:
    sdk: flutter

  provider: ^6.1.0
  sqflite: ^2.3.0
  path: ^1.9.0
  uuid: ^4.5.0
  intl: ^0.19.0
```

Optional later:

```yaml
  supabase_flutter:
  shared_preferences:
  file_picker:
```

Do not add Supabase until the core local workflow is working.

---

## 5. Recommended Folder Structure

```text
lib/
  main.dart

  app/
    app.dart
    routes.dart

  models/
    meal_family.dart
    meal_variant.dart
    ingredient.dart
    meal_ingredient.dart
    weekly_plan.dart
    weekly_plan_item.dart
    shopping_item.dart
    app_settings.dart

  services/
    database_service.dart
    meal_service.dart
    planning_service.dart
    shopping_service.dart
    settings_service.dart
    import_service.dart

  providers/
    meal_provider.dart
    planner_provider.dart
    shopping_provider.dart
    settings_provider.dart
    import_provider.dart

  ui/
    planner/
      select_meal_count_screen.dart
      plan_this_week_screen.dart
      generated_plan_screen.dart
      swap_meal_sheet.dart

    shopping/
      shopping_list_screen.dart

    meals/
      meal_library_screen.dart
      meal_detail_screen.dart
      meal_edit_screen.dart

    import/
      import_history_screen.dart
      review_import_screen.dart

    history/
      plan_history_screen.dart

  widgets/
    prep_button.dart
    prep_header.dart
    bottom_navigation.dart
    meal_slot_card.dart
    meal_card_compact.dart
    meal_card_library.dart
    shopping_item_tile.dart
    category_badge.dart
    filter_chip.dart
    search_input.dart
    week_range_card.dart
    quantity_selector.dart

  theme/
    app_colors.dart
    app_spacing.dart
    app_radius.dart
    app_typography.dart
    app_theme.dart

  utils/
    date_utils.dart
    id_utils.dart
```

---

## 6. Design Tokens to Mirror from Figma

The current Figma file already contains a usable visual system.

Keep the same naming in Flutter where practical.

### Core colours

```dart
class AppColors {
  static const backgroundApp = Color(0xFFF8F7F3);
  static const backgroundSurface = Color(0xFFFFFFFF);
  static const backgroundMuted = Color(0xFFF0F1EE);

  static const textPrimary = Color(0xFF171A16);
  static const textSecondary = Color(0xFF6E746D);
  static const textTertiary = Color(0xFFB9BDB7);
  static const textInverse = Color(0xFFFFFFFF);

  static const borderDefault = Color(0xFFB9BDB7);
  static const borderSubtle = Color(0xFFF0F1EE);

  static const actionPrimary = Color(0xFF1E9A5A);
  static const actionPrimaryHover = Color(0xFF36A86D);
  static const actionPrimaryPressed = Color(0xFF147A45);
  static const actionSecondary = Color(0xFFE6F4EC);

  static const categoryBreakfast = Color(0xFFFFF0DC);
  static const categoryLunch = Color(0xFFE6F4EC);
  static const categoryDinner = Color(0xFFEFECFF);
  static const categoryShopping = Color(0xFFFDEBE8);
}
```

### Spacing scale

```text
4
8
12
16
20
24
32
40
48
```

### Radius scale

```text
8
12
16
20
24
999
```

### Typography

Use DM Sans to match the current design direction.

Recommended app styles:

```text
Display Large      32 / 38 / SemiBold
Heading H1         28 / 34 / SemiBold
Heading H2         24 / 30 / SemiBold
Heading H3         20 / 26 / SemiBold
Title Large        18 / 24 / SemiBold
Title Medium       16 / 22 / SemiBold
Body Large         16 / 24 / Regular
Body Medium        14 / 20 / Regular
Body Small         12 / 18 / Regular
Label Large        14 / 20 / Medium
Label Medium       12 / 16 / Medium
Caption            11 / 16 / Regular
```

---

## 7. Domain Models

## MealFamily

Represents a core meal concept.

Examples:
- Lou Lou Spaghetti
- Fried Rice
- Burgers
- Paninis

```dart
enum MealType {
  breakfast,
  lunch,
  dinner,
}

class MealFamily {
  final String id;
  final String name;
  final MealType mealType;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

---

## MealVariant

Represents a version of a meal family.

Examples:
- Lou Lou Spaghetti + Chicken
- Lou Lou Spaghetti + Turkey
- Lou Lou Spaghetti + Salmon

```dart
class MealVariant {
  final String id;
  final String mealFamilyId;
  final String name;
  final String? protein;
  final DateTime? lastPlannedAt;
  final int timesPlanned;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

---

## Ingredient

```dart
class Ingredient {
  final String id;
  final String name;
  final String? category;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

Suggested categories:

```text
produce
protein
pantry
chilled
frozen
household
specialist
other
```

---

## MealIngredient

Links a meal variant to an ingredient.

```dart
class MealIngredient {
  final String id;
  final String mealVariantId;
  final String ingredientId;
  final double? quantity;
  final String? unit;
  final int? baseServings;
}
```

Do not invent missing quantities.

If quantity is unknown, store it as `null`.

---

## WeeklyPlan

```dart
enum PlanStatus {
  draft,
  confirmed,
}

class WeeklyPlan {
  final String id;
  final DateTime weekStart;
  final PlanStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
}
```

---

## WeeklyPlanItem

```dart
enum MealSlot {
  breakfast,
  lunch,
  dinner1,
  dinner2,
}

class WeeklyPlanItem {
  final String id;
  final String weeklyPlanId;
  final String mealVariantId;
  final MealSlot slot;
}
```

The first MVP can support:

```text
0–1 breakfast
0–N lunches
0–N dinners
```

The current UI supports configurable meal counts.

---

## ShoppingItem

```dart
class ShoppingItem {
  final String id;
  final String weeklyPlanId;
  final String ingredientId;
  final String name;
  final double? quantity;
  final String? unit;
  final String category;
  final bool isChecked;
  final bool isManual;
}
```

---

## AppSettings

```dart
class AppSettings {
  final int breakfastCount;
  final int lunchCount;
  final int dinnerCount;
}
```

Future settings may include:

- household size
- default servings
- pantry items
- preferred specialist shop
- dietary preferences

---

## 8. SQLite Schema

Use UUID strings as primary keys.

Do not use auto-increment IDs.

---

### meal_families

```sql
CREATE TABLE meal_families (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  meal_type TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

---

### meal_variants

```sql
CREATE TABLE meal_variants (
  id TEXT PRIMARY KEY,
  meal_family_id TEXT NOT NULL,
  name TEXT NOT NULL,
  protein TEXT,
  last_planned_at TEXT,
  times_planned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (meal_family_id)
    REFERENCES meal_families(id)
);
```

---

### ingredients

```sql
CREATE TABLE ingredients (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

---

### meal_ingredients

```sql
CREATE TABLE meal_ingredients (
  id TEXT PRIMARY KEY,
  meal_variant_id TEXT NOT NULL,
  ingredient_id TEXT NOT NULL,
  quantity REAL,
  unit TEXT,
  base_servings INTEGER,
  FOREIGN KEY (meal_variant_id)
    REFERENCES meal_variants(id),
  FOREIGN KEY (ingredient_id)
    REFERENCES ingredients(id)
);
```

---

### weekly_plans

```sql
CREATE TABLE weekly_plans (
  id TEXT PRIMARY KEY,
  week_start TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  confirmed_at TEXT
);
```

---

### weekly_plan_items

```sql
CREATE TABLE weekly_plan_items (
  id TEXT PRIMARY KEY,
  weekly_plan_id TEXT NOT NULL,
  meal_variant_id TEXT NOT NULL,
  slot TEXT NOT NULL,
  FOREIGN KEY (weekly_plan_id)
    REFERENCES weekly_plans(id),
  FOREIGN KEY (meal_variant_id)
    REFERENCES meal_variants(id)
);
```

---

### shopping_items

```sql
CREATE TABLE shopping_items (
  id TEXT PRIMARY KEY,
  weekly_plan_id TEXT NOT NULL,
  ingredient_id TEXT,
  name TEXT NOT NULL,
  quantity REAL,
  unit TEXT,
  category TEXT NOT NULL,
  is_checked INTEGER NOT NULL DEFAULT 0,
  is_manual INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (weekly_plan_id)
    REFERENCES weekly_plans(id)
);
```

---

### settings

For MVP, a simple key/value table is sufficient.

```sql
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

---

## 9. DatabaseService

File:

```text
lib/services/database_service.dart
```

Responsibilities:

- open SQLite database
- create tables
- handle schema versions
- expose database instance
- migrations later

Suggested skeleton:

```dart
class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // open database
    // run onCreate
    // run migrations later
  }
}
```

No provider should contain SQL.

---

## 10. MealService

File:

```text
lib/services/meal_service.dart
```

Responsibilities:

```dart
Future<List<MealVariant>> getAllMeals();
Future<List<MealVariant>> getMealsByType(MealType type);
Future<MealVariant?> getMealById(String id);

Future<void> addMeal(...);
Future<void> updateMeal(...);
Future<void> deleteMeal(String id);

Future<List<MealIngredient>> getIngredientsForMeal(String mealVariantId);
```

This service is also responsible for loading meal families and variants.

---

## 11. SettingsService

File:

```text
lib/services/settings_service.dart
```

Responsibilities:

```dart
Future<AppSettings> getSettings();
Future<void> saveSettings(AppSettings settings);
```

The Select Meal Count screen should persist its choices here.

---

## 12. PlanningService

File:

```text
lib/services/planning_service.dart
```

This contains the key product logic.

Required methods:

```dart
Future<WeeklyPlan> generateWeeklyPlan(AppSettings settings);

Future<WeeklyPlanItem> swapMeal({
  required String planId,
  required String planItemId,
});

Future<void> confirmPlan(String planId);

Future<List<WeeklyPlan>> getPlanHistory();
```

---

## 13. Recommendation Logic

Start simple and deterministic.

For each required slot:

1. Load meals matching the correct meal type
2. Exclude the current meal during swaps
3. Down-rank recently planned meals
4. Avoid repeating the same meal family in the same week
5. Avoid obvious protein repetition where possible
6. Add a small random factor
7. Select the highest-ranked eligible meal

Conceptual scoring:

```text
score =
  recencyScore
  + familyVarietyScore
  + proteinVarietyScore
  + randomFactor
```

The app does not need machine learning for V1.

---

## 14. Swap Logic

Swapping must only replace one meal.

Example:

```text
Breakfast
Lunch
Dinner 1 ← swap only this
Dinner 2
```

Do not regenerate the whole week.

The swap sheet should:

- search meals
- filter by meal type
- show compatible alternatives
- allow selecting one meal
- return to the generated plan

---

## 15. ShoppingService

File:

```text
lib/services/shopping_service.dart
```

Required methods:

```dart
Future<List<ShoppingItem>> generateFromPlan(String planId);

Future<void> toggleItem(String shoppingItemId);

Future<void> addManualItem(...);

Future<void> updateItem(...);

Future<void> deleteItem(String id);
```

---

## 16. Shopping List Aggregation Rules

When a plan is confirmed:

1. load all plan items
2. load ingredients for each meal
3. merge matching ingredients
4. sum quantities only when units match
5. preserve unknown quantity where precision is not known
6. group by category
7. save generated shopping items

Example:

```text
Chicken 500 g
Chicken 750 g
```

becomes:

```text
Chicken 1.25 kg
```

Only perform unit conversion if explicitly supported.

Do not invent quantities.

---

## 17. Provider Responsibilities

## SettingsProvider

```dart
class SettingsProvider extends ChangeNotifier {
  AppSettings? settings;
  bool isLoading = false;

  Future<void> loadSettings();
  Future<void> updateMealCounts(...);
}
```

Used by:

```text
Select Meal Count
```

---

## MealProvider

```dart
class MealProvider extends ChangeNotifier {
  List<MealVariant> meals = [];
  bool isLoading = false;

  Future<void> loadMeals();
  Future<void> addMeal(...);
  Future<void> updateMeal(...);
  Future<void> deleteMeal(...);
}
```

Used by:

```text
Meal Library
Meal Detail
Swap Meal
Import Review
```

---

## PlannerProvider

```dart
class PlannerProvider extends ChangeNotifier {
  WeeklyPlan? currentPlan;
  List<WeeklyPlanItem> items = [];

  bool isGenerating = false;
  bool isConfirming = false;

  Future<void> generatePlan();
  Future<void> swapMeal(...);
  Future<void> confirmPlan();
}
```

Used by:

```text
Plan This Week
Generated Plan
Swap Meal
```

---

## ShoppingProvider

```dart
class ShoppingProvider extends ChangeNotifier {
  List<ShoppingItem> items = [];
  bool isLoading = false;

  Future<void> generateFromPlan(String planId);
  Future<void> loadShoppingList(String planId);
  Future<void> toggleItem(String id);
  Future<void> addItem(...);
  Future<void> deleteItem(...);
}
```

---

## ImportProvider

Add this after the main planning workflow works.

```dart
class ImportProvider extends ChangeNotifier {
  String sourceText = '';
  List<ImportedMealCandidate> candidates = [];

  bool isParsing = false;

  Future<void> parseText();
  Future<void> confirmImport();
}
```

---

## 18. UI Build Order

Build screens in this order.

### 1. Select Meal Count

Purpose:

Allow the household to choose how many meal-prep batches are needed.

Inputs:

```text
Breakfast count
Lunch count
Dinner count
```

Action:

```text
Continue
```

Persist settings locally.

---

### 2. Plan This Week

Show empty meal slots based on selected counts.

Example:

```text
Breakfast
Lunch
Dinner 1
Dinner 2
```

Primary action:

```text
Plan this week
```

---

### 3. Generated Plan

Display the selected meals.

Each card should have:

- meal category
- meal name
- optional protein
- swap action

Primary action:

```text
Confirm plan
```

Secondary action:

```text
Regenerate
```

Avoid making regenerate the primary interaction.

---

### 4. Swap Meal Sheet

Bottom sheet.

Contains:

- search
- filter chips
- compatible meals
- confirm selection

Only one slot changes.

---

### 5. Shopping List

Generated after plan confirmation.

Features:

- category grouping
- checked/unchecked state
- quantities where known
- manual items
- filters
- persistent state

---

### 6. Meal Library

Features:

- add meal
- search
- meal type filters
- card grid/list
- tap to open detail

---

### 7. Meal Detail

Displays:

- meal image if available
- meal name
- meal family
- protein/variant information
- meal type
- ingredients
- quantities
- edit action

---

### 8. Import Meal History

Start with pasted text.

Do not begin with complex document parsing.

The user pastes previous meal notes and continues.

---

### 9. Review Import

Show detected meals.

Allow:

- include/exclude
- rename
- assign meal type
- merge duplicates
- confirm

AI-assisted parsing can be added after the basic manual review flow is working.

---

## 19. Shared Widgets to Build First

Build these before full screens.

```text
PrepButton
PrepHeader
BottomNavigation
MealSlotCard
MealCardCompact
MealCardLibrary
ShoppingItemTile
CategoryBadge
PrepFilterChip
PrepSearchInput
WeekRangeCard
QuantitySelector
```

Do not recreate these separately on each screen.

---

## 20. Flutter Theme Setup

Create:

```text
lib/theme/app_theme.dart
```

Use:

```dart
ThemeData(
  scaffoldBackgroundColor: AppColors.backgroundApp,
  fontFamily: 'DM Sans',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.actionPrimary,
  ),
)
```

Keep typography, spacing and colour references centralized.

---

## 21. Navigation

Keep navigation simple.

Suggested routes:

```text
/select-meal-count
/plan
/generated-plan
/shopping
/meals
/meal/:id
/import
/import/review
/history
```

The Swap Meal interaction should be a modal bottom sheet, not a dedicated route unless needed later.

---

## 22. Seed Data

Do not make AI import the first engineering challenge.

Seed SQLite with a small set of known meals so the full flow can be tested immediately.

Example seed meals:

```text
Lou Lou Spaghetti + Chicken
Lou Lou Spaghetti + Turkey
Fried Rice + Chicken
Jollof Rice + Turkey
Burger + Sweet Potato
Fish + Rice
Pasta + Mince
Breakfast Muffins
Paninis
```

Add enough ingredients to test shopping aggregation.

The goal is to validate the weekly planning flow before building import intelligence.

---

## 23. First Development Sprint

## Sprint Goal

Produce a working local app where a user can:

```text
choose meal counts
→ generate a weekly plan
→ swap one meal
→ confirm the plan
→ see a generated shopping list
→ check shopping items off
```

### Sprint Tasks

#### Setup
- [ ] Create Flutter project
- [ ] Add Provider
- [ ] Add sqflite
- [ ] Add uuid
- [ ] Add intl
- [ ] Add DM Sans
- [ ] Create theme tokens

#### Database
- [ ] Create DatabaseService
- [ ] Create SQLite tables
- [ ] Add seed data
- [ ] Verify database reads/writes

#### Models
- [ ] MealFamily
- [ ] MealVariant
- [ ] Ingredient
- [ ] MealIngredient
- [ ] WeeklyPlan
- [ ] WeeklyPlanItem
- [ ] ShoppingItem
- [ ] AppSettings

#### Services
- [ ] SettingsService
- [ ] MealService
- [ ] PlanningService
- [ ] ShoppingService

#### Providers
- [ ] SettingsProvider
- [ ] MealProvider
- [ ] PlannerProvider
- [ ] ShoppingProvider

#### Shared UI
- [ ] PrepButton
- [ ] PrepHeader
- [ ] BottomNavigation
- [ ] MealSlotCard
- [ ] MealCardCompact
- [ ] ShoppingItemTile
- [ ] CategoryBadge
- [ ] QuantitySelector

#### Screens
- [ ] Select Meal Count
- [ ] Plan This Week
- [ ] Generated Plan
- [ ] Swap Meal Sheet
- [ ] Shopping List

#### Validation
- [ ] Change meal counts
- [ ] Generate valid plan
- [ ] Prevent obvious duplicate meals
- [ ] Swap one meal without altering other slots
- [ ] Confirm plan
- [ ] Generate consolidated shopping list
- [ ] Persist checked shopping state after restart

---

## 24. Sprint 2

After the core loop works:

- [ ] Meal Library
- [ ] Meal Detail
- [ ] Add meal
- [ ] Edit meal
- [ ] Edit ingredients
- [ ] Delete meal
- [ ] Plan History
- [ ] Improve recommendation scoring
- [ ] Add empty states
- [ ] Add loading states
- [ ] Add error states

---

## 25. Sprint 3

Import flow:

- [ ] Paste historical meal notes
- [ ] Parse candidate meal names
- [ ] Review candidate meals
- [ ] Merge duplicates
- [ ] Assign meal types
- [ ] Save into meal library
- [ ] Add AI-assisted cleanup if required

AI should assist with extraction and cleanup.

It should not become the source of truth for weekly planning.

---

## 26. Supabase Phase

Only start this after local-first MVP validation.

Future architecture:

```text
Flutter UI
↓
Provider
↓
Service
↓
SQLite
   ↕
SyncService
   ↕
Supabase
```

Add later:

```text
services/
  auth_service.dart
  sync_service.dart
```

Recommended future database fields:

```text
created_at
updated_at
synced_at
deleted_at
```

SQLite should remain the local source of truth.

---

## 27. MVP Definition of Done

The MVP is usable when the following works without Supabase or AI:

1. User chooses meal counts
2. PrepPick stores those settings
3. User generates a weekly plan
4. Meals are selected from their personal meal library
5. User can swap one meal
6. User confirms the plan
7. Ingredients are consolidated
8. Shopping list is generated
9. Shopping items can be checked off
10. App state survives a restart

If all ten work reliably, PrepPick has reached the first meaningful MVP milestone.

---

## 28. Important Product Rules

Keep these rules visible while building.

### Rule 1
PrepPick plans from meals the household already likes.

### Rule 2
The app should reduce weekly decision-making.

### Rule 3
Swapping one meal should not regenerate the whole week.

### Rule 4
Do not invent missing ingredient quantities.

### Rule 5
The shopping list is a first-class product experience.

### Rule 6
AI is an assistant for messy import, not the core planning engine.

### Rule 7
The first useful version should work fully offline.

---

## 29. Recommended First Coding Session

Build only this vertical slice first:

```text
AppTheme
↓
DatabaseService
↓
Seed Meals
↓
AppSettings
↓
SettingsService
↓
SettingsProvider
↓
SelectMealCountScreen
```

Then:

```text
MealService
↓
PlanningService
↓
PlannerProvider
↓
PlanThisWeekScreen
↓
GeneratedPlanScreen
```

Then:

```text
ShoppingService
↓
ShoppingProvider
↓
ShoppingListScreen
```

This avoids building a large amount of UI before the core data flow is proven.

---

## 30. Architecture Rule for Every New Feature

Whenever you add a feature, ask:

```text
What is the model?
What service owns the logic?
What provider owns the state?
What UI consumes that state?
```

If the UI starts containing SQL or planning logic, move it down into a service.

If a provider starts becoming full of SQL, move that logic into a service.

Keep the system simple:

```text
Model
→ Service
→ Provider
→ UI
```

That is the intended PrepPick architecture for the MVP.
