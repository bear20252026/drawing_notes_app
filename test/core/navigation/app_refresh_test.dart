// AppRefresh（同步刷新修复）单测：
// notifyDataChanged 空回调/有效回调解耦 + AppRefreshRouteAware 路由感知
// （didPopNext 触发刷新，didPush/didPushNext/didPop 不触发）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/navigation/app_refresh.dart';

/// 最小可路由感知页面（按 app_refresh.dart 文档用法接入 routeObserver）。
class _AwareHome extends StatefulWidget {
  const _AwareHome({required this.onVisibleAgain});

  final VoidCallback onVisibleAgain;

  @override
  State<_AwareHome> createState() => _AwareHomeState();
}

class _AwareHomeState extends State<_AwareHome>
    with AppRefreshRouteAware<_AwareHome> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppRefresh.routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    AppRefresh.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void onPageVisibleAgain() => widget.onVisibleAgain();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('AppRefresh.notifyDataChanged（表驱动）', () {
    test('null 回调：不抛错、不调用（未装配 bumpDataVersion 的窗口期安全）', () {
      expect(() => AppRefresh.notifyDataChanged(null), returnsNormally);
    });

    test('非空回调：被调用且恰好一次', () {
      var calls = 0;

      AppRefresh.notifyDataChanged(() => calls++);

      expect(calls, 1);
    });

    test('回调内抛错正常向上传播（通知入口不吞业务异常）', () {
      expect(
        () => AppRefresh.notifyDataChanged(() => throw StateError('boom')),
        throwsStateError,
      );
    });

    test('routeObserver 为共享单例（多处注册指向同一观察者）', () {
      expect(identical(AppRefresh.routeObserver, AppRefresh.routeObserver), isTrue);
      expect(AppRefresh.routeObserver, isA<RouteObserver<ModalRoute<void>>>());
    });
  });

  group('AppRefreshRouteAware 路由钩子（直接驱动）', () {
    test('didPopNext 触发 onPageVisibleAgain', () {
      var fired = 0;
      // 直接实例化 State（无需绑定 widget 树）驱动 mixin 的路由回调分支。
      final holder = _HookState(onVisible: () => fired++);

      holder.didPopNext();

      expect(fired, 1);
    });

    test('didPush / didPush / didPushNext / didPop 均不触发刷新', () {
      var fired = 0;
      final holder = _HookState(onVisible: () => fired++);

      holder.didPush();
      holder.didPushNext();
      holder.didPop();

      expect(fired, 0, reason: '仅"从下级路由返回"才刷新');
    });
  });

  group('AppRefreshRouteAware 集成（真实路由栈）', () {
    testWidgets('被覆盖不刷新，pop 返回时刷新恰好一次', (tester) async {
      var visibleAgain = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [AppRefresh.routeObserver],
          home: _AwareHome(onVisibleAgain: () => visibleAgain++),
        ),
      );

      expect(visibleAgain, 0, reason: '首帧渲染不触发刷新');

      final context = tester.element(find.byType(_AwareHome));
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();

      expect(visibleAgain, 0, reason: 'didPushNext（被覆盖）不触发刷新');

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(visibleAgain, 1, reason: 'didPopNext（返回本页）触发一次刷新');
    });
  });
}

/// 无 widget 依赖的钩子 State（直接调用路由回调，验证 mixin 分支）。
class _HookWidget extends StatefulWidget {
  const _HookWidget();

  @override
  State<_HookWidget> createState() => _HookState();
}

class _HookState extends State<_HookWidget>
    with AppRefreshRouteAware<_HookWidget> {
  _HookState({this.onVisible});

  VoidCallback? onVisible;

  @override
  void onPageVisibleAgain() => onVisible?.call();

  @override
  Widget build(BuildContext context) => const SizedBox();
}
