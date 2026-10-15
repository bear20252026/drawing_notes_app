// 批次 D（第三轮专家审计 2026-10-13）：写路径「改名换入」这一步的唯一执行点。
//
// 两条写腿（画布 `StorageWritePipeline.replaceWithTemp`、块文档
// `NoteBlockDocStore._writeFileAtomic`）各自都有「首选 rename ⇒ 被拒则先删目标
// 再换入」这条兜底，也都各自有一个测试钩子决定「这一次要不要拒」。但**拒绝
// 这个动作本身**的形状只能定义一次：不执行改名、tmp 与目标都原地不动、抛
// `errno 5` 的 FileSystemException。两处各写一遍的话，「测试注入的失败」与
// 「真机的失败」会长成两个形状，注入就不再是在验那条腿。
//
// 为什么这条兜底的成功分支必须靠注入才能测（本机 2026-10-15 实测，不是推测）：
// - 目标已存在时，Windows 的 `File.rename` **直接成功**（它带 replace 语义）；
// - 真正会拒的是别人持有目标句柄：rename 报 `code 5 拒绝访问`，而同一个句柄
//   让紧随的 `delete` 报 `code 32 另一个程序正在使用此文件`；
// - ⇒ 兜底腿只有在「持句柄者刚好在两次调用之间放手」的窗口里才走得通。
// 用 sleep 去赌那个窗口，赌赢的测试同样是假的；Linux CI 更是永远走不到这条腿。

import 'dart:io';

/// 把 [tmp] 换入 [destination]。[fault] 是测试钩子（生产恒 null）：返回 true
/// 表示**这一次**改名被系统拒绝——于是不执行改名，只抛出与真机同形状的异常，
/// tmp 与目标都留在原地。返回 false 或没有钩子时走真实 `rename`。
Future<void> renameIntoPlace(
  File tmp,
  File destination,
  bool Function(String tmpPath, String destinationPath)? fault,
) async {
  if (fault?.call(tmp.path, destination.path) ?? false) {
    throw FileSystemException(
      '注入：改名被系统拒绝',
      destination.path,
      const OSError('拒绝访问。', 5),
    );
  }
  await tmp.rename(destination.path);
}
