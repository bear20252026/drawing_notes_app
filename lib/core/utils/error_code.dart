// 由 Claude 团队生成 | Drawing Notes App

/// 诊断面上唯一的「错误代码」判据（审计 CTL-03 解锁顺序第①步）。
///
/// 缘起：出货命令加 `--obfuscate` 之前，`lib/` 里有 **28 处**在运行时读类型名
/// （22 处 `e.runtimeType.toString()` + 6 处 `${...runtimeType}`，2026-10-17 实测；
/// 另有 17 行 `runtimeType` 是 `operator ==` 里的同类型比较，那部分不受混淆影响、
/// 本批一行没动）。这 28 处喂的正是**用户可见面与审计面**：粘贴失败 / 插图失败 /
/// 打开链接失败三条 snackbar 的占位符、`saveFailure` 芯片的 `errorKind`（AW13 那条
/// 「保存失败可见化」本体）、`AuditLogger` 的 `detail`，以及 `main.dart` 把类型名
/// 拼进**审计 action id**。Flutter 文档明写「依赖类名做匹配的代码会失效」，举的
/// 就是 `runtimeType.toString()` 这个例子 ⇒ 混淆一开，这 28 条同时变成每次构建都
/// 不同的随机串，而**没有任何绿灯看得见**（`flutter test` 与 `-d windows` 的 smoke
/// 都跑非混淆编译，只有装到用户机器上才现形）。
///
/// 形状为什么是「异常自带一个码」而不是「一个文件里写一条 `is` 链」：
/// 第一版确实是 `is` 链，被本仓自己的 `规则2：零循环依赖` 判红——异常类散在
/// `core/documents`、`core/storage`、`core/security`、`core/sync`、`infrastructure/v2`、
/// `features/notes/application` 六个模块里，而**这些模块全都 import `core/utils`**。
/// 一份「认识所有异常」的枢纽文件必然与它们互相引用 ⇒ 谁不稳定？都不稳定。
/// 正确方向是让**类型自己报名字**（下面的 [CodedFailure]）：本文件因此几乎不 import
/// `lib/` 里的东西——只有 `document_budgets.dart` 一个单向例外（下面 `errorCode()` 里
/// 写明了为什么），实测 Martin instability `I=0.04`（Ca=23、Ce=1，2026-10-17 由
/// `architecture_test` 规则3b 打印），落在本目录「utils 应为稳定层（I≤0.4）」之内；
/// `is` 关系也从「判序」变成「派发」，子类忘写码会被「类块里必须有自己的 getter」
/// 与行为用例一起抓到。
///
/// 三条取舍写在这儿，不散进 28 个调用点：
///  - **信息量下降是故意的**。以前 snackbar 印 `FileSystemException`，现在印
///    `io_file_system`。拿「今天读起来更陌生」换「混淆后仍然可读」——一个每次出包
///    都改名的诊断键等于没有键。
///  - **码里永远不带 message**。`FileSystemException.toString()` 含**路径**，
///    `WebDavSyncException` 含 URL ⇒ 拼进 snackbar 与审计就是把用户文件名往外抛
///    （H-04「不泄漏内部结构」；`save_scheduler.dart` 文件头立的同一条纪律）。
///    所以标准库那几条只给类级别代码；自定义异常的 `toString()` 里带不带东西
///    与这里无关——本文件不返回它。
///  - **认不出来就明说认不出来**（[errorCode] 末尾的 `other`）。宁可少一档信息，
///    也不要在混淆后给出一个每次出包都不同的名字。
///
/// 覆盖由 `test/architecture/error_code_coverage_gate_test.dart` 钉成机器事实：
/// `lib/` 里每个自定义异常类都必须实现 [CodedFailure]、码必须互不相同。
library;

import 'dart:async';
import 'dart:io';

import 'package:drawing_notes_app/core/storage/document_budgets.dart'
    show DocumentBudgetException, DocumentIncompleteLoadException;

/// 异常类型自己报出来的**稳定诊断码**（编译期字面量，与类名无关）。
///
/// 约定三条，都由门禁逐条验：
///  - 码是小写 `[a-z_]`，不带 message、路径、凭据（行为用例直接断言）；
///  - **全库唯一**：两个异常共用一个码 = 把两类失败合并成一类；
///  - **子类必须自己写一条**，不能靠继承父类的码——那样 `webdav_precondition_failed`
///    会一路报成 `webdav_sync`，正是这条判据要防的「读不出来被答成没有」。
abstract class CodedFailure {
  String get errorCode;
}

/// 把异常换算成**稳定代码**：不返回 message、路径，也不返回运行时读到的类型名。
String errorCode(Object error) {
  // 自定义异常：类型自己报名字，本文件不需要知道有哪些类型。
  if (error is CodedFailure) return error.errorCode;
  // 唯一的两个例外：`document_budgets.dart` 立了「本文件零项目内 import」的纪律
  // （文件头与 :213 各写一次，为的是 isolate 编码路径零依赖引用），它**不能** import 本文件，
  // 于是这两个类只能由这边单向认识它们。这条例外不破坏上面的形状——门禁
  // `error_code_coverage_gate_test.dart` 断言「枢纽 import 的每个 `lib/` 文件自己必须
  // 零项目内 import」：单向、不成环，才允许这一段 `is` 链存在。
  if (error is DocumentBudgetException) return 'document_budget';
  if (error is DocumentIncompleteLoadException) return 'document_incomplete_load';
  // 标准库：只列 `lib/` 里真会出现的（逐个 grep 实测；门禁的类数下限钉住这份清点）。
  if (error is FileSystemException) return 'io_file_system';
  if (error is SocketException) return 'io_socket';
  if (error is TimeoutException) return 'async_timeout';
  if (error is FormatException) return 'core_format';
  if (error is ArgumentError) return 'core_argument';
  if (error is StateError) return 'core_state';
  if (error is TypeError) return 'core_type';
  // 兜底也是判据：宁可说「不知道是哪一类」，也不要在混淆后给出一个每次出包都不同的名字。
  return 'other';
}
