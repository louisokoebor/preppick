import 'package:flutter/material.dart';

/// PrepPick semantic colour tokens, mirrored from the approved Figma design.
///
/// Screens should reference these tokens rather than hard-coded [Color] values.
class AppColors {
  const AppColors._();

  // Background
  static const backgroundApp = Color(0xFFF8F7F3);
  static const backgroundSurface = Color(0xFFFFFFFF);
  static const backgroundMuted = Color(0xFFF0F1EE);

  // Text
  static const textPrimary = Color(0xFF171A16);
  static const textSecondary = Color(0xFF6E746D);
  static const textTertiary = Color(0xFFB9BDB7);
  static const textInverse = Color(0xFFFFFFFF);

  // Border
  static const borderDefault = Color(0xFFB9BDB7);
  static const borderSubtle = Color(0xFFF0F1EE);

  // Action
  static const actionPrimary = Color(0xFF1E9A5A);
  static const actionPrimaryHover = Color(0xFF36A86D);
  static const actionPrimaryPressed = Color(0xFF147A45);
  static const actionSecondary = Color(0xFFE6F4EC);

  // Category
  static const categoryBreakfast = Color(0xFFFFF0DC);
  static const categoryLunch = Color(0xFFE6F4EC);
  static const categoryDinner = Color(0xFFEFECFF);
  static const categoryShopping = Color(0xFFFDEBE8);

  // State
  static const stateWarning = Color(0xFFE99A43);
  static const stateError = Color(0xFFD96555);
}
