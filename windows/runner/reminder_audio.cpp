#include "reminder_audio.h"
#include <filesystem>
#include <mmsystem.h>
#include <windows.h>

bool PlayReminderSound(const std::wstring &key) {
  if (key == L"none") {
    PlaySoundW(nullptr, nullptr, 0);
    return true;
  }
  if (key != L"wood_tap" && key != L"soft_chime" && key != L"clear_bell" &&
      key != L"warm_keys")
    return false;
  wchar_t executable[32768]{};
  const DWORD count = GetModuleFileNameW(nullptr, executable, 32768);
  if (!count || count >= 32768)
    return false;
  const auto sound = std::filesystem::path(executable).parent_path() / L"data" /
                     L"flutter_assets" / L"assets" / L"sounds" /
                     (key + L".wav");
  return PlaySoundW(sound.c_str(), nullptr,
                    SND_FILENAME | SND_ASYNC | SND_NODEFAULT) != FALSE;
}
