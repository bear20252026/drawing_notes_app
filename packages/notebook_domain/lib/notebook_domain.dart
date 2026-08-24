// notebook_domain——纯 Dart 笔记本安全域（V2 引导——批次 A）。
//
// 专家目标架构（ADR-001）：NotebookSession/KeyHandle/LockPolicy/UseCases/
// Ports 的唯一可信来源——禁 Widget/BuildContext/Platform/File。
library;

export 'src/ports/repository_ports.dart';
export 'src/session/notebook_session.dart';
export 'src/session/key_handle.dart';
export 'src/session/lock_policy.dart';
