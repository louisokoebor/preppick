import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/meal_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/category_labels.dart';
import '../../widgets/prep_loading.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_header.dart';

/// Add or edit one meal and its ingredient links.
class MealEditScreen extends StatefulWidget {
  const MealEditScreen({super.key, this.mealId});

  final String? mealId;

  bool get isEditing => mealId != null;

  @override
  State<MealEditScreen> createState() => _MealEditScreenState();
}

class _MealEditScreenState extends State<MealEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyName = TextEditingController();
  final _variantName = TextEditingController();
  final _protein = TextEditingController();
  final _estimatedMinutes = TextEditingController();
  final List<_IngredientEditor> _ingredients = [];

  MealType? _mealType;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.mealId != null) {
      _loadMeal(widget.mealId!);
    }
  }

  @override
  void dispose() {
    _familyName.dispose();
    _variantName.dispose();
    _protein.dispose();
    _estimatedMinutes.dispose();
    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMeal(String id) async {
    setState(() => _isLoading = true);
    MealDetail? detail;
    try {
      detail = await context.read<MealProvider>().getDetail(id);
    } catch (_) {
      detail = null;
    }
    if (!mounted) return;
    if (detail == null) {
      setState(() {
        _isLoading = false;
        _error = 'This meal could not be found.';
      });
      return;
    }
    _familyName.text = detail.family.name;
    _variantName.text = detail.meal.name;
    _protein.text = detail.meal.protein ?? '';
    _estimatedMinutes.text = detail.meal.estimatedMinutes?.toString() ?? '';
    _mealType = detail.family.mealType;
    for (final line in detail.ingredients) {
      _ingredients.add(_IngredientEditor.fromLine(line));
    }
    setState(() => _isLoading = false);
  }

  void _addIngredient() {
    setState(() => _ingredients.add(_IngredientEditor()));
  }

  void _removeIngredient(int index) {
    final ingredient = _ingredients.removeAt(index);
    ingredient.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final mealType = _mealType;
    if (mealType == null) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final drafts = <MealIngredientDraft>[];
      for (final ingredient in _ingredients) {
        final quantityText = ingredient.quantity.text.trim();
        drafts.add(
          MealIngredientDraft(
            lineId: ingredient.lineId,
            name: ingredient.name.text.trim(),
            category: ingredient.category,
            quantity: quantityText.isEmpty ? null : double.parse(quantityText),
            unit: ingredient.unit.text.trim().isEmpty
                ? null
                : ingredient.unit.text.trim(),
          ),
        );
      }
      final estimatedText = _estimatedMinutes.text.trim();
      await context.read<MealProvider>().saveMeal(
        mealVariantId: widget.mealId,
        familyName: _familyName.text,
        mealType: mealType,
        variantName: _variantName.text,
        protein: _protein.text,
        estimatedMinutes: estimatedText.isEmpty
            ? null
            : int.parse(estimatedText),
        ingredients: drafts,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FormatException {
      setState(() {
        _isSaving = false;
        _error = 'Enter a valid number for each amount or time.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'The meal could not be saved. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: SafeArea(child: PrepLoading(message: 'Loading this meal')),
      );
    }
    if (_error != null && widget.mealId != null && _familyName.text.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              PrepHeader(
                title: 'Edit meal',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(child: Center(child: Text(_error!))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              PrepHeader(
                title: widget.isEditing ? 'Edit meal' : 'Add meal',
                subtitle: widget.isEditing
                    ? 'Keep this meal up to date.'
                    : 'Save a meal your household already likes.',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xxl,
                  ),
                  children: [
                    _textField(
                      controller: _familyName,
                      label: 'Meal family / name',
                      hint: 'e.g. Jollof Rice',
                      validator: _required,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<MealType>(
                      initialValue: _mealType,
                      decoration: _decoration('Meal type'),
                      hint: const Text('Choose a meal type'),
                      validator: (value) =>
                          value == null ? 'Choose a meal type' : null,
                      items: [
                        for (final type in MealType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Icon(CategoryBadge.iconFor(type), size: 18),
                                const SizedBox(width: AppSpacing.sm),
                                Text(CategoryBadge.nameFor(type)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _mealType = value),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _textField(
                      controller: _variantName,
                      label: 'Variant name',
                      hint: 'Optional — e.g. Jollof Rice + Turkey',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _textField(
                      controller: _protein,
                      label: 'Protein',
                      hint: 'Optional',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _textField(
                      controller: _estimatedMinutes,
                      label: 'Estimated cook time',
                      hint: 'Optional minutes',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value?.trim().isEmpty ?? true) return null;
                        final minutes = int.tryParse(value!.trim());
                        if (minutes == null) return 'Use whole minutes';
                        return minutes <= 0 ? 'Use at least 1 minute' : null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ingredients',
                            style: AppTypography.headingH3,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isSaving ? null : _addIngredient,
                          icon: const Icon(AppIcons.addRounded),
                          label: const Text('Add ingredient'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_ingredients.isEmpty)
                      Text(
                        'No ingredients yet. Add them when you know them — '
                        'amounts can stay blank.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else
                      for (var index = 0; index < _ingredients.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _IngredientEditorView(
                            key: ValueKey(_ingredients[index]),
                            editor: _ingredients[index],
                            onRemove: () => _removeIngredient(index),
                            enabled: !_isSaving,
                          ),
                        ),
                    if (_error != null &&
                        (widget.mealId == null || _familyName.text.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          _error!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.stateError,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                color: AppColors.backgroundApp,
                child: PrepButton(
                  label: widget.isEditing ? 'Save changes' : 'Save meal',
                  isBusy: _isSaving,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_isSaving,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    style: AppTypography.bodyMedium,
    decoration: _decoration(hint).copyWith(labelText: label),
    validator: validator,
  );

  static String? _required(String? value) =>
      value?.trim().isEmpty ?? true ? 'Enter a meal name' : null;
}

class _IngredientEditor {
  _IngredientEditor({
    this.lineId,
    this.category,
    String? name,
    String? quantity,
    String? unit,
  }) : name = TextEditingController(text: name),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit);

  factory _IngredientEditor.fromLine(MealRecipeLine line) => _IngredientEditor(
    lineId: line.id,
    name: line.name,
    category: line.category,
    quantity: line.quantity == null
        ? null
        : (line.quantity! == line.quantity!.roundToDouble()
              ? line.quantity!.toInt().toString()
              : line.quantity!.toString()),
    unit: line.unit,
  );

  final String? lineId;
  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unit;
  String? category;

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
  }
}

class _IngredientEditorView extends StatelessWidget {
  const _IngredientEditorView({
    super.key,
    required this.editor,
    required this.onRemove,
    required this.enabled,
  });

  final _IngredientEditor editor;
  final VoidCallback onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.backgroundSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: editor.name,
                enabled: enabled,
                decoration: _decoration('Ingredient name'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Enter an ingredient name'
                    : null,
              ),
            ),
            IconButton(
              onPressed: enabled ? onRemove : null,
              tooltip: 'Remove ingredient',
              icon: const Icon(
                AppIcons.deleteOutlineRounded,
                semanticLabel: 'Remove ingredient',
              ),
              color: AppColors.stateError,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: editor.quantity,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: _decoration('Quantity (optional)'),
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) return null;
                  return double.tryParse(value!.trim()) == null
                      ? 'Use a number'
                      : null;
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: editor.unit,
                enabled: enabled,
                decoration: _decoration('Unit (optional)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: editor.category,
          decoration: _decoration('Category (optional)'),
          items: [
            for (final category in IngredientCategory.all)
              DropdownMenuItem(
                value: category,
                child: Text(PrepCategoryLabels.labelFor(category)),
              ),
          ],
          onChanged: enabled ? (value) => editor.category = value : null,
        ),
      ],
    ),
  );
}

InputDecoration _decoration(String hint) => InputDecoration(
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
    borderSide: const BorderSide(color: AppColors.borderDefault),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: const BorderSide(color: AppColors.borderDefault),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: const BorderSide(color: AppColors.actionPrimary),
  ),
);
