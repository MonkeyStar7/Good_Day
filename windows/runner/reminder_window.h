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
  void PaintButton(const DRAWITEMSTRUCT &item);
  void Layout();
  int Scale(int value) const;
  HWND owner_ = nullptr;
  HWND window_ = nullptr;
  std::array<HWND, 5> buttons_{};
  UINT dpi_ = 96;
  int accent_rgb_ = 0x365D46;
  bool saving_ = false;
  bool owner_enabled_ = true;
  std::wstring title_, time_, date_, clock_, notes_, timing_, error_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
