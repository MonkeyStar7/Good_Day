#include "reminder_window.h"
#include <algorithm>
#include <flutter/standard_method_codec.h>

namespace {
constexpr wchar_t kClassName[] = L"GoodDay.Reminder";
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
        InvalidateRect(window_, nullptr, TRUE);
      result->Success();
    } else {
      result->NotImplemented();
    }
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
  if (window_) {
    SetForegroundWindow(window_);
    return true;
  }
  title_ = Text(data, "title");
  time_ = Text(data, "time");
  notes_ = Text(data, "notes");
  timing_ = Text(data, "timing");
  error_.clear();
  saving_ = false;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hIcon = LoadIcon(nullptr, IDI_INFORMATION);
  RegisterClassW(&window_class);
  const HMONITOR monitor = MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info))
    return false;
  dpi_ = GetDpiForWindow(owner_);
  if (dpi_ == 0)
    dpi_ = 96;
  const int width = std::min(
      Scale(640),
      static_cast<int>(info.rcWork.right - info.rcWork.left) - Scale(24));
  const int height = std::min(
      Scale(450),
      static_cast<int>(info.rcWork.bottom - info.rcWork.top) - Scale(24));
  const int x = info.rcMonitor.left +
                (info.rcMonitor.right - info.rcMonitor.left - width) / 2;
  const int y = info.rcMonitor.top +
                (info.rcMonitor.bottom - info.rcMonitor.top - height) / 2;
  body_font_ =
      CreateFontW(-Scale(17), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                  CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei UI");
  title_font_ =
      CreateFontW(-Scale(29), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                  CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei UI");
  owner_enabled_ = IsWindowEnabled(owner_) != FALSE;
  window_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"Good Day · 待办事件提醒",
      WS_POPUP | WS_CAPTION | WS_SYSMENU, x, y, width, height, owner_, nullptr,
      GetModuleHandle(nullptr), this);
  if (!window_) {
    Close();
    return false;
  }
  const wchar_t *labels[] = {L"5 分钟后", L"10 分钟后", L"30 分钟后",
                             L"知道了"};
  for (int i = 0; i < 4; ++i) {
    buttons_[i] =
        CreateWindowW(L"BUTTON", labels[i],
                      WS_CHILD | WS_VISIBLE | WS_TABSTOP |
                          (i == 3 ? BS_DEFPUSHBUTTON : BS_PUSHBUTTON),
                      0, 0, 1, 1, window_,
                      reinterpret_cast<HMENU>(static_cast<INT_PTR>(101 + i)),
                      GetModuleHandle(nullptr), nullptr);
    if (!buttons_[i]) {
      Close();
      return false;
    }
    SendMessageW(buttons_[i], WM_SETFONT, reinterpret_cast<WPARAM>(body_font_),
                 TRUE);
  }
  Layout();
  EnableWindow(owner_, FALSE);
  ShowWindow(window_, SW_SHOW);
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
  SetForegroundWindow(window_);
  SetFocus(buttons_[3]);
  FLASHWINFO flash{sizeof(FLASHWINFO), window_, FLASHW_ALL, 3, 0};
  FlashWindowEx(&flash);
  return true;
}

void ReminderWindow::Close() {
  if (window_) {
    HWND old = window_;
    window_ = nullptr;
    DestroyWindow(old);
  }
  buttons_.fill(nullptr);
  if (body_font_) {
    DeleteObject(body_font_);
    body_font_ = nullptr;
  }
  if (title_font_) {
    DeleteObject(title_font_);
    title_font_ = nullptr;
  }
  if (owner_enabled_ && IsWindow(owner_))
    EnableWindow(owner_, TRUE);
}

void ReminderWindow::Layout() {
  if (!window_)
    return;
  RECT bounds{};
  GetClientRect(window_, &bounds);
  const int gap = Scale(12), left = Scale(24);
  const int width = (bounds.right - left * 2 - gap * 3) / 4;
  for (int i = 0; i < 4; ++i)
    if (buttons_[i])
      MoveWindow(buttons_[i], left + i * (width + gap),
                 bounds.bottom - Scale(64), width, Scale(40), TRUE);
}

void ReminderWindow::Submit(int minutes) {
  if (saving_)
    return;
  saving_ = true;
  error_ = L"正在保存…";
  for (HWND button : buttons_)
    if (button)
      EnableWindow(button, FALSE);
  InvalidateRect(window_, nullptr, TRUE);
  channel_->InvokeMethod("action",
                         std::make_unique<flutter::EncodableValue>(minutes));
}

void ReminderWindow::Paint() {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window_, &paint);
  const int saved_dc = SaveDC(dc);
  RECT rect{};
  GetClientRect(window_, &rect);
  HBRUSH background = CreateSolidBrush(RGB(247, 249, 252));
  FillRect(dc, &rect, background);
  DeleteObject(background);
  RECT header{0, 0, rect.right, Scale(60)};
  HBRUSH blue = CreateSolidBrush(RGB(33, 83, 143));
  FillRect(dc, &header, blue);
  DeleteObject(blue);
  SetBkMode(dc, TRANSPARENT);
  SelectObject(dc, body_font_);
  SetTextColor(dc, RGB(255, 255, 255));
  RECT heading{Scale(24), Scale(16), rect.right - Scale(24), Scale(52)};
  DrawTextW(dc, L"待办事件提醒", -1, &heading, DT_SINGLELINE | DT_VCENTER);
  SetTextColor(dc, RGB(27, 40, 57));
  SelectObject(dc, title_font_);
  RECT title{Scale(24), Scale(78), rect.right - Scale(24), Scale(160)};
  DrawTextW(dc, title_.c_str(), -1, &title,
            DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(dc, body_font_);
  RECT time{Scale(24), Scale(167), rect.right - Scale(24), Scale(197)};
  DrawTextW(dc, time_.c_str(), -1, &time,
            DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  RECT timing{Scale(24), Scale(201), rect.right - Scale(24), Scale(234)};
  DrawTextW(dc, timing_.c_str(), -1, &timing,
            DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  SetTextColor(dc, RGB(80, 92, 108));
  RECT notes{Scale(24), Scale(241), rect.right - Scale(24),
             rect.bottom - Scale(112)};
  DrawTextW(dc, notes_.c_str(), -1, &notes,
            DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
  if (!error_.empty()) {
    SetTextColor(dc, saving_ ? RGB(80, 92, 108) : RGB(166, 44, 36));
    RECT error{Scale(24), rect.bottom - Scale(107), rect.right - Scale(24),
               rect.bottom - Scale(69)};
    DrawTextW(dc, error_.c_str(), -1, &error,
              DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
  }
  RestoreDC(dc, saved_dc);
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
  case WM_PAINT:
    self->Paint();
    return 0;
  case WM_ERASEBKGND:
    return 1;
  case WM_SIZE:
    self->Layout();
    return 0;
  case WM_COMMAND:
    if (LOWORD(wparam) == IDOK) {
      self->Submit(0);
      return 0;
    }
    if (LOWORD(wparam) == IDCANCEL) {
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
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
