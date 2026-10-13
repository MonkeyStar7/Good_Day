#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
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
  window_surface_ = std::make_unique<WindowSurface>(
      flutter_controller_->engine()->messenger(), GetHandle());
  reminder_window_ = std::make_unique<ReminderWindow>(
      flutter_controller_->engine()->messenger(), GetHandle());
  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "good_day/lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  backdrop_refresh_ = std::make_unique<BackdropRefresh>(GetHandle(), [this]() {
    window_surface_->RefreshBackdrop();
    flutter_controller_->ForceRedraw();
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  backdrop_refresh_ = nullptr;
  window_surface_ = nullptr;
  reminder_window_ = nullptr;
  lifecycle_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (backdrop_refresh_ && backdrop_refresh_->HandleMessage(message, wparam))
    return 0;
  if (window_surface_ && message == WM_SHOWWINDOW && !wparam)
    window_surface_->HideGlass();
  if (window_surface_ &&
      (message == WM_SIZE || message == WM_DPICHANGED ||
       message == WM_WINDOWPOSCHANGED || message == WM_ACTIVATE))
    window_surface_->ResizeRegion();
  if (lifecycle_channel_) {
    if (message == WM_POWERBROADCAST &&
        (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND)) {
      lifecycle_channel_->InvokeMethod("resume", nullptr);
    } else if (message == WM_TIMECHANGE) {
      lifecycle_channel_->InvokeMethod("timeChanged", nullptr);
    }
  }
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
