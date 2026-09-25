import 'dart:math';

import '../models/models.dart';

/// The deterministic scoring rules behind PrepPick's weekly planner.
///
/// Everything here is a pure function of its arguments — no database, no
/// clock, no hidden state — so the product rules can be tested directly
/// rather than inferred from a generated plan. [PlanningService] owns the
/// persistence and calls into this.
///
/// ## Why the weights look like this
///
/// Each term occupies its own band, and a band is always wider than the sum
/// of every band below it. That makes the rules strictly ordered rather than
/// merely weighted: a lower-priority term can break a tie inside a band, but
/// can never overturn a higher-priority one.
///
/// ```text
/// uniqueness   1000   never repeat a meal already in this plan
/// family        100   never repeat a meal family
/// protein        50   avoid repeating a protein in the same category
/// recency      0-40   prefer meals not eaten recently
/// frequency     0-5   nudge away from the household's over-used staples
/// random        0-2   break near-ties so two weeks are not identical
/// ```
///
/// 100 > 50 + 40 + 5 + 2, and 50 > 40 + 5 + 2, and 1000 > all of it. So the
/// random factor can only ever decide between candidates that the business
/// rules rate equally — which is exactly rule 5.
///
/// ## Graceful relaxation
///
/// Nothing here filters candidates out. A meal that breaks every variety rule
/// still receives a score, it is simply beaten by any meal that does not. A
/// library holding a single dinner therefore still produces a full week of
/// dinners (rule 6) instead of an error, and no special "the library is too
/// small" branch is needed.
class PlanScoring {
  const PlanScoring._();

  /// Awarded to a meal not already placed in the plan being built.
  static const double uniquenessWeight = 1000;

  /// Awarded when no other slot in the plan uses this meal's family.
  static const double familyWeight = 100;

  /// Awarded when no other slot *of the same meal type* uses this protein.
  static const double proteinWeight = 50;

  /// Maximum recency reward, reached at [recencyHorizonDays].
  static const double recencyWeight = 40;

  /// Maximum reward for a meal the household rarely plans.
  static const double frequencyWeight = 5;

  /// Maximum jitter. Deliberately smaller than every business term.
  static const double randomWeight = 2;

  /// How long a meal takes to become "fresh" again. A meal last planned this
  /// many days ago scores the same as one never planned at all.
  static const int recencyHorizonDays = 28;

  /// How strongly a meal is preferred for not having been eaten lately.
  ///
  /// Ramps linearly from 0 (planned today) to [recencyWeight] at
  /// [recencyHorizonDays]. A meal that has never been planned scores the
  /// full amount — an untried favourite should surface.
  ///
  /// A [lastPlannedAt] in the future (a clock change, a plan confirmed ahead
  /// of time) is treated as "just planned" rather than allowed to go
  /// negative.
  static double recencyScore(DateTime? lastPlannedAt, DateTime now) {
    if (lastPlannedAt == null) return recencyWeight;
    final days = now.toUtc().difference(lastPlannedAt.toUtc()).inHours / 24;
    final ratio = (days / recencyHorizonDays).clamp(0.0, 1.0);
    return recencyWeight * ratio;
  }

  /// How strongly a meal is preferred for being an infrequent choice.
  ///
  /// Decays as `1 / (1 + timesPlanned)`, so the gap between a meal planned
  /// never and once is large while the gap between nine and ten times is
  /// negligible — which matches how a household actually experiences
  /// repetition.
  static double frequencyScore(int timesPlanned) =>
      frequencyWeight / (1 + max(0, timesPlanned));

  /// [familyWeight] unless [usedFamilyIds] already contains this family.
  static double familyVarietyScore(
    String mealFamilyId,
    Set<String> usedFamilyIds,
  ) => usedFamilyIds.contains(mealFamilyId) ? 0 : familyWeight;

  /// [proteinWeight] unless [usedProteins] already contains this protein.
  ///
  /// A meal with no recorded protein is never penalised: an unknown protein
  /// is not evidence of repetition, and PrepPick does not invent data it was
  /// not given.
  static double proteinVarietyScore(String? protein, Set<String> usedProteins) {
    final key = normaliseProtein(protein);
    if (key == null) return proteinWeight;
    return usedProteins.contains(key) ? 0 : proteinWeight;
  }

