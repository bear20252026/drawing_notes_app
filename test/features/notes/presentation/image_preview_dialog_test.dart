import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/presentation/image_preview_dialog.dart';

void main() {
  group('showImagePreviewDialog', () {
    testWidgets('空 src 不弹窗', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showImagePreviewDialog(context, src: ''),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 空 src 不应弹出 dialog
      expect(find.byType(AlertDialog), findsNothing);
      // 也不应有 InteractiveViewer（预览弹窗的核心组件）
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('非空 src 弹出预览弹窗', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showImagePreviewDialog(
                  context,
                  src: 'https://example.com/image.png',
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 应弹出预览弹窗
      expect(find.byType(InteractiveViewer), findsOneWidget);
      // 应显示关闭按钮
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('关闭按钮关闭弹窗', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showImagePreviewDialog(
                  context,
                  src: 'https://example.com/image.png',
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // 关闭弹窗
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 弹窗应关闭
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });
}
