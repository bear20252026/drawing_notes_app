// M10-B 冒烟测试：WebDavSyncSettingsPage 渲染骨架 + 表单字段。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

import '../../../helpers/wait_until.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: child,
  );
}

// ---- T-08（审计 2026-09-27）就绪判据：固定 pump 计数 → 观测完成条件本身 ----
//
// 原写法是每处两段 `pump(100ms)` 的**盲泵**——把「泵够了 200ms」当成「加载
// 完了」的时序判据：慢机器上 200ms 仍没回灌完就假红，快机器上纯空耗 fake
// 时钟。现改为 `helpers/wait_until.dart` 的 `tester.pumpUntil`（早退 + 有界）。
// 每条判据都刻意**不等于**紧随其后的 expect：探针只看「加载/保存这条链路
// 自己结束了没有」，原断言的牙齿一条没少（超时后 pumpUntil 静默返回，
// expect 照样带原始信息失败）。

/// 表单骨架已建完：`保存配置` 与标题/输入框/`立即同步` 同批渲染，
/// 且它本身不是任何 expect 的对象——用它作「首帧已出」的信号最不吃断言。
bool _formBuilt() => find.text('保存配置').evaluate().isNotEmpty;

/// `_loadConfig()` 已 setState 落树：口令**存在性** bool 置位后，两个口令框
/// 才换成「已保存 · 留空保持不变」占位提示（配置/机密两次 await 之后唯一
/// 的可见完成信号）。这里只要求**至少出现一个**——「恰好两个」仍由用例
/// 自己的 `findsNWidgets(2)` 裁决，不把断言整条抄进判据。
bool _secretsLoaded() => find.text('已保存 · 留空保持不变').evaluate().isNotEmpty;

/// `_save()` 全链结束的可见信号：成功提示（两条文案变体）与失败/取消提示
/// 都在 `await _sync.save(...)` **之后**才弹，故 SnackBar 入树即代表写盘
/// 动作已尘埃落定——随后 `store.read()` 读到的必然是最终态。
bool _saveSettled() => find.byType(SnackBar).evaluate().isNotEmpty;

void main() {
  testWidgets('WebDavSyncSettingsPage 渲染：表单字段 + 按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          // C-05：页面只接收注入的 SyncController，装配在测试里完成。
          syncController: SyncController(
            configStore: WebDavConfigStore(),
            secretStore: MemorySyncSecretStore(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpUntil(_formBuilt);

    expect(find.text('WebDAV 同步'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('立即同步'), findsOneWidget);
  });

  // S-03（审计 2026-09-27）方案 A：口令不回填控制器。
  //
  // 回归锁一：明文驻留 = 本审计条目的全部问题——`TextEditingController`
  // 持有的字符串绕过 `SessionSecrets.clearAll()`（切后台只清各 store 的
  // 会话缓存，清不到 widget 树），堆转储可直接读出。故断言输入框必须为空、
  // 且存在性只以占位提示呈现。
  testWidgets('S-03：已存口令不回填输入框，改用占位提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemorySyncSecretStore(
      const SyncSecrets(
        webdavPassword: 'fixture-pass',
        syncPassphrase: 'fixture-phrase',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          syncController: SyncController(
            configStore: WebDavConfigStore(),
            secretStore: store,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpUntil(_formBuilt);
    await tester.pumpUntil(_secretsLoaded);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    // 密码 / 同步口令是第 3、4 个输入框（前两个是 URL / 用户名）。
    expect(fields[2].controller!.text, isEmpty);
    expect(fields[3].controller!.text, isEmpty);
    // 明文绝不出现在任何可见文本里。
    expect(find.text('fixture-pass'), findsNothing);
    expect(find.text('fixture-phrase'), findsNothing);
    // 存在性以占位提示呈现（hintText 只在框空时渲染，此处两框皆空）。
    expect(find.text('已保存 · 留空保持不变'), findsNWidgets(2));
  });

  // 回归锁二：空值 = 沿用已存。方案 A 把「未改」与「清空」合并成了空值，
  // 若哪天有人把保存写回成 `空 → null`，用户留空点保存就会静默抹掉口令，
  // 下一次同步直接认证失败。这条锁死「留空保存后原值仍在」。
  testWidgets('S-03：留空点保存，已存口令不被抹掉', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemorySyncSecretStore(
      const SyncSecrets(
        webdavPassword: 'fixture-pass',
        syncPassphrase: 'fixture-phrase',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          syncController: SyncController(
            configStore: WebDavConfigStore(),
            secretStore: store,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpUntil(_formBuilt);
    await tester.pumpUntil(_secretsLoaded);

    await tester.tap(find.text('保存配置'));
    // T-08：成功/失败提示都在 `await _sync.save(...)` 之后才弹，故 SnackBar
    // 入树即写盘已尘埃落定——取代原「两段 300ms 盲泵」，store.read 断言不变。
    await tester.pump();
    await tester.pumpUntil(_saveSettled);

    final saved = await store.read();
    expect(saved.webdavPassword, 'fixture-pass');
    expect(saved.syncPassphrase, 'fixture-phrase');
  });

  // 回归锁三：输入新值覆盖旧值——确保「留空沿用」没有把覆盖能力一起关掉。
  testWidgets('S-03：输入新口令覆盖旧值', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemorySyncSecretStore(
      const SyncSecrets(
        webdavPassword: 'old-pass',
        syncPassphrase: 'old-passphrase',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          syncController: SyncController(
            configStore: WebDavConfigStore(),
            secretStore: store,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpUntil(_formBuilt);
    await tester.pumpUntil(_secretsLoaded);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    // 直接写 controller：两个口令框当前为空，按 index 定位最稳
    //（enterText 需要先 focus，空框无法用 find.widgetWithText 唯一定位）。
    fields[2].controller!.text = 'new-pass';
    fields[3].controller!.text = 'new-passphrase';
    await tester.pump();

    await tester.tap(find.text('保存配置'));
    // T-08：同上——以「保存结果提示已入树」为写盘完成判据，取代两段盲泵。
    await tester.pump();
    await tester.pumpUntil(_saveSettled);

    final saved = await store.read();
    expect(saved.webdavPassword, 'new-pass');
    expect(saved.syncPassphrase, 'new-passphrase');
  });
}
