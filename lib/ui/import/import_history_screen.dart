import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../providers/import_provider.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/error_messages.dart';
import '../../widgets/prep_button.dart';
import '../../widgets/prep_header.dart';

class ImportHistoryScreen extends StatefulWidget {
  const ImportHistoryScreen({super.key, this.onContinue});

  final VoidCallback? onContinue;

  @override
  State<ImportHistoryScreen> createState() => _ImportHistoryScreenState();
}

class _ImportHistoryScreenState extends State<ImportHistoryScreen> {
  late final TextEditingController _source;

  @override
  void initState() {
    super.initState();
    _source = TextEditingController(
      text: context.read<ImportProvider>().sourceText,
    );
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final provider = context.read<ImportProvider>();
    final ok = await provider.parseSource();
    if (!mounted || !ok) return;
    final onContinue = widget.onContinue;
    if (onContinue != null) {
      onContinue();
    } else {
      Navigator.of(context).pushNamed(AppRoutes.reviewImport);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ImportProvider>();
    // Never the error object itself: a failed parse is the household's to
    // fix, but a failed write is ours, and only one of the two has copy worth
    // reading.
    final error = PrepErrorMessages.forError(
      provider.error,
      fallback: 'Your notes could not be read. Please try again.',
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PrepHeader(
              title: 'Import history',
              subtitle:
                  'Paste meal notes from past weeks and review them before they join your library.',
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
                  Text(
                    'Paste one meal per line. Bullets and numbering are fine; ingredients and quantities will not be imported here.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSurface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: TextField(
                      key: const Key('importSourceTextField'),
                      controller: _source,
                      minLines: 10,
                      maxLines: 16,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText:
                            'e.g.\n- Lou Lou Spaghetti + Chicken\n- Fried Rice\n3. Paninis',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(AppSpacing.lg),
                      ),
                      onChanged: provider.updateSourceText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ExampleBox(),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      error,
                      key: const Key('importErrorText'),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.stateError,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: PrepButton(
                label: 'Continue to review',
                icon: AppIcons.arrowForwardRounded,
                iconAfterLabel: true,
                isBusy: provider.isParsing,
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.backgroundMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        'Good paste shape:\nBreakfast Muffins\nFried Rice + Chicken\nJollof Rice + Turkey',
        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
