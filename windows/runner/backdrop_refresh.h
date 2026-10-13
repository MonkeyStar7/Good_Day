#ifndef GOOD_DAY_BACKDROP_REFRESH_H_
#define GOOD_DAY_BACKDROP_REFRESH_H_
#include <functional>
#include <memory>
#include <windows.h>

// Listen to desktop changes without polling or activating the application.
class BackdropRefresh {
public:
  static constexpr UINT kMessage = WM_APP + 73;
  explicit BackdropRefresh(HWND window, std::function<void()> redraw);
  ~BackdropRefresh();
  bool HandleMessage(UINT message, WPARAM wparam);
  static bool RelevantEvent(DWORD event, LONG object, LONG child);

private:
  struct State;
  std::unique_ptr<State> state_;
};
#endif
