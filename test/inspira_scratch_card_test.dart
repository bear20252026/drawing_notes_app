// InspiraScratchCard 组件测试：擦除揭示、阈值回调、无障碍降级。
import 'package:drawing_notes_app/shared/widgets/inspira/inspira_scratch_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required Widget child,
  bool disableAnimations = false,
  double threshold = 0.62,
  String? overlayText,
  VoidCallback? onRevealed,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 220,
              child: InspiraScratchCard(
                overlayText: overlayText,
                revealThreshold: threshold,
                onRevealed: onRevealed,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

Finder overlayFinder() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is InspiraScratchOverlayPainter,
    );

void main() {
  testWidgets('初始状态覆盖层存在', (tester) async {
    var revealed = false;
    await tester.pumpWidget(
      _host(
        overlayText: '刮开查看',
        onRevealed: () => revealed = true,
        child: const FlutterLogo(size: 80),
      ),
    );
    expect(overlayFinder(), findsOneWidget);
    expect(revealed, isFalse);
  });

  testWidgets('单行刮擦不触发回调，全面刮擦触发且仅一次', (tester) async {
    var revealedCount = 0;
    await tester.pumpWidget(
      _host(
        threshold: 0.5,
        onRevealed: () => revealedCount++,
        child: const SizedBox.expand(),
      ),
    );

    final card = tester.getRect(find.byType(InspiraScratchCard));

    // 单行横扫：约 1/18 网格 → 远低于 50%。
    await tester.dragFrom(
      card.centerLeft + const Offset(6, 0),
      Offset(card.width - 12, 0),
    );
    await tester.pump();
    expect(revealedCount, 0, reason: '单行不应达到揭示阈值');

    // 蛇形扫过大部分区域 → 触发一次。
    final gesture =
        await tester.startGesture(card.topLeft + const Offset(10, 8));
    for (var row = 0; row < 16; row++) {
      final dy = 8.0 + row * ((card.height - 16) / 16);
      final x = row.isEven
          ? card.left + card.width - 12
          : card.left + 12;
      await gesture.moveTo(
        Offset(x, card.top + dy),
        timeStamp: Duration(milliseconds: 200 + row * 60),
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(revealedCount, 1);
  });

  testWidgets('低阈值时短划即触发', (tester) async {
    var revealed = false;
    await tester.pumpWidget(
      _host(
        threshold: 0.02,
        onRevealed: () => revealed = true,
        child: const SizedBox.expand(),
      ),
    );
    final card = tester.getRect(find.byType(InspiraScratchCard));
    await tester.dragFrom(
      card.centerLeft + const Offset(4, 0),
      Offset(card.width - 8, 0),
    );
    await tester.pumpAndSettle();
    expect(revealed, isTrue);
  });

  testWidgets('disableAnimations 时达到阈值直接消失（无淡出等待）', (tester) async {
    var revealed = false;
    await tester.pumpWidget(
      _host(
        disableAnimations: true,
        threshold: 0.02,
        onRevealed: () => revealed = true,
        child: const SizedBox.expand(),
      ),
    );
    expect(overlayFinder(), findsOneWidget);

    final card = tester.getRect(find.byType(InspiraScratchCard));
    await tester.dragFrom(
      card.centerLeft + const Offset(4, 0),
      Offset(card.width - 8, 0),
    );
    await tester.pump(); // 无淡出：一帧内覆盖层应已移除

    expect(revealed, isTrue);
    expect(overlayFinder(), findsNothing);
  });
}
