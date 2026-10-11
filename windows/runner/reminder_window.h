#ifndef GOOD_DAY_REMINDER_WINDOW_H_
#define GOOD_DAY_REMINDER_WINDOW_H_

#include <array>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <string>
#include <windows.h>

class ReminderWindow {
public:
  ReminderWindow(flutter::BinaryMessenger *messenger, HWND owner);
  ~ReminderWindow();

private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  bool Show(const flutter::EncodableMap &data);
  void Close();
  void Submit(int minutes);
  void Paint();
  void Layout();
  int Scale(int value) const;
  HWND owner_ = nullptr;
  HWND window_ = nullptr;
  std::array<HWND, 4> buttons_{};
  HFONT body_font_ = nullptr;
  HFONT title_font_ = nullptr;
  UINT dpi_ = 96;
  bool saving_ = false;
  bool owner_enabled_ = true;
  std::wstring title_, time_, notes_, timing_, error_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
