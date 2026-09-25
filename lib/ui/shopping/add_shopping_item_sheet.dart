import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/category_labels.dart';
import '../../widgets/prep_button.dart';

/// What the household typed into the add-item sheet.
class ManualItemDraft {
  const ManualItemDraft({
    required this.name,
    required this.category,
    this.quantity,
    this.unit,
  });

  final String name;
  final String category;

  /// Null when they gave no amount. Nothing is inferred from the name — a
  /// shopping list that guesses is worse than one that says nothing.
  final double? quantity;
  final String? unit;
}

/// The sheet for adding something the plan did not produce: bin bags, milk,
/// whatever the household knows they need.
///
/// Only the name is required. Quantity and unit are offered but never
/// demanded, because most of what gets added this way — "coffee", "bread" —
/// has no amount worth typing, and forcing one would invite a made-up number.
class AddShoppingItemSheet extends StatefulWidget {
  const AddShoppingItemSheet({super.key});

  /// Opens the sheet and resolves to what was entered, or null if dismissed.
  static Future<ManualItemDraft?> show(BuildContext context) {
    return showModalBottomSheet<ManualItemDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
      builder: (_) => const AddShoppingItemSheet(),
    );
  }

  @override
  State<AddShoppingItemSheet> createState() => _AddShoppingItemSheetState();
}

class _AddShoppingItemSheetState extends State<AddShoppingItemSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _unit = TextEditingController();

  String _category = IngredientCategory.other;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty;

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final typed = _quantity.text.trim();
    final unit = _unit.text.trim();

    Navigator.of(context).pop(
      ManualItemDraft(
        name: name,
        category: _category,
        // An unparseable amount is dropped rather than guessed at; the line
        // simply carries no quantity.
        quantity: typed.isEmpty ? null : double.tryParse(typed),
        unit: unit.isEmpty ? null : unit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        // The fields scroll and the action does not. On a short phone with
        // the keyboard up there is not enough room for the whole sheet, and
        // if the button scrolls with the fields it ends up under the keys
        // with nothing on screen saying it is there.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add an item', style: AppTypography.headingH3),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Anything else you need this week. An amount is optional.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _Field(
                      controller: _name,
                      label: 'Item',
                      hint: 'e.g. Bin bags',
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _canSubmit ? _submit() : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Field(
                            controller: _quantity,
                            label: 'Amount',
                            hint: 'Optional',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _Field(
                            controller: _unit,
                            label: 'Unit',
                            hint: 'g, ml, packs',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Aisle',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: _fieldDecoration('Aisle'),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      items: [
                        for (final category in IngredientCategory.all)
                          DropdownMenuItem(
                            value: category,
                            child: Text(PrepCategoryLabels.labelFor(category)),
                          ),
                      ],
                      onChanged: (value) => setState(
                        () => _category = value ?? IngredientCategory.other,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: PrepButton(
                label: 'Add to list',
                onPressed: _canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
  filled: true,
  fillColor: AppColors.backgroundSurface,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: const BorderSide(color: AppColors.actionPrimary),
  ),
);

/// A labelled text field in the sheet's style.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: AppTypography.bodyMedium,
          decoration: _fieldDecoration(hint),
        ),
      ],
    );
  }
}
