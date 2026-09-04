// 同步刷新修复（SyncFix）——首页数据变更通知与路由可见性兜底。
//
// 原 `lib/fix/security_and_sync_fix.dart` PART 1（M1 目录迁移，行为零变化）。

import 'package:flutter/material.dart';

// PART 1 · SyncFix —— 同步刷新修复
// ===========================================================================

/// 同步修复工具集。
///
/// 根因：首页只监听 `AppServices.dataVersion`（ValueNotifier），
/// 而笔记本页内部的新建/保存路径没有调用 `bumpDataVersion`，
/// 且首页在 IndexedStack 中保活，切回时也不刷新。
abstract final class SyncFix {
  /// 全局路由观察者。注册到 MaterialApp.navigatorObservers 后，
  /// 首页可通过 [SyncFixRouteAware] 在重新可见时自动刷新。
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  /// 数据变更统一通知入口。
  ///
  /// 所有"新建 / 修改 / 删除"落盘成功后调用一次；传入项目现有的
  /// `services.bumpDataVersion`（-tear-off）即可，不引入新状态源。
  static void notifyDataChanged(VoidCallback? bumpDataVersion) {
    bumpDataVersion?.call();
  }
}

/// 首页（或任意保活页面）混入后，页面重新可见时自动回调 [onPageVisibleAgain]。
///
/// 用法（在 HomePage State 中）：
///   `class _HomePageState extends State<HomePage> with SyncFixRouteAware` {
///     @override
///     void onPageVisibleAgain() => _refresh();
///     @override
///     void didChangeDependencies() {
///       super.didChangeDependencies();
///       SyncFix.routeObserver.subscribe(
///           this, ModalRoute.of(context)! as PageRoute);
///     }
///     @override
///     void dispose() {
///       SyncFix.routeObserver.unsubscribe(this);
///       super.dispose();
///     }
///   }
mixin SyncFixRouteAware<T extends StatefulWidget> on State<T>
    implements RouteAware {
  void onPageVisibleAgain();

  @override
  void didPopNext() => onPageVisibleAgain();

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}
}
