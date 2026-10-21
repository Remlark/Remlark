# Remlark SSH 加密原生库：静态链接 OpenSSL libcrypto，输出单个动态库供 Dart FFI 加载。
# OpenSSL 复用 RDP 原生库构建时编译的静态库（build/native/<平台-架构>/prefix）
cmake_minimum_required(VERSION 3.16)
project(remlark_crypto C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(REMLARK_DEPS_PREFIX "" CACHE PATH "OpenSSL 安装前缀（由构建脚本传入）")

add_library(remlark_crypto SHARED src/remlark_crypto.c)
target_include_directories(remlark_crypto PRIVATE ${REMLARK_DEPS_PREFIX}/include)

set(DEPS_LIB ${REMLARK_DEPS_PREFIX}/lib)
if(WIN32)
  # 与 macOS / Linux 一样使用 UTF-8 源码，不依赖 Windows 当前代码页。
  target_compile_options(remlark_crypto PRIVATE /utf-8)
  target_link_libraries(remlark_crypto PRIVATE ${DEPS_LIB}/libcrypto.lib ws2_32 crypt32 advapi32 user32 bcrypt)
else()
  find_package(Threads REQUIRED)
  target_link_libraries(remlark_crypto PRIVATE ${DEPS_LIB}/libcrypto.a Threads::Threads ${CMAKE_DL_LIBS})
  if(APPLE)
    # 只导出 rmk_crypto_* 接口，避免与应用内其他库的 OpenSSL 符号冲突
    target_link_options(remlark_crypto PRIVATE "-Wl,-exported_symbol,_rmk_crypto_*")
    set_target_properties(remlark_crypto PROPERTIES INSTALL_NAME_DIR "@rpath")
  else()
    target_link_options(remlark_crypto PRIVATE "-Wl,--exclude-libs,ALL" "-Wl,-Bsymbolic")
  endif()
endif()
