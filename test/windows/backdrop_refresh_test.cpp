#include "backdrop_refresh.h"
#include <iostream>
#include <stdexcept>

BackdropRefresh *monitor = nullptr;
int frames = 0;
void Check(bool condition, const char *text) {
  if (!condition)
    throw std::runtime_error(text);
}
LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (monitor && monitor->HandleMessage(message, wp))
    return 0;
  return DefWindowProcW(window, message, wp, lp);
}
void Pump(DWORD duration) {
  const auto until = GetTickCount64() + duration;
  while (GetTickCount64() < until) {
    MSG msg{};
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    Sleep(5);
  }
}
int main() {
  try {
    Check(BackdropRefresh::RelevantEvent(EVENT_SYSTEM_FOREGROUND, 0, 0),
          "foreground ignored");
    Check(BackdropRefresh::RelevantEvent(EVENT_SYSTEM_MINIMIZEEND, 0, 0),
          "minimize ignored");
    Check(BackdropRefresh::RelevantEvent(EVENT_SYSTEM_DESKTOPSWITCH, 0, 0),
          "desktop switch ignored");
    Check(BackdropRefresh::RelevantEvent(EVENT_OBJECT_HIDE, OBJID_WINDOW,
                                         CHILDID_SELF),
          "hidden window ignored");
    Check(!BackdropRefresh::RelevantEvent(EVENT_OBJECT_LOCATIONCHANGE,
                                          OBJID_CLIENT, 0),
          "child layout causes refresh");
    Check(!BackdropRefresh::RelevantEvent(EVENT_OBJECT_FOCUS, OBJID_WINDOW, 0),
          "focus noise causes refresh");
    WNDCLASSW wc{};
    wc.lpfnWndProc = Procedure;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"GoodDay.BackdropRefresh.Test";
    RegisterClassW(&wc);
    HWND window = CreateWindowW(wc.lpszClassName, L"", WS_POPUP, 0, 0, 20, 20,
                                nullptr, nullptr, wc.hInstance, nullptr);
    Check(window != nullptr, "test window missing");
    ShowWindow(window, SW_SHOWNOACTIVATE);
    {
      BackdropRefresh value(window, [] { ++frames; });
      monitor = &value;
      for (int i = 0; i < 20; ++i)
        PostMessageW(window, BackdropRefresh::kMessage, 0, 0);
      Pump(550);
      Check(frames == 2, "burst must cause immediate and settled redraw only");
      Pump(450);
      Check(frames == 2, "idle refresh polling detected");
      ShowWindow(window, SW_HIDE);
      PostMessageW(window, BackdropRefresh::kMessage, 0, 0);
      Pump(550);
      Check(frames == 2, "hidden app repaints");
      ShowWindow(window, SW_SHOWNOACTIVATE);
      PostMessageW(window, BackdropRefresh::kMessage, 0, 0);
      Pump(80);
      Check(frames == 3, "visible refresh did not resume");
      monitor = nullptr;
    }
    Pump(450);
    Check(frames == 3, "destroyed monitor still redraws");
    DestroyWindow(window);
    std::cout << "PASS: desktop events, coalescing, settled redraw, no idle "
                 "polling and safe cleanup\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
