cmake_minimum_required(VERSION 3.14)
project(good_day_native_tests LANGUAGES CXX)
get_filename_component(ROOT "../.." ABSOLUTE)
set(WRAPPER "${ROOT}/windows/flutter/ephemeral/cpp_client_wrapper")
add_executable(reminder_window_test reminder_window_test.cpp
  "${ROOT}/windows/runner/reminder_window.cpp")
target_compile_features(reminder_window_test PRIVATE cxx_std_17)
target_compile_options(reminder_window_test PRIVATE /W4 /WX /utf-8)
target_compile_definitions(reminder_window_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_include_directories(reminder_window_test PRIVATE "${WRAPPER}/include" "${ROOT}/windows/runner")
target_link_libraries(reminder_window_test PRIVATE user32 gdi32
  "${ROOT}/build/windows/x64/flutter/Release/flutter_wrapper_app.lib"
  "${ROOT}/windows/flutter/ephemeral/flutter_windows.dll.lib")
add_custom_command(TARGET reminder_window_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${ROOT}/windows/flutter/ephemeral/flutter_windows.dll" "$<TARGET_FILE_DIR:reminder_window_test>")
enable_testing()
add_test(NAME centered_reminder COMMAND reminder_window_test)
