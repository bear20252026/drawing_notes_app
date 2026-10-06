import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';
import 'package:drawing_notes_app/features/drawing/presentation/pdf_export_panel.dart';

void main() {
  testWidgets(
    'PDF quality and tiled layout options survive selection and export',
    (tester) async {
      PdfExportSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showPdfExportPanel(
                    context,
                    hasMultiplePages: false,
                    pageCount: 1,
                    showLayout: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final quality = tester.widget<SegmentedButton<PdfQuality>>(
        find.byType(SegmentedButton<PdfQuality>),
      );
      quality.onSelectionChanged!({PdfQuality.lossless});
      final layout = tester.widget<SegmentedButton<PdfLayout>>(
        find.byType(SegmentedButton<PdfLayout>),
      );
      layout.onSelectionChanged!({PdfLayout.tiled});
      await tester.pumpAndSettle();
      final order = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      order.onSelectionChanged!({true});
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
        true,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.quality, PdfQuality.lossless);
      expect(result!.layout, PdfLayout.tiled);
      expect(result!.columnMajor, isTrue);
      expect(result!.footer, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
