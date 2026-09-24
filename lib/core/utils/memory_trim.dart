import 'dart:ffi';
import 'dart:io' show Platform;

/// Windows 进程工作集归还（2026-09-24 内存优化批次 ④）。
///
/// Dart GC 回收后通常不立即把物理页还给操作系统，任务管理器里的「工作集」
/// 会长期停在高位（高但稳定，非泄漏）。本工具在切后台/最小化等释放缓存后
/// 调用 `SetProcessWorkingSetSize(handle, -1, -1)`，促使系统回收物理页、
/// 任务管理器数字立即回落。这是**纯观感优化**：页面数据仍在后备内存，
/// 回到前台首次触碰时由系统自动换回，不影响任何功能。
///
/// 句柄传 `GetCurrentProcess()` 的伪句柄常量 `-1`（Win32 语义，无需真实
/// 句柄）。非 Windows 平台为 no-op；任何 FFI 失败均静默吞掉——观感优化
/// 不允许影响功能。调用方须在释放自身大块缓存（图层位图/图片缓存）之后
/// 调用，否则归还的页会被立刻换回。
void trimProcessWorkingSet() {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setWorkingSetSize = kernel32.lookupFunction<
        Int32 Function(IntPtr, IntPtr, IntPtr),
        int Function(int, int, int)>('SetProcessWorkingSetSize');
    // 伪句柄 -1 = GetCurrentProcess()；dwMinimum/dwMaximum 传 -1：
    // 请求系统从进程工作集中移除尽可能多的页。
    setWorkingSetSize(-1, -1, -1);
  } catch (_) {
    // 静默：见上，观感优化失败无功能影响。
  }
}
