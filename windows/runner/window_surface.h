#ifndef GOOD_DAY_WINDOW_SURFACE_H_
#define GOOD_DAY_WINDOW_SURFACE_H_
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <windows.h>

class WindowSurface {
public:
  WindowSurface(flutter::BinaryMessenger *messenger, HWND window);
  ~WindowSurface();
  void ResizeRegion();

private:
  HWND window_;
  double scale_ = 1;
  bool notes_ = true;
  int selected_ = 0, count_ = 3;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
