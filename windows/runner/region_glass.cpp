#include "region_glass.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <dispatcherqueue.h>
#include <dwmapi.h>
#include <roapi.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.Desktop.h>

namespace {
constexpr wchar_t kBackdropClass[] = L"GoodDay.RegionGlass";
LRESULT CALLBACK BackdropProc(HWND window, UINT message, WPARAM wparam,
                              LPARAM lparam) {
  switch (message) {
  case WM_NCCALCSIZE:
    if (wparam)
      return 0;
    break;
  case WM_NCHITTEST:
    return HTTRANSPARENT;
  case WM_MOUSEACTIVATE:
    return MA_NOACTIVATE;
  case WM_ERASEBKGND:
    return 1;
  case WM_PAINT: {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    PatBlt(dc, paint.rcPaint.left, paint.rcPaint.top,
           paint.rcPaint.right - paint.rcPaint.left,
           paint.rcPaint.bottom - paint.rcPaint.top, BLACKNESS);
    EndPaint(window, &paint);
    return 0;
  }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
bool Frost(HWND window) {
  const MARGINS margins{-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(window, &margins);
  const BOOL dark = FALSE;
  DwmSetWindowAttribute(window, 20, &dark, sizeof(dark));
  struct Policy {
    int state;
    int flags;
    DWORD color;
    int animation;
  };
  struct Data {
    int attribute;
    void *data;
    SIZE_T size;
  };
  using SetComposition = BOOL(WINAPI *)(HWND, Data *);
  const auto set = reinterpret_cast<SetComposition>(GetProcAddress(
      GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute"));
  if (set) {
    BOOL active = TRUE;
    Data activation{15, &active, sizeof(active)};
    set(window, &activation);
  }
  const DWORD backdrop = 3;
  if (SUCCEEDED(DwmSetWindowAttribute(window, 38, &backdrop, sizeof(backdrop))))
    return true;
  if (!set)
    return false;
  Policy policy{4, 2, 0x08FFFFFF, 0};
  Data data{19, &policy, sizeof(policy)};
  return set(window, &data) != FALSE;
}
} // namespace

struct RegionGlass::State {
  HWND window;
  std::array<HWND, 5> panels{};
  bool updating = false;
  bool runtime = false;
  winrt::Windows::System::DispatcherQueueController queue{nullptr};
  winrt::Windows::UI::Composition::Compositor compositor{nullptr};
  std::array<winrt::Windows::UI::Composition::Desktop::DesktopWindowTarget, 5>
      targets{nullptr, nullptr, nullptr, nullptr, nullptr};
  std::array<winrt::Windows::UI::Composition::SpriteVisual, 5> visuals{
      nullptr, nullptr, nullptr, nullptr, nullptr};
  std::array<
      winrt::Windows::UI::Composition::CompositionRoundedRectangleGeometry, 5>
      geometries{nullptr, nullptr, nullptr, nullptr, nullptr};
  explicit State(HWND value) : window(value) {}
  bool Layer(int index) {
    try {
      if (!compositor) {
        if (!runtime) {
          const HRESULT hr = RoInitialize(RO_INIT_SINGLETHREADED);
          if (FAILED(hr))
            return false;
          runtime = true;
        }
        if (!winrt::Windows::System::DispatcherQueue::GetForCurrentThread()) {
          DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),
                                         DQTYPE_THREAD_CURRENT, DQTAT_COM_NONE};
          winrt::check_hresult(CreateDispatcherQueueController(
              options, reinterpret_cast<
                           ABI::Windows::System::IDispatcherQueueController **>(
                           winrt::put_abi(queue))));
        }
        compositor = winrt::Windows::UI::Composition::Compositor();
      }
      if (!targets[index]) {
        const DWORD none = 1;
        DwmSetWindowAttribute(panels[index], 38, &none, sizeof(none));
        const BOOL host = TRUE;
        DwmSetWindowAttribute(panels[index], 17, &host, sizeof(host));
        auto interop = compositor.as<ABI::Windows::UI::Composition::Desktop::
                                         ICompositorDesktopInterop>();
        winrt::check_hresult(interop->CreateDesktopWindowTarget(
            panels[index], TRUE,
            reinterpret_cast<
                ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget *
                    *>(winrt::put_abi(targets[index]))));
        visuals[index] = compositor.CreateSpriteVisual();
        visuals[index].Brush(compositor.CreateHostBackdropBrush());
        geometries[index] = compositor.CreateRoundedRectangleGeometry();
        visuals[index].Clip(compositor.CreateGeometricClip(geometries[index]));
        targets[index].Root(visuals[index]);
      }
      return true;
    } catch (const winrt::hresult_error &) {
      return false;
    }
  }
  HWND Panel(int index) {
    if (panels[index])
      return panels[index];
    WNDCLASSW type{};
    type.hInstance = GetModuleHandleW(nullptr);
    type.lpszClassName = kBackdropClass;
    type.lpfnWndProc = BackdropProc;
    RegisterClassW(&type);
    panels[index] = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
                                    kBackdropClass, L"", WS_POPUP, 0, 0, 1, 1,
                                    nullptr, nullptr, type.hInstance, nullptr);
    if (panels[index] && !Layer(index))
      Frost(panels[index]);
    return panels[index];
  }
  ~State() {
    try {
      for (int i = 0; i < 5; ++i) {
        if (targets[i]) {
          targets[i].Root(nullptr);
          targets[i].Close();
        }
        visuals[i] = nullptr;
        geometries[i] = nullptr;
        targets[i] = nullptr;
      }
      if (compositor)
        compositor.Close();
      compositor = nullptr;
      if (queue) {
        auto shutdown = queue.ShutdownQueueAsync();
        const ULONGLONG deadline = GetTickCount64() + 500;
        while (shutdown.Status() ==
                   winrt::Windows::Foundation::AsyncStatus::Started &&
               GetTickCount64() < deadline) {
          MSG message{};
          if (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) {
              PostQuitMessage(static_cast<int>(message.wParam));
              break;
            }
            TranslateMessage(&message);
            DispatchMessageW(&message);
          } else
            Sleep(1);
        }
      }
    } catch (const winrt::hresult_error &) {
    }
    queue = nullptr;
    if (runtime)
      RoUninitialize();
    for (HWND panel : panels)
      if (panel)
        DestroyWindow(panel);
  }
  void Place(int index, HWND &after, int x, int y, int width, int height,
             int radius, bool visible) {
    HWND panel = Panel(index);
    if (!panel || width <= 0 || height <= 0)
      return;
    HRGN region =
        CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
    if (region && !SetWindowRgn(panel, region, FALSE))
      DeleteObject(region);
    SetWindowPos(panel, after, x, y, width, height,
                 SWP_NOACTIVATE | (visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW));
    if (visuals[index]) {
      try {
        const winrt::Windows::Foundation::Numerics::float2 size{
            static_cast<float>(width), static_cast<float>(height)};
        visuals[index].Size(size);
        geometries[index].Size(size);
        geometries[index].CornerRadius(
            {static_cast<float>(radius), static_cast<float>(radius)});
      } catch (const winrt::hresult_error &) {
      }
    }
    after = panel;
  }
};

RegionGlass::RegionGlass(HWND window)
    : state_(std::make_unique<State>(window)) {}
RegionGlass::~RegionGlass() = default;
void RegionGlass::Hide() {
  for (HWND panel : state_->panels)
    if (panel)
      ShowWindow(panel, SW_HIDE);
}
void RegionGlass::Refresh() {
  if (!IsWindowVisible(state_->window) || IsIconic(state_->window))
    return;
  for (int index = 0; index < 5; ++index) {
    if (!state_->panels[index] || !IsWindowVisible(state_->panels[index]))
      continue;
    try {
      if (state_->visuals[index])
        state_->visuals[index].Brush(
            state_->compositor.CreateHostBackdropBrush());
      else
        Frost(state_->panels[index]);
    } catch (const winrt::hresult_error &) {
    }
  }
}
bool RegionGlass::Update(double scale, bool notes, int selected, int count) {
  if (state_->updating)
    return true;
  state_->updating = true;
  RECT bounds{}, client{};
  GetWindowRect(state_->window, &bounds);
  GetClientRect(state_->window, &client);
  const double factor =
      scale * std::max(96U, GetDpiForWindow(state_->window)) / 96.0;
  const auto px = [factor](int value) {
    return static_cast<int>(std::lround(value * factor));
  };
  const bool visible =
      IsWindowVisible(state_->window) && !IsIconic(state_->window);
  HWND after = state_->window;
  const int left = notes ? px(56) : 0;
  state_->Place(0, after, bounds.left + left, bounds.top, client.right - left,
                client.bottom, px(20), visible);
  for (int index = 0; index < 4; ++index) {
    if (notes && index < count) {
      const int x = index == selected ? 0 : px(6);
      state_->Place(index + 1, after, bounds.left + x,
                    bounds.top + px(88 + 68 * index), px(64) - x, px(58), px(8),
                    visible);
    } else if (state_->panels[index + 1])
      ShowWindow(state_->panels[index + 1], SW_HIDE);
  }
  state_->updating = false;
  return state_->panels[0] != nullptr;
}
