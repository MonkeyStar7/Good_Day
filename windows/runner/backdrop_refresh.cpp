#include "backdrop_refresh.h"
#include <array>
#include <unordered_map>

namespace {
constexpr UINT_PTR kFirst = 0x474401;
constexpr UINT_PTR kSettled = 0x474402;
} // namespace

struct BackdropRefresh::State {
  HWND window;
  std::function<void()> redraw;
  std::array<HWINEVENTHOOK, 4> hooks{};
  bool posted = false;
  static std::unordered_map<HWINEVENTHOOK, State *> &Registry() {
    static thread_local std::unordered_map<HWINEVENTHOOK, State *> registry;
    return registry;
  }
  bool Visible() const { return IsWindowVisible(window) && !IsIconic(window); }
  static void CALLBACK Event(HWINEVENTHOOK hook, DWORD event, HWND source,
                             LONG object, LONG child, DWORD, DWORD) {
    const auto it = Registry().find(hook);
    if (it == Registry().end() ||
        !BackdropRefresh::RelevantEvent(event, object, child))
      return;
    State *state = it->second;
    if (!state->Visible() || state->posted)
      return;
    if (event >= EVENT_OBJECT_DESTROY && source && IsWindow(source)) {
      if (GetAncestor(source, GA_ROOT) != source)
        return;
      RECT foreground{}, paper{}, overlap{};
      if (event != EVENT_OBJECT_LOCATIONCHANGE &&
          GetWindowRect(source, &foreground) &&
          GetWindowRect(state->window, &paper) &&
          !IntersectRect(&overlap, &foreground, &paper))
        return;
    }
    state->posted =
        PostMessageW(state->window, BackdropRefresh::kMessage, 0, 0) != FALSE;
  }
  State(HWND target, std::function<void()> callback)
      : window(target), redraw(std::move(callback)) {
    const std::array<std::pair<DWORD, DWORD>, 4> ranges{{
        {EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND},
        {EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND},
        {EVENT_SYSTEM_DESKTOPSWITCH, EVENT_SYSTEM_DESKTOPSWITCH},
        {EVENT_OBJECT_DESTROY, EVENT_OBJECT_LOCATIONCHANGE},
    }};
    for (size_t i = 0; i < hooks.size(); ++i) {
      hooks[i] =
          SetWinEventHook(ranges[i].first, ranges[i].second, nullptr, Event, 0,
                          0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
      if (hooks[i])
        Registry()[hooks[i]] = this;
    }
  }
  ~State() {
    KillTimer(window, kFirst);
    KillTimer(window, kSettled);
    for (auto hook : hooks)
      if (hook) {
        Registry().erase(hook);
        UnhookWinEvent(hook);
      }
  }
};

BackdropRefresh::BackdropRefresh(HWND window, std::function<void()> redraw)
    : state_(std::make_unique<State>(window, std::move(redraw))) {}
BackdropRefresh::~BackdropRefresh() = default;
bool BackdropRefresh::RelevantEvent(DWORD event, LONG object, LONG child) {
  if (event == EVENT_SYSTEM_FOREGROUND || event == EVENT_SYSTEM_MINIMIZESTART ||
      event == EVENT_SYSTEM_MINIMIZEEND || event == EVENT_SYSTEM_DESKTOPSWITCH)
    return true;
  return object == OBJID_WINDOW && child == CHILDID_SELF &&
         (event == EVENT_OBJECT_SHOW || event == EVENT_OBJECT_HIDE ||
          event == EVENT_OBJECT_DESTROY ||
          event == EVENT_OBJECT_LOCATIONCHANGE);
}
bool BackdropRefresh::HandleMessage(UINT message, WPARAM wparam) {
  if (message == kMessage) {
    state_->posted = false;
    if (state_->Visible()) {
      // Coalesce a burst, then redraw once more after minimize/fade animations.
      SetTimer(state_->window, kFirst, 50, nullptr);
      KillTimer(state_->window, kSettled);
    }
    return true;
  }
  if (message != WM_TIMER || (wparam != kFirst && wparam != kSettled))
    return false;
  KillTimer(state_->window, static_cast<UINT_PTR>(wparam));
  if (state_->Visible()) {
    state_->redraw();
    if (wparam == kFirst)
      SetTimer(state_->window, kSettled, 350, nullptr);
  }
  return true;
}
