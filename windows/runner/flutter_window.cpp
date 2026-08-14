#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>
#include <variant>
#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // (note)
  // Dart  MethodChannel('gov.drawingnotes/clipboard')  RGBA 
  // (note)
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "gov.drawingnotes/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "copyPng") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("bad_args", "missing arguments");
          return;
        }
        auto it_w = args->find(flutter::EncodableValue("width"));
        auto it_h = args->find(flutter::EncodableValue("height"));
        auto it_r = args->find(flutter::EncodableValue("rgba"));
        if (it_w == args->end() || it_h == args->end() ||
            it_r == args->end()) {
          result->Error("bad_args", "missing width/height/rgba");
          return;
        }
        const auto width = std::get<int>(it_w->second);
        const auto height = std::get<int>(it_h->second);
        const auto& rgba = std::get<std::vector<uint8_t>>(it_r->second);
        if (width <= 0 || height <= 0 ||
            rgba.size() < (size_t)(width * height * 4)) {
          result->Error("bad_args", "invalid pixel data");
          return;
        }
        // (note)
        const int bpp = 32;
        const int rowSize = ((width * bpp + 31) / 32) * 4;
        const int imgSize = rowSize * height;
        const size_t total = sizeof(BITMAPINFOHEADER) + imgSize;
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, total);
        if (!hMem) {
          result->Error("alloc_failed", "GlobalAlloc failed");
          return;
        }
        auto* dst = static_cast<uint8_t*>(GlobalLock(hMem));
        auto* bih = reinterpret_cast<BITMAPINFOHEADER*>(dst);
        bih->biSize = sizeof(BITMAPINFOHEADER);
        bih->biWidth = width;
        bih->biHeight = height;  // (note)
        bih->biPlanes = 1;
        bih->biBitCount = bpp;
        bih->biCompression = BI_RGB;
        bih->biSizeImage = imgSize;
        auto* px = dst + sizeof(BITMAPINFOHEADER);
        // RGBA -> BGRA
        for (int y = 0; y < height; y++) {
          int srcRow = (height - 1 - y) * width * 4;
          int dstRow = y * rowSize;
          for (int x = 0; x < width; x++) {
            int si = srcRow + x * 4;
            int di = dstRow + x * 4;
            px[di + 0] = rgba[si + 2];  // B
            px[di + 1] = rgba[si + 1];  // G
            px[di + 2] = rgba[si + 0];  // R
            px[di + 3] = 0;             // (note)
          }
        }
        GlobalUnlock(hMem);
        if (!OpenClipboard(nullptr)) {
          GlobalFree(hMem);
          result->Error("clipboard_busy", "OpenClipboard failed");
          return;
        }
        EmptyClipboard();
        SetClipboardData(CF_DIB, hMem);
        CloseClipboard();
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
