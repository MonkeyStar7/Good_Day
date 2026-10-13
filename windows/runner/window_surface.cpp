#include "window_surface.h"
#include <algorithm>
#include <cmath>
#include <flutter/standard_method_codec.h>

WindowSurface::WindowSurface(flutter::BinaryMessenger *messenger, HWND window)
    : window_(window), glass_(std::make_unique<RegionGlass>(window)) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "good_day/window_surface",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    if (call.method_name() == "workArea") {
      MONITORINFO info{};
      info.cbSize = sizeof(info);
      if (!GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                           &info)) {
        result->Error("monitor", "Cannot get work area");
        return;
      }
      const double dpi = std::max(96U, GetDpiForWindow(window_)) / 96.0;
      result->Success(flutter::EncodableMap{
          {flutter::EncodableValue("left"),
           flutter::EncodableValue(info.rcWork.left / dpi)},
          {flutter::EncodableValue("top"),
           flutter::EncodableValue(info.rcWork.top / dpi)},
          {flutter::EncodableValue("width"),
           flutter::EncodableValue((info.rcWork.right - info.rcWork.left) /
                                   dpi)},
          {flutter::EncodableValue("height"),
           flutter::EncodableValue((info.rcWork.bottom - info.rcWork.top) /
                                   dpi)}});
    } else if (call.method_name() == "shape") {
      const auto data =
          call.arguments()
              ? std::get_if<flutter::EncodableMap>(call.arguments())
              : nullptr;
      if (!data) {
        result->Error("shape", "Expected window shape");
        return;
      }
      const auto scale = data->find(flutter::EncodableValue("scale"));
      if (scale != data->end()) {
        const auto value = std::get_if<double>(&scale->second);
        if (value && (*value == 0.75 || *value == 1 || *value == 1.5))
          scale_ = *value;
      }
      const auto notes = data->find(flutter::EncodableValue("notesVisible"));
      if (notes != data->end())
        if (const auto value = std::get_if<bool>(&notes->second))
          notes_ = *value;
      for (const char *key : {"selected", "count"}) {
        const auto it = data->find(flutter::EncodableValue(key));
        if (it != data->end())
          if (const auto value = std::get_if<int32_t>(&it->second)) {
            if (std::string(key) == "selected")
              selected_ = std::clamp(*value, 0, 3);
            else
              count_ = std::clamp(*value, 1, 4);
          }
      }
      ResizeRegion();
      result->Success();
    } else
      result->NotImplemented();
  });
}

WindowSurface::~WindowSurface() { channel_->SetMethodCallHandler(nullptr); }
void WindowSurface::HideGlass() { glass_->Hide(); }
void WindowSurface::RefreshBackdrop() { glass_->Refresh(); }

void WindowSurface::ResizeRegion() {
  if (resizing_)
    return;
  struct ResizeGuard {
    bool &value;
    explicit ResizeGuard(bool &flag) : value(flag) { value = true; }
    ~ResizeGuard() { value = false; }
  } guard(resizing_);
  RECT rect{};
  if (!GetClientRect(window_, &rect) || rect.right <= 0 || rect.bottom <= 0) {
    glass_->Hide();
    return;
  }
  const double factor = scale_ * std::max(96U, GetDpiForWindow(window_)) / 96.0;
  const auto px = [factor](int value) {
    return static_cast<int>(std::lround(value * factor));
  };
  HRGN region = CreateRoundRectRgn(notes_ ? px(56) : 0, 0, rect.right + 1,
                                   rect.bottom + 1, px(40), px(40));
  if (!region)
    return;
  if (notes_)
    for (int index = 0; index < count_; ++index) {
      const int top = px(88 + 68 * index);
      HRGN tab = CreateRoundRectRgn(index == selected_ ? 0 : px(6), top, px(64),
                                    top + px(58), px(16), px(16));
      if (tab) {
        CombineRgn(region, region, tab, RGN_OR);
        DeleteObject(tab);
      }
    }
  // Clip acrylic to the paper and notes, leaving the gaps truly outside the
  // window instead of filling them with a rectangular translucent frame.
  if (!SetWindowRgn(window_, region, TRUE))
    DeleteObject(region);
  glass_->Update(scale_, notes_, selected_, count_);
}
