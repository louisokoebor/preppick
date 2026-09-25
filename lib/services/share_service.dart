import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../utils/category_labels.dart';
import '../utils/quantity_format.dart';
import '../utils/week_range_format.dart';

/// Builds and shares the two things a household needs to take out of
/// PrepPick: the shopping list and the current meal plan.
///
/// Formatting lives here rather than in either screen so a message and a PDF
/// always describe the same data, and so platform sharing stays out of the UI.
class ShareService {
  const ShareService();

  static const _appName = 'PrepPick';

  String shoppingListMessage({
    required DateTime weekStart,
    required Iterable<ShoppingItem> items,
  }) {
    final groups = _groupShoppingItems(items);
    final buffer = StringBuffer()
      ..writeln('PrepPick shopping list')
      ..writeln(PrepWeekRange.label(weekStart))
      ..writeln();

    for (final entry in groups.entries) {
      buffer.writeln(_categoryLabel(entry.key));
      for (final item in entry.value) {
        final check = item.isChecked ? '[x]' : '[ ]';
        final quantity = PrepQuantityFormat.label(item.quantity, item.unit);
        buffer.writeln(
          '$check ${item.name}${quantity == null ? '' : ' - $quantity'}',
        );
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  String mealPlanMessage({
    required DateTime weekStart,
    required Iterable<WeeklyPlanItem> items,
    required MealVariant? Function(WeeklyPlanItem item) mealFor,
  }) {
    final buffer = StringBuffer()
      ..writeln('PrepPick meal plan')
      ..writeln(PrepWeekRange.label(weekStart))
      ..writeln();

    final sorted = items.toList()..sort(_comparePlanItems);
    for (final item in sorted) {
      final meal = mealFor(item);
      buffer.writeln(
        '${item.slot.label(totalOfType: _countOfType(sorted, item.mealType))}: '
        '${meal?.name ?? 'Meal unavailable'}',
      );
    }
    return buffer.toString().trimRight();
  }

  Future<ShareResult> shareText({
    required String subject,
    required String text,
  }) {
    return SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  Future<ShareResult> shareShoppingListPdf({
    required DateTime weekStart,
    required Iterable<ShoppingItem> items,
  }) async {
    final bytes = await shoppingListPdf(weekStart: weekStart, items: items);
    return _sharePdf(bytes, 'preppick-shopping-list.pdf', 'Shopping list');
  }

  Future<ShareResult> shareMealPlanPdf({
    required DateTime weekStart,
    required Iterable<WeeklyPlanItem> items,
    required MealVariant? Function(WeeklyPlanItem item) mealFor,
  }) async {
    final bytes = await mealPlanPdf(
      weekStart: weekStart,
      items: items,
      mealFor: mealFor,
    );
    return _sharePdf(bytes, 'preppick-meal-plan.pdf', 'Meal plan');
  }

  Future<Uint8List> shoppingListPdf({
    required DateTime weekStart,
    required Iterable<ShoppingItem> items,
  }) async {
    final groups = _groupShoppingItems(items);
    final document = _document(title: 'Shopping list');
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 42, 40, 36),
        header: (_) => _pdfHeader('Shopping list', weekStart),
        footer: _pdfFooter,
        build: (_) => [
          for (final entry in groups.entries) ...[
            _pdfSectionHeading(_categoryLabel(entry.key)),
            for (final item in entry.value) _pdfShoppingItem(item),
            pw.SizedBox(height: 14),
          ],
        ],
      ),
    );
    return document.save();
  }

  Future<Uint8List> mealPlanPdf({
    required DateTime weekStart,
    required Iterable<WeeklyPlanItem> items,
    required MealVariant? Function(WeeklyPlanItem item) mealFor,
  }) async {
    final sorted = items.toList()..sort(_comparePlanItems);
    final document = _document(title: 'Meal plan');
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 42, 40, 36),
        header: (_) => _pdfHeader('Meal plan', weekStart),
        footer: _pdfFooter,
        build: (_) => [
          for (final item in sorted)
            _pdfPlanItem(
              item,
              mealFor(item),
              totalOfType: _countOfType(sorted, item.mealType),
            ),
        ],
      ),
    );
    return document.save();
  }

  Future<ShareResult> _sharePdf(
    Uint8List bytes,
    String fileName,
    String subject,
  ) {
    return SharePlus.instance.share(
      ShareParams(
        subject: subject,
        files: [
          XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

  pw.Document _document({required String title}) {
    final document = pw.Document(title: '$_appName $title');
    return document;
  }

  pw.Widget _pdfHeader(String title, DateTime weekStart) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 24),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _appName,
            style: pw.TextStyle(
              color: PdfColors.green700,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            PrepWeekRange.label(weekStart),
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(color: PdfColors.grey300),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionHeading(String label) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 8),
      padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 9),
      color: PdfColors.green50,
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _pdfShoppingItem(ShoppingItem item) {
    final quantity = PrepQuantityFormat.label(item.quantity, item.unit);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 9),
      child: pw.Row(
        children: [
          pw.Text(item.isChecked ? '[x]' : '[ ]', style: _pdfBodyStyle),
          pw.SizedBox(width: 9),
          pw.Expanded(child: pw.Text(item.name, style: _pdfBodyStyle)),
          if (quantity != null) pw.Text(quantity, style: _pdfMutedStyle),
        ],
      ),
    );
  }

  pw.Widget _pdfPlanItem(
    WeeklyPlanItem item,
    MealVariant? meal, {
    required int totalOfType,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              item.slot.label(totalOfType: totalOfType),
              style: pw.TextStyle(
                color: PdfColors.green700,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(meal?.name ?? 'Meal unavailable', style: _pdfBodyStyle),
                if (meal?.protein != null && meal!.protein!.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Text(meal.protein!, style: _pdfMutedStyle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(pw.Context context) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'PrepPick - Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  Map<String, List<ShoppingItem>> _groupShoppingItems(
    Iterable<ShoppingItem> items,
  ) {
    final groups = <String, List<ShoppingItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    return groups;
  }

  String _categoryLabel(String category) =>
      PrepCategoryLabels.labelFor(category);

  int _countOfType(Iterable<WeeklyPlanItem> items, MealType type) =>
      items.where((item) => item.mealType == type).length;

  int _comparePlanItems(WeeklyPlanItem a, WeeklyPlanItem b) {
    final byType = a.mealType.index.compareTo(b.mealType.index);
    return byType != 0 ? byType : a.slotIndex.compareTo(b.slotIndex);
  }

  pw.TextStyle get _pdfBodyStyle =>
      pw.TextStyle(fontSize: 11, color: PdfColors.grey900);

  pw.TextStyle get _pdfMutedStyle =>
      pw.TextStyle(fontSize: 10, color: PdfColors.grey700);
}
