#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // 禁用 Impeller 渲染器（2026-09-06 内存/性能紧急修复）。
  //
  // 实测（profile + VM Service，Intel Core Ultra 5 135H 集显 / OpenGLES）：
  // Dart 堆仅 ~25MB、external ~14KB，但进程私有提交高达 ~1.9GB、CPU/GPU 双高
  // ——占用全部落在 Impeller 的 GPU 内存行为上（OpenGLESSDF 后端 + 液态玻璃
  // 大量离屏玻璃表面），与业务代码无关。App 侧的所有位图/缓存修复都无法触达。
  // 回退到成熟的 Skia 渲染路径后，内存与帧调度回归正常水位。
  // 若后续 Flutter 版本修复了 Windows/Intel 集显上的 Impeller 内存问题，
  // 可删除下面这一行重新启用（Default = 跟随引擎默认）。
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"drawing_notes_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
