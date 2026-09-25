import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:preppick/models/models.dart';
import 'package:preppick/services/plan_scoring.dart';

void main() {
  final now = DateTime.utc(2026, 3, 15);

  MealVariant meal({
    required String id,
    String family = 'family-a',
    String? protein,
    DateTime? lastPlannedAt,
    int timesPlanned = 0,
  }) => MealVariant(
    id: id,
    mealFamilyId: family,
    name: id,
    protein: protein,
    lastPlannedAt: lastPlannedAt,
    timesPlanned: timesPlanned,
    createdAt: now,
    updatedAt: now,
  );

  double scoreOf(MealVariant candidate, {SlotContext? context}) =>
      PlanScoring.scoreMeal(
        meal: candidate,
        context: context ?? SlotContext(),
        now: now,
      );

  group('recency', () {
    test('a meal used yesterday scores below a comparable stale meal', () {
      final yesterday = meal(
        id: 'fresh-in-memory',
        lastPlannedAt: now.subtract(const Duration(days: 1)),
      );
      final longAgo = meal(
        id: 'forgotten',
        lastPlannedAt: now.subtract(const Duration(days: 21)),
      );

      expect(scoreOf(yesterday), lessThan(scoreOf(longAgo)));
    });

    test('a never-planned meal scores the full recency reward', () {
      expect(PlanScoring.recencyScore(null, now), PlanScoring.recencyWeight);
    });

    test('recency saturates at the horizon rather than growing forever', () {
      final atHorizon = now.subtract(
        Duration(days: PlanScoring.recencyHorizonDays),
      );
      final ancient = now.subtract(const Duration(days: 365));

      expect(
        PlanScoring.recencyScore(atHorizon, now),
        PlanScoring.recencyWeight,
      );
      expect(PlanScoring.recencyScore(ancient, now), PlanScoring.recencyWeight);
    });

    test(
      'a future last-planned date is treated as just planned, not negative',
      () {
        final future = now.add(const Duration(days: 5));
        expect(PlanScoring.recencyScore(future, now), 0);
      },
    );
  });

  group('frequency', () {
    test('a rarely planned meal outscores a household staple', () {
      expect(
        PlanScoring.frequencyScore(0),
        greaterThan(PlanScoring.frequencyScore(12)),
      );
    });

    test('never exceeds its weight', () {
      expect(PlanScoring.frequencyScore(0), PlanScoring.frequencyWeight);
    });
  });

  group('family variety', () {
    test('a new family is preferred over one already in the plan', () {
      final context = SlotContext(usedFamilyIds: {'family-a'});
      final repeat = meal(id: 'repeat', family: 'family-a');
      final fresh = meal(id: 'fresh', family: 'family-b');

      expect(
        scoreOf(repeat, context: context),
        lessThan(scoreOf(fresh, context: context)),
      );
    });

    test('family variety outranks recency', () {
      // The repeated family is the more appealing meal on every other axis:
      // never planned at all. It must still lose to a stale new family.
      final context = SlotContext(usedFamilyIds: {'family-a'});
      final repeatButFresh = meal(id: 'repeat', family: 'family-a');
      final newFamilyJustEaten = meal(
        id: 'new',
        family: 'family-b',
        timesPlanned: 40,
        lastPlannedAt: now,
      );

      expect(
        scoreOf(newFamilyJustEaten, context: context),
        greaterThan(scoreOf(repeatButFresh, context: context)),
      );
    });
  });

  group('protein variety', () {
    test('an unused protein is preferred when alternatives exist', () {
      final context = SlotContext(usedProteins: {'chicken'});
      final chicken = meal(id: 'chicken', family: 'f1', protein: 'Chicken');
      final salmon = meal(id: 'salmon', family: 'f2', protein: 'Salmon');

      expect(
        scoreOf(chicken, context: context),
        lessThan(scoreOf(salmon, context: context)),
      );
    });

    test('protein matching ignores case and surrounding whitespace', () {
      final context = SlotContext(usedProteins: {'chicken'});
      expect(
        PlanScoring.proteinVarietyScore('  CHICKEN ', context.usedProteins),
        0,
      );
    });

    test('an unknown protein is not penalised, because it is not evidence', () {
      final context = SlotContext(usedProteins: {'chicken'});
      expect(
        PlanScoring.proteinVarietyScore(null, context.usedProteins),
        PlanScoring.proteinWeight,
      );
      expect(
        PlanScoring.proteinVarietyScore('   ', context.usedProteins),
        PlanScoring.proteinWeight,
      );
    });

    test('protein variety outranks recency but yields to family variety', () {
      expect(
        PlanScoring.proteinWeight,
        greaterThan(
          PlanScoring.recencyWeight +
              PlanScoring.frequencyWeight +
              PlanScoring.randomWeight,
        ),
      );
      expect(
        PlanScoring.familyWeight,
        greaterThan(
          PlanScoring.proteinWeight +
              PlanScoring.recencyWeight +
              PlanScoring.frequencyWeight +
              PlanScoring.randomWeight,
        ),
      );
    });
  });

  group('uniqueness', () {
    test('a meal already in the plan loses to any unused meal', () {
      final context = SlotContext(
        usedVariantIds: {'used'},
        usedFamilyIds: {'family-a'},
        usedProteins: {'chicken'},
      );
      // The unused meal breaks both variety rules and was eaten today; the
      // repeat breaks neither beyond being a repeat. Uniqueness still wins.
      final repeat = meal(id: 'used', family: 'family-z', protein: 'Tofu');
      final unusedButPoor = meal(
        id: 'other',
        family: 'family-a',
        protein: 'Chicken',
        lastPlannedAt: now,
        timesPlanned: 30,
      );

      expect(
        scoreOf(repeat, context: context),
        lessThan(scoreOf(unusedButPoor, context: context)),
      );
    });

    test(
      'outranks every other term combined, so repeats are a last resort',
      () {
        expect(
          PlanScoring.uniquenessWeight,
          greaterThan(
            PlanScoring.familyWeight +
                PlanScoring.proteinWeight +
                PlanScoring.recencyWeight +
                PlanScoring.frequencyWeight +
                PlanScoring.randomWeight,
          ),
        );
      },
    );
  });

  group('random factor', () {
    test('cannot overpower any business rule, across many draws', () {
      final random = Random(7);
      final context = SlotContext(
        usedFamilyIds: {'family-a'},
        usedProteins: {'chicken'},
      );
      final ruleBreaker = meal(id: 'repeat', family: 'family-a');
      final ruleKeeper = meal(id: 'fresh', family: 'family-b');

      for (var i = 0; i < 500; i++) {
        final bad = PlanScoring.scoreMeal(
          meal: ruleBreaker,
          context: context,
          now: now,
          random: random,
        );
        final good = PlanScoring.scoreMeal(
          meal: ruleKeeper,
          context: context,
          now: now,
          random: random,
        );
        expect(bad, lessThan(good));
      }
    });

    test('still separates candidates the business rules rate identically', () {
      final twins = [
        meal(id: 'a', family: 'f1'),
        meal(id: 'b', family: 'f2'),
        meal(id: 'c', family: 'f3'),
      ];
      final picks = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        final choice = PlanScoring.selectBest(
          candidates: twins,
          context: SlotContext(),
          now: now,
          random: Random(seed),
        );
        picks.add(choice!.id);
      }

      expect(picks.length, greaterThan(1), reason: 'plans should vary');
    });

    test('selection is deterministic when no random source is supplied', () {
      final candidates = [
        meal(id: 'a', family: 'f1'),
        meal(id: 'b', family: 'f2'),
      ];
      final first = PlanScoring.selectBest(
        candidates: candidates,
        context: SlotContext(),
        now: now,
      );
      expect(first!.id, 'a');
    });
  });

  group('selection', () {
    test('returns null only for an empty candidate list', () {
      expect(
        PlanScoring.selectBest(
          candidates: const [],
          context: SlotContext(),
          now: now,
        ),
        isNull,
      );
    });

    test('rank orders best first and keeps every candidate', () {
      final context = SlotContext(usedFamilyIds: {'family-a'});
      final ranked = PlanScoring.rank(
        candidates: [
          meal(id: 'repeat-family', family: 'family-a'),
          meal(id: 'new-family', family: 'family-b'),
        ],
        context: context,
        now: now,
      );

      expect(ranked.map((m) => m.id), ['new-family', 'repeat-family']);
    });
  });

  group('SlotContext.of', () {
    test('collects families plan-wide but proteins only for one meal type', () {
      final context = SlotContext.of([
        (
          meal: meal(id: 'l1', family: 'fam-lunch', protein: 'Chicken'),
          mealType: MealType.lunch,
        ),
        (
          meal: meal(id: 'd1', family: 'fam-dinner', protein: 'Beef'),
          mealType: MealType.dinner,
        ),
      ], proteinScope: MealType.dinner);

      expect(context.usedVariantIds, {'l1', 'd1'});
      expect(context.usedFamilyIds, {'fam-lunch', 'fam-dinner'});
      expect(context.usedProteins, {'beef'});
    });
  });
}