  /// Case- and whitespace-insensitive protein key, or null when unknown.
  static String? normaliseProtein(String? protein) {
    final trimmed = protein?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// The total score for placing [meal] into the slot described by [context].
  ///
  /// [random] supplies the tie-breaking jitter; pass a seeded [Random] to
  /// make a generation reproducible.
  static double scoreMeal({
    required MealVariant meal,
    required SlotContext context,
    required DateTime now,
    Random? random,
  }) {
    final unique = context.usedVariantIds.contains(meal.id)
        ? 0.0
        : uniquenessWeight;
    return unique +
        familyVarietyScore(meal.mealFamilyId, context.usedFamilyIds) +
        proteinVarietyScore(meal.protein, context.usedProteins) +
        recencyScore(meal.lastPlannedAt, now) +
        frequencyScore(meal.timesPlanned) +
        (random == null ? 0 : random.nextDouble() * randomWeight);
  }

  /// The best meal in [candidates] for the slot described by [context].
  ///
  /// Returns null only when [candidates] is empty. Ties are settled by the
  /// jitter in [scoreMeal]; with no [random] supplied the first candidate in
  /// the given order wins, which keeps tests deterministic.
  static MealVariant? selectBest({
    required Iterable<MealVariant> candidates,
    required SlotContext context,
    required DateTime now,
    Random? random,
  }) {
    MealVariant? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in candidates) {
      final score = scoreMeal(
        meal: candidate,
        context: context,
        now: now,
        random: random,
      );
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  /// [candidates] ordered best-first for the slot described by [context].
  ///
  /// Used by the swap sheet, which shows the household the same ranking the
  /// planner would have used rather than a raw alphabetical list.
  static List<MealVariant> rank({
    required Iterable<MealVariant> candidates,
    required SlotContext context,
    required DateTime now,
    Random? random,
  }) {
    final scored = [
      for (final candidate in candidates)
        (
          meal: candidate,
          score: scoreMeal(
            meal: candidate,
            context: context,
            now: now,
            random: random,
          ),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return [for (final entry in scored) entry.meal];
  }
}

/// What the plan already contains when one slot is being filled.
///
/// Family and variant exclusions are plan-wide: the same meal twice in a week
/// is repetitive whether it lands at lunch or dinner. Protein exclusions are
/// scoped to one meal type, because chicken at lunch and chicken at dinner is
/// a much weaker clash than chicken at both dinners.
class SlotContext {
  SlotContext({
    Set<String>? usedVariantIds,
    Set<String>? usedFamilyIds,
    Set<String>? usedProteins,
  }) : usedVariantIds = usedVariantIds ?? <String>{},
       usedFamilyIds = usedFamilyIds ?? <String>{},
       usedProteins = usedProteins ?? <String>{};

  /// Meals already placed anywhere in this plan.
  final Set<String> usedVariantIds;

  /// Families already placed anywhere in this plan.
  final Set<String> usedFamilyIds;

  /// Proteins already placed in *this meal type*, normalised.
  final Set<String> usedProteins;

  /// Records [meal] as placed, so later slots avoid it.
  void add(MealVariant meal) {
    usedVariantIds.add(meal.id);
    usedFamilyIds.add(meal.mealFamilyId);
    final protein = PlanScoring.normaliseProtein(meal.protein);
    if (protein != null) usedProteins.add(protein);
  }

  /// The context produced by a set of already-placed meals.
  ///
  /// [placed] pairs each meal with the type of the slot it occupies, which is
  /// what lets protein exclusions stay scoped to one meal type while family
  /// and variant exclusions apply across the whole plan. Pass only the *other*
  /// slots when scoring a replacement, so the meal being swapped out does not
  /// compete against its own alternatives.
  static SlotContext of(
    Iterable<({MealVariant meal, MealType mealType})> placed, {
    required MealType proteinScope,
  }) {
    final context = SlotContext();
    for (final entry in placed) {
      context.usedVariantIds.add(entry.meal.id);
      context.usedFamilyIds.add(entry.meal.mealFamilyId);
      if (entry.mealType != proteinScope) continue;
      final protein = PlanScoring.normaliseProtein(entry.meal.protein);
      if (protein != null) context.usedProteins.add(protein);
    }
    return context;
  }
}
