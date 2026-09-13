import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'routes.dart';

/// Root widget. Owns theming, routing and the provider shell.
///
/// Providers are registered here only once they are implemented. The first
/// real provider (SettingsProvider, Phase 2) is wrapped in a MultiProvider at
/// the marked point below; `provider` rejects an empty provider list, so no
/// placeholder shell is created up front.
class PrepPickApp extends StatelessWidget {
  const PrepPickApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Providers go here, as MultiProvider(providers: [...], child: MaterialApp).
    return MaterialApp(
      title: 'PrepPick',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.startup,
      routes: {
        AppRoutes.startup: (_) => const StartupShellScreen(),
      },
    );
  }
}

/// Temporary landing screen so the app has something to show before the
/// planner flow is built. Replaced in Phase 2.
class StartupShellScreen extends StatelessWidget {
  const StartupShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PrepPick', style: textTheme.displayLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Plan the meals your household already likes.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
