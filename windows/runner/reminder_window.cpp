#include "reminder_window.h"
#include <algorithm>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <gdiplus.h>

namespace {
constexpr wchar_t kClassName[] = L"GoodDay.Reminder";
constexpr wchar_t kButtonProcedure[] = L"GoodDay.Reminder.ButtonProc";
constexpr wchar_t kHovered[] = L"GoodDay.Reminder.Hovered";
Gdiplus::Color Mix(int rgb, float amount, BYTE neutral = 255) {
  // Match the cloud-yellow Flutter palette while keeping readable controls.
  if (rgb == 0x8D742B) {
    if (neutral == 255 && amount == 0.09f)
      return Gdiplus::Color(255, 255, 253, 245);
    if (neutral == 255 && amount == 0.16f)
      return Gdiplus::Color(255, 255, 248, 230);
    if (neutral == 255 && amount == 0.29f)
      return Gdiplus::Color(255, 234, 225, 201);
    if (neutral == 32 && amount == 0.52f)
      return Gdiplus::Color(255, 63, 58, 45);
    if (neutral == 120 && amount == 0.58f)
      return Gdiplus::Color(255, 129, 118, 93);
  }
  const auto blend = [amount, neutral](int channel) {
    return static_cast<BYTE>(neutral + (channel - neutral) * amount);
  };
  return Gdiplus::Color(255, blend((rgb >> 16) & 255), blend((rgb >> 8) & 255),
                        blend(rgb & 255));
}
class DrawingSession {
public:
  DrawingSession() {
    Gdiplus::GdiplusStartupInput input;
    ready = Gdiplus::GdiplusStartup(&token_, &input, nullptr) == Gdiplus::Ok;
  }
  ~DrawingSession() {
    if (ready)
      Gdiplus::GdiplusShutdown(token_);
  }
  bool ready = false;

private:
  ULONG_PTR token_ = 0;
};
std::wstring Wide(const std::string &text) {
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  if (length > 0)
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), length);
  return result;
}
std::wstring Text(const flutter::EncodableMap &data, const char *key) {
  const auto it = data.find(flutter::EncodableValue(key));
  if (it == data.end())
    return L"";
  const auto value = std::get_if<std::string>(&it->second);
  return value ? Wide(*value) : L"";
}
void Round(Gdiplus::Graphics &graphics, const Gdiplus::RectF &rect,
           float radius, const Gdiplus::Color &color,
           const Gdiplus::Color *border = nullptr) {
  const float d = radius * 2;
  Gdiplus::GraphicsPath path;
  path.AddArc(rect.X, rect.Y, d, d, 180, 90);
  path.AddArc(rect.GetRight() - d, rect.Y, d, d, 270, 90);
  path.AddArc(rect.GetRight() - d, rect.GetBottom() - d, d, d, 0, 90);
  path.AddArc(rect.X, rect.GetBottom() - d, d, d, 90, 90);
  path.CloseFigure();
  Gdiplus::SolidBrush fill(color);
  graphics.FillPath(&fill, &path);
  if (border) {
    Gdiplus::Pen pen(*border, 1);
    graphics.DrawPath(&pen, &path);
  }
}
void Write(Gdiplus::Graphics &graphics, const std::wstring &text,
           const Gdiplus::RectF &rect, float size, const Gdiplus::Color &color,
           bool bold = false, bool centered = false,
           const wchar_t *family = L"Microsoft YaHei UI") {
  Gdiplus::Font font(family, size,
                     bold ? Gdiplus::FontStyleBold : Gdiplus::FontStyleRegular,
                     Gdiplus::UnitPixel);
  Gdiplus::SolidBrush brush(color);
  Gdiplus::StringFormat format;
  format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  if (centered) {
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  }
  graphics.DrawString(text.c_str(), static_cast<int>(text.size()), &font, rect,
                      &format, &brush);
}
LRESULT CALLBACK ButtonProc(HWND button, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  auto original = reinterpret_cast<WNDPROC>(GetPropW(button, kButtonProcedure));
  if (message == WM_MOUSEMOVE && !GetPropW(button, kHovered)) {
    SetPropW(button, kHovered, reinterpret_cast<HANDLE>(1));
    TRACKMOUSEEVENT track{sizeof(TRACKMOUSEEVENT), TME_LEAVE, button, 0};
    TrackMouseEvent(&track);
    InvalidateRect(button, nullptr, FALSE);
  } else if (message == WM_MOUSELEAVE) {
    RemovePropW(button, kHovered);
    InvalidateRect(button, nullptr, FALSE);
  } else if (message == WM_NCDESTROY) {
    RemovePropW(button, kHovered);
    RemovePropW(button, kButtonProcedure);
  }
  return original ? CallWindowProcW(original, button, message, wparam, lparam)
                  : DefWindowProcW(button, message, wparam, lparam);
}
} // namespace

