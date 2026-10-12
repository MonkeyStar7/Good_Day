#include <cstdint>
#include <cwctype>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <string>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kInstanceProperty[] = L"GoodDay.Instance";

BOOL CALLBACK ActivateExistingWindow(HWND window, LPARAM instance_id) {
  if (::GetPropW(window, kInstanceProperty) !=
      reinterpret_cast<HANDLE>(instance_id)) {
    return TRUE;
  }
  ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(window);
  return FALSE;
}
} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Scope the instance to this executable location. An isolated internal build
  // can run alongside the installed release without sharing its data.
  wchar_t executable[32768] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, executable, 32768);
  if (length == 0 || length >= 32768)
    return EXIT_FAILURE;
  uintptr_t instance_id = 14695981039346656037ULL;
  for (DWORD i = 0; i < length; ++i) {
    instance_id ^= static_cast<uintptr_t>(std::towlower(executable[i]));
    instance_id *= 1099511628211ULL;
  }
  const std::wstring mutex_name =
      L"Local\\GoodDay." + std::to_wstring(instance_id);
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (instance_mutex == nullptr)
    return EXIT_FAILURE;
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // A second launch during startup must wait briefly for the first window.
    for (int attempt = 0; attempt < 40; ++attempt) {
      if (!::EnumWindows(ActivateExistingWindow,
                         static_cast<LPARAM>(instance_id)))
        break;
      ::Sleep(50);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
  // The installer can detect this exact executable without terminating drafts.
  uint64_t setup_hash = 0;
  for (DWORD i = 0; i < length; ++i) {
    setup_hash = (setup_hash * 31 + std::towlower(executable[i])) % 1000000007;
  }
  const std::wstring setup_mutex_name =
      L"Local\\GoodDay.Setup." + std::to_wstring(setup_hash);
  HANDLE setup_mutex = ::CreateMutexW(nullptr, FALSE, setup_mutex_name.c_str());
  if (setup_mutex == nullptr) {
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Good Day", origin, size)) {
    ::CloseHandle(setup_mutex);
    ::CloseHandle(instance_mutex);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  ::SetPropW(window.GetHandle(), kInstanceProperty,
             reinterpret_cast<HANDLE>(instance_id));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    HWND root = ::GetAncestor(msg.hwnd, GA_ROOT);
    wchar_t class_name[64] = {};
    ::GetClassNameW(root, class_name, 64);
    if (std::wstring(class_name) == L"GoodDay.Reminder" &&
        ::IsDialogMessageW(root, &msg))
      continue;
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(setup_mutex);
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
