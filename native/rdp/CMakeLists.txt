# Remlark RDP 胶水库：静态链接 FreeRDP / WinPR / OpenSSL，输出单个动态库供 Dart FFI 加载
cmake_minimum_required(VERSION 3.16)
project(remlark_rdp C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(REMLARK_DEPS_PREFIX "" CACHE PATH "OpenSSL / FreeRDP 安装前缀（由构建脚本传入）")

add_library(remlark_rdp SHARED
  src/remlark_rdp.c
  src/rmk_clipboard.c
)

target_include_directories(remlark_rdp PRIVATE
  ${REMLARK_DEPS_PREFIX}/include/freerdp3
  ${REMLARK_DEPS_PREFIX}/include/winpr3
  ${REMLARK_DEPS_PREFIX}/include
)

set(DEPS_LIB ${REMLARK_DEPS_PREFIX}/lib)
if(WIN32)
  set(STATIC_LIBS
    ${DEPS_LIB}/freerdp-client3.lib ${DEPS_LIB}/freerdp3/remdesk-common.lib
    ${DEPS_LIB}/freerdp3.lib ${DEPS_LIB}/winpr3.lib
    ${DEPS_LIB}/libssl.lib ${DEPS_LIB}/libcrypto.lib)
  target_link_libraries(remlark_rdp PRIVATE ${STATIC_LIBS}
    ws2_32 crypt32 secur32 ntdsapi rpcrt4 shlwapi dbghelp userenv winmm shell32 ole32 advapi32 user32 gdi32 bcrypt ncrypt)
else()
  set(STATIC_LIBS
    ${DEPS_LIB}/libfreerdp-client3.a ${DEPS_LIB}/freerdp3/libremdesk-common.a
    ${DEPS_LIB}/libfreerdp3.a ${DEPS_LIB}/libwinpr3.a
    ${DEPS_LIB}/libssl.a ${DEPS_LIB}/libcrypto.a)
  find_package(ZLIB)
  find_package(Threads REQUIRED)
  target_link_libraries(remlark_rdp PRIVATE ${STATIC_LIBS} Threads::Threads ${CMAKE_DL_LIBS} m)
  if(ZLIB_FOUND)
    target_link_libraries(remlark_rdp PRIVATE ZLIB::ZLIB)
  endif()
  if(APPLE)
    target_link_libraries(remlark_rdp PRIVATE
      "-framework CoreFoundation" "-framework Security" "-framework IOKit"
      "-framework SystemConfiguration" "-framework CoreServices" "-framework Carbon" "-framework AppKit"
      "-framework AudioToolbox" "-framework CoreAudio" "-framework AudioUnit" "-framework AVFoundation" "-framework CoreMedia" "-framework Foundation"
      # 只导出 rmk_rdp_* 接口，避免与应用内其他库（如 OpenSSL）符号冲突
      "-Wl,-exported_symbol,_rmk_rdp_*")
    set_target_properties(remlark_rdp PROPERTIES INSTALL_NAME_DIR "@rpath")
  else()
    # 静态库符号不导出，并优先绑定自身符号，避免与系统 OpenSSL 等冲突
    target_link_options(remlark_rdp PRIVATE "-Wl,--exclude-libs,ALL" "-Wl,-Bsymbolic")
  endif()
endif()
