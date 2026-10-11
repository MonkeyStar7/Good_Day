#include "reminder_window.h"
#include <flutter/standard_method_codec.h>
#include <fstream>
#include <iostream>
#include <stdexcept>

void Check(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
HWND CurrentReminder() {
  HWND result = nullptr;
  EnumWindows(
      [](HWND candidate, LPARAM target) -> BOOL {
        DWORD process = 0;
        GetWindowThreadProcessId(candidate, &process);
        wchar_t name[64]{};
        GetClassNameW(candidate, name, 64);
        if (process == GetCurrentProcessId() &&
            std::wstring(name) == L"GoodDay.Reminder") {
          *reinterpret_cast<HWND *>(target) = candidate;
          return FALSE;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&result));
  return result;
}
class Messenger : public flutter::BinaryMessenger {
public:
  flutter::BinaryMessageHandler handler;
  mutable int action = -1;
  void SetMessageHandler(const std::string &,
                         flutter::BinaryMessageHandler value) override {
    handler = value;
  }
  void Send(const std::string &, const uint8_t *data, size_t size,
            flutter::BinaryReply reply = nullptr) const override {
    const auto call =
        flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(data,
                                                                     size);
    Check(call && call->method_name() == "action", "native action missing");
    action = std::get<int32_t>(*call->arguments());
    if (reply)
      reply(nullptr, 0);
  }
  void Call(const char *method, flutter::EncodableMap args = {}) {
    const auto bytes =
        flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
            flutter::MethodCall<flutter::EncodableValue>(
                method, std::make_unique<flutter::EncodableValue>(args)));
    bool replied = false;
    handler(bytes->data(), bytes->size(),
            [&](const uint8_t *data, size_t size) {
              Check(data && size > 0 && data[0] == 0, "native method failed");
              replied = true;
            });
    Check(replied, "native method not replied");
  }
};
void Capture(HWND window, const char *path) {
  RedrawWindow(window, nullptr, nullptr,
               RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
  RECT bounds{};
  GetWindowRect(window, &bounds);
  const int width = bounds.right - bounds.left,
            height = bounds.bottom - bounds.top;
  HDC source = GetWindowDC(window), destination = CreateCompatibleDC(source);
  HBITMAP bitmap = CreateCompatibleBitmap(source, width, height);
  HGDIOBJ original = SelectObject(destination, bitmap);
  BitBlt(destination, 0, 0, width, height, source, 0, 0, SRCCOPY);
  SelectObject(destination, original);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
  Check(GetDIBits(destination, bitmap, 0, height, pixels.data(), &info,
                  DIB_RGB_COLORS) != 0,
        "capture failed");
  BITMAPFILEHEADER file{};
  file.bfType = 0x4D42;
  file.bfOffBits = sizeof(file) + sizeof(BITMAPINFOHEADER);
  file.bfSize = file.bfOffBits + static_cast<DWORD>(pixels.size());
  std::ofstream output(path, std::ios::binary);
  output.write(reinterpret_cast<const char *>(&file), sizeof(file));
  output.write(reinterpret_cast<const char *>(&info.bmiHeader),
               sizeof(BITMAPINFOHEADER));
  output.write(reinterpret_cast<const char *>(pixels.data()), pixels.size());
  Check(output.good(), "capture write failed");
  DeleteObject(bitmap);
  DeleteDC(destination);
  ReleaseDC(window, source);
}
int main(int argc, char **argv) {
  HWND owner = CreateWindowW(L"STATIC", L"Good Day isolated native test",
                             WS_OVERLAPPEDWINDOW, 20, 20, 340, 500, nullptr,
                             nullptr, GetModuleHandle(nullptr), nullptr);
  try {
    Check(owner != nullptr, "test owner creation failed");
    Messenger messenger;
    ReminderWindow reminder(&messenger, owner);
    const flutter::EncodableMap args = {
        {flutter::EncodableValue("title"),
         flutter::EncodableValue("准备开始下午的学习")},
        {flutter::EncodableValue("time"),
         flutter::EncodableValue("事件时间：2026-10-12 09:00")},
        {flutter::EncodableValue("notes"),
         flutter::EncodableValue("准备好笔记，先复习昨天的内容。")},
        {flutter::EncodableValue("date"),
         flutter::EncodableValue("2026 年 10 月 12 日")},
        {flutter::EncodableValue("clock"), flutter::EncodableValue("09:00")},
        {flutter::EncodableValue("timing"),
         flutter::EncodableValue("现在该做这件事了。")}};
    messenger.Call("show", args);
    HWND popup = CurrentReminder();
    Check(popup && popup != owner && IsWindowVisible(popup),
          "independent visible popup missing");
    Check(!IsWindowVisible(owner) && !IsWindowEnabled(owner),
          "hidden owner changed or not protected");
    Check((GetWindowLongPtrW(popup, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0,
          "popup not on top");
    Check((GetWindowLongPtrW(popup, GWL_STYLE) & WS_CAPTION) == 0,
          "old system title bar still present");
    RECT bounds{};
    GetWindowRect(popup, &bounds);
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    GetMonitorInfoW(MonitorFromWindow(owner, MONITOR_DEFAULTTOPRIMARY),
                    &monitor);
    Check(abs((bounds.left + bounds.right) -
              (monitor.rcMonitor.left + monitor.rcMonitor.right)) <= 2,
          "not centered horizontally");
    Check(abs((bounds.top + bounds.bottom) -
              (monitor.rcMonitor.top + monitor.rcMonitor.bottom)) <= 2,
          "not centered vertically");
    if (argc > 1)
      Capture(popup, argv[1]);
    SendMessageW(popup, WM_COMMAND, MAKEWPARAM(104, BN_CLICKED), 0);
    Check(messenger.action == 0 && IsWindow(popup),
          "acknowledgement closed before save");
    Check(!IsWindowEnabled(GetDlgItem(popup, 104)),
          "buttons active while saving");
    messenger.Call("error", {{flutter::EncodableValue("message"),
                              flutter::EncodableValue("模拟保存失败")}});
    Check(IsWindowEnabled(GetDlgItem(popup, 104)), "save retry not enabled");
    SendMessageW(popup, WM_COMMAND, MAKEWPARAM(102, BN_CLICKED), 0);
    Check(messenger.action == 10, "snooze action incorrect");
    messenger.Call("dismiss");
    Check(!IsWindow(popup) && IsWindowEnabled(owner) && !IsWindowVisible(owner),
          "dismiss did not restore hidden owner");
    messenger.Call("show", args);
    popup = CurrentReminder();
    SendMessageW(popup, WM_COMMAND, MAKEWPARAM(105, BN_CLICKED), 0);
    Check(messenger.action == 5 && IsWindow(popup),
          "custom close must request saved snooze");
    messenger.Call("error");
    MSG escape{};
    escape.hwnd = GetDlgItem(popup, 104);
    escape.message = WM_KEYDOWN;
    escape.wParam = VK_ESCAPE;
    IsDialogMessageW(popup, &escape);
    Check(messenger.action == 5 && !IsWindowEnabled(GetDlgItem(popup, 104)),
          "keyboard snooze missing");
    messenger.Call("dismiss");
    std::cout << "PASS: independent centered topmost popup, hidden tray owner, "
                 "acknowledgement, snooze, save retry and close protection\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    DestroyWindow(owner);
    return 1;
  }
  DestroyWindow(owner);
  return 0;
}