ReminderWindow::ReminderWindow(flutter::BinaryMessenger *messenger, HWND owner)
    : owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "good_day/reminder",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    if (call.method_name() == "show") {
      const auto data =
          call.arguments()
              ? std::get_if<flutter::EncodableMap>(call.arguments())
              : nullptr;
      if (!data || !Show(*data)) {
        result->Error("reminder_window", "Cannot create reminder window");
        return;
      }
      result->Success();
    } else if (call.method_name() == "dismiss") {
      Close();
      result->Success();
    } else if (call.method_name() == "error") {
      const auto data =
          call.arguments()
              ? std::get_if<flutter::EncodableMap>(call.arguments())
              : nullptr;
      error_ = data ? Text(*data, "message") : L"保存失败，请重试";
      saving_ = false;
      for (HWND button : buttons_)
        if (button)
          EnableWindow(button, TRUE);
      if (window_)
        InvalidateRect(window_, nullptr, FALSE);
      result->Success();
    } else
      result->NotImplemented();
  });
}
ReminderWindow::~ReminderWindow() {
  channel_->SetMethodCallHandler(nullptr);
  Close();
}
int ReminderWindow::Scale(int value) const {
  return MulDiv(value, static_cast<int>(dpi_), 96);
}

bool ReminderWindow::Show(const flutter::EncodableMap &data) {
  static DrawingSession drawing;
  if (!drawing.ready)
    return false;
  if (window_) {
    SetForegroundWindow(window_);
    return true;
  }
  const auto accent = data.find(flutter::EncodableValue("accentRgb"));
  accent_rgb_ = 0x365D46;
  if (accent != data.end()) {
    const auto value = std::get_if<int32_t>(&accent->second);
    if (value && *value >= 0 && *value <= 0xFFFFFF)
      accent_rgb_ = *value;
  }
  title_ = Text(data, "title");
  time_ = Text(data, "time");
  date_ = Text(data, "date");
  clock_ = Text(data, "clock");
  if (clock_.empty() && time_.length() >= 5)
    clock_ = time_.substr(time_.length() - 5);
  if (date_.empty())
    date_ = time_.length() > 6 ? time_.substr(0, time_.length() - 6) : time_;
  notes_ = Text(data, "notes");
  timing_ = Text(data, "timing");
  error_.clear();
  saving_ = false;
  WNDCLASSW window_class{};
  window_class.style = CS_DROPSHADOW;
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY),
                      &info))
    return false;
  dpi_ = GetDpiForWindow(owner_);
  if (!dpi_)
    dpi_ = 96;
  const int width = std::min(
      Scale(600),
      static_cast<int>(info.rcWork.right - info.rcWork.left) - Scale(24));
  const int height = std::min(
      Scale(460),
      static_cast<int>(info.rcWork.bottom - info.rcWork.top) - Scale(24));
  // Keep content proportions when the monitor cannot fit the requested DPI
  // size.
  dpi_ = std::min(
      dpi_, static_cast<UINT>(std::min(width * 96 / 600, height * 96 / 460)));
  const int x = info.rcMonitor.left +
                (info.rcMonitor.right - info.rcMonitor.left - width) / 2;
  const int y = info.rcMonitor.top +
                (info.rcMonitor.bottom - info.rcMonitor.top - height) / 2;
  owner_enabled_ = IsWindowEnabled(owner_) != FALSE;
  window_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName,
                            L"Good Day · 待办事件提醒",
                            WS_POPUP | WS_THICKFRAME, x, y, width, height,
                            owner_, nullptr, GetModuleHandle(nullptr), this);
  if (!window_) {
    Close();
    return false;
  }
  const DWORD round_corners = 2;
  if (FAILED(DwmSetWindowAttribute(window_, 33, &round_corners,
                                   sizeof(round_corners)))) {
    HRGN region =
        CreateRoundRectRgn(0, 0, width + 1, height + 1, Scale(28), Scale(28));
    if (!SetWindowRgn(window_, region, FALSE))
      DeleteObject(region);
  }
  const MARGINS shadow{1, 1, 1, 1};
  DwmExtendFrameIntoClientArea(window_, &shadow);
  SetWindowPos(window_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  const wchar_t *labels[] = {L"5 分钟后", L"10 分钟后", L"30 分钟后", L"知道了",
                             L"关闭，5 分钟后提醒"};
  for (int i = 0; i < 5; ++i) {
    buttons_[i] = CreateWindowW(
        L"BUTTON", labels[i], WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 1, 1, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(101 + i)),
        GetModuleHandle(nullptr), nullptr);
    if (!buttons_[i]) {
      Close();
      return false;
    }
    const auto original = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
        buttons_[i], GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ButtonProc)));
    SetPropW(buttons_[i], kButtonProcedure, reinterpret_cast<HANDLE>(original));
  }
  Layout();
  EnableWindow(owner_, FALSE);
  ShowWindow(window_, SW_SHOW);
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
  SetForegroundWindow(window_);
  SetFocus(buttons_[3]);
  return true;
}
void ReminderWindow::Close() {
  if (window_) {
    HWND old = window_;
    window_ = nullptr;
    DestroyWindow(old);
  }
  buttons_.fill(nullptr);
  if (owner_enabled_ && IsWindow(owner_))
    EnableWindow(owner_, TRUE);
}
void ReminderWindow::Layout() {
  if (!window_)
    return;
  RECT bounds{};
  GetClientRect(window_, &bounds);
  const int gap = Scale(10), left = Scale(32),
            width = (bounds.right - left * 2 - gap * 3) / 4;
  for (int i = 0; i < 4; ++i)
    if (buttons_[i])
      MoveWindow(buttons_[i], left + i * (width + gap),
                 bounds.bottom - Scale(70), width, Scale(42), TRUE);
  if (buttons_[4])
    MoveWindow(buttons_[4], bounds.right - Scale(60), Scale(24), Scale(36),
               Scale(36), TRUE);
}
void ReminderWindow::Submit(int minutes) {
  if (saving_)
    return;
  saving_ = true;
  error_ = L"正在保存…";
  for (HWND button : buttons_)
    if (button)
      EnableWindow(button, FALSE);
  InvalidateRect(window_, nullptr, FALSE);
  channel_->InvokeMethod("action",
                         std::make_unique<flutter::EncodableValue>(minutes));
}
void ReminderWindow::PaintButton(const DRAWITEMSTRUCT &item) {
  const auto kPaper = Mix(accent_rgb_, 0.09f);
  const auto kMuted = Mix(accent_rgb_, 0.58f, 120);
  const auto kAccent = Mix(accent_rgb_, 1.0f);
  Gdiplus::Graphics graphics(item.hDC);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
  graphics.Clear(kPaper);
  const bool disabled = (item.itemState & ODS_DISABLED) != 0;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  const bool hover = GetPropW(item.hwndItem, kHovered) != nullptr;
  const auto width = static_cast<float>(item.rcItem.right - item.rcItem.left);
  const auto height = static_cast<float>(item.rcItem.bottom - item.rcItem.top);
  if (item.CtlID == 105) {
    if (hover || pressed)
      Round(graphics, {1, 1, width - 2, height - 2},
            static_cast<float>(Scale(9)), Mix(accent_rgb_, 0.16f));
    Gdiplus::Pen pen(disabled ? Mix(accent_rgb_, 0.42f) : kMuted,
                     static_cast<float>(Scale(2)));
    pen.SetStartCap(Gdiplus::LineCapRound);
    pen.SetEndCap(Gdiplus::LineCapRound);
    const float mid_x = width / 2, mid_y = height / 2,
                offset = static_cast<float>(Scale(5));
    graphics.DrawLine(&pen, mid_x - offset, mid_y - offset, mid_x + offset,
                      mid_y + offset);
    graphics.DrawLine(&pen, mid_x - offset, mid_y + offset, mid_x + offset,
                      mid_y - offset);
  } else {
    const bool primary = item.CtlID == 104;
    const Gdiplus::Color fill = primary
                                    ? (disabled  ? Mix(accent_rgb_, 0.55f)
                                       : pressed ? Mix(accent_rgb_, 0.85f, 0)
                                       : hover   ? Mix(accent_rgb_, 0.87f)
                                                 : kAccent)
                                    : (pressed ? Mix(accent_rgb_, 0.24f)
                                       : hover ? Mix(accent_rgb_, 0.19f)
                                               : Mix(accent_rgb_, 0.12f));
    const auto border = Mix(accent_rgb_, 0.29f);
    Round(graphics, {1, 1, width - 2, height - 2},
          static_cast<float>(Scale(10)), fill, primary ? nullptr : &border);
    const wchar_t *labels[] = {L"5 分钟后", L"10 分钟后", L"30 分钟后",
                               L"知道了"};
    Write(graphics, labels[item.CtlID - 101], {0, 0, width, height},
          static_cast<float>(Scale(14)),
          primary    ? Gdiplus::Color(255, 255, 255, 255)
          : disabled ? Mix(accent_rgb_, 0.48f)
                     : kAccent,
          primary, true);
  }
  if ((item.itemState & ODS_FOCUS) != 0 && !disabled) {
    auto outline = Mix(accent_rgb_, 0.65f);
    Round(graphics, {2, 2, width - 4, height - 4}, static_cast<float>(Scale(9)),
          Gdiplus::Color(0, 0, 0, 0), &outline);
  }
}
void ReminderWindow::Paint() {
  const auto kPaper = Mix(accent_rgb_, 0.09f);
  const auto kInk = Mix(accent_rgb_, 0.52f, 32);
  const auto kMuted = Mix(accent_rgb_, 0.58f, 120);
  const auto kAccent = Mix(accent_rgb_, 1.0f);
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window_, &paint);
  RECT bounds{};
  GetClientRect(window_, &bounds);
  {
    // Draw to an offscreen surface so hover and save updates do not flash.
    Gdiplus::Bitmap surface(bounds.right, bounds.bottom, PixelFormat32bppPARGB);
    Gdiplus::Graphics graphics(&surface);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    graphics.Clear(kPaper);
    const auto px = [this](int value) {
      return static_cast<float>(Scale(value));
    };
    const float right = static_cast<float>(bounds.right),
                bottom = static_cast<float>(bounds.bottom);
    Round(graphics, {px(32), px(28), px(42), px(42)}, px(13),
          Mix(accent_rgb_, 0.20f));
    Gdiplus::Pen clock_pen(kAccent, px(2));
    clock_pen.SetStartCap(Gdiplus::LineCapRound);
    clock_pen.SetEndCap(Gdiplus::LineCapRound);
    graphics.DrawEllipse(&clock_pen, px(44), px(40), px(18), px(18));
    graphics.DrawLine(&clock_pen, px(53), px(44), px(53), px(49));
    graphics.DrawLine(&clock_pen, px(53), px(49), px(57), px(51));
    Write(graphics, L"GOOD DAY", {px(86), px(29), right - px(160), px(18)},
          px(12), kAccent, true, false, L"Segoe UI");
    Write(graphics, L"待办提醒", {px(86), px(49), right - px(160), px(22)},
          px(13), kMuted);
    Write(graphics, title_, {px(32), px(100), right - px(64), px(80)}, px(27),
          kInk, true);
    Round(graphics, {px(32), px(194), right - px(64), px(74)}, px(14),
          Mix(accent_rgb_, 0.16f));
    Write(graphics, clock_, {px(48), px(208), px(116), px(44)}, px(30), kAccent,
          true, false, L"Segoe UI");
    Write(graphics, date_, {px(178), px(206), right - px(226), px(22)}, px(13),
          kInk);
    Write(graphics, timing_, {px(178), px(234), right - px(226), px(24)},
          px(12), kMuted);
    Write(graphics, notes_.empty() ? L"到时间了，先把这件事完成吧。" : notes_,
          {px(32), px(286), right - px(64), std::max(px(20), bottom - px(408))},
          px(15), kMuted);
    if (!error_.empty())
      Write(graphics, error_,
            {px(32), bottom - px(128), right - px(64), px(36)}, px(12),
            saving_ ? kMuted : Gdiplus::Color(255, 156, 65, 49));
    Gdiplus::Pen line(Mix(accent_rgb_, 0.29f), 1);
    graphics.DrawLine(&line, px(32), bottom - px(86), right - px(32),
                      bottom - px(86));
    Gdiplus::Graphics target(dc);
    target.DrawImage(&surface, 0, 0);
  }
  EndPaint(window_, &paint);
}
LRESULT CALLBACK ReminderWindow::WindowProc(HWND window, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  auto *self = reinterpret_cast<ReminderWindow *>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<ReminderWindow *>(
        reinterpret_cast<CREATESTRUCTW *>(lparam)->lpCreateParams);
    self->window_ = window;
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (!self)
    return DefWindowProcW(window, message, wparam, lparam);
  switch (message) {
  case WM_NCCALCSIZE:
    if (wparam)
      return 0;
    break;
  case WM_NCHITTEST: {
    POINT point{static_cast<short>(LOWORD(lparam)),
                static_cast<short>(HIWORD(lparam))};
    ScreenToClient(window, &point);
    RECT bounds{};
    GetClientRect(window, &bounds);
    return point.y < self->Scale(82) && point.x < bounds.right - self->Scale(70)
               ? HTCAPTION
               : HTCLIENT;
  }
  case WM_PAINT:
    self->Paint();
    return 0;
  case WM_ERASEBKGND:
    return 1;
  case WM_SIZE:
    self->Layout();
    return 0;
  case WM_DRAWITEM:
    if (wparam >= 101 && wparam <= 105) {
      self->PaintButton(*reinterpret_cast<DRAWITEMSTRUCT *>(lparam));
      return TRUE;
    }
    break;
  case DM_GETDEFID:
    return MAKELONG(104, DC_HASDEFID);
  case WM_COMMAND:
    if (LOWORD(wparam) == IDOK) {
      self->Submit(0);
      return 0;
    }
    if (LOWORD(wparam) == IDCANCEL || LOWORD(wparam) == 105) {
      self->Submit(5);
      return 0;
    }
    if (HIWORD(wparam) == BN_CLICKED && LOWORD(wparam) >= 101 &&
        LOWORD(wparam) <= 104) {
      constexpr int minutes[] = {5, 10, 30, 0};
      self->Submit(minutes[LOWORD(wparam) - 101]);
      return 0;
    }
    break;
  case WM_CLOSE:
    self->Submit(5);
    return 0;
  case WM_KEYDOWN:
    if (wparam == VK_ESCAPE) {
      self->Submit(5);
      return 0;
    }
    if (wparam == VK_RETURN) {
      self->Submit(0);
      return 0;
    }
    break;
  case WM_DPICHANGED:
    self->dpi_ = HIWORD(wparam);
    {
      const auto *suggested = reinterpret_cast<RECT *>(lparam);
      SetWindowPos(window, nullptr, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
    }
    self->Layout();
    InvalidateRect(window, nullptr, FALSE);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
