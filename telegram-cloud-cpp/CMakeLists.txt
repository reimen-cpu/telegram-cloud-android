cmake_minimum_required(VERSION 3.22)
project(TelegramCloudCore LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build as a shared library for Android
set(BUILD_SHARED_LIBS ON)

if(NOT ANDROID)
    message(FATAL_ERROR "This CMakeLists.android.txt is intended to be used with Android/NDK builds (ANDROID must be defined)")
endif()

if(NOT DEFINED ANDROID_ABI)
    message(FATAL_ERROR "ANDROID_ABI must be provided by the build system")
endif()

message(STATUS "Building for ABI: ${ANDROID_ABI}")

# Map ABI-specific variables to generic ones
string(TOUPPER "${ANDROID_ABI}" _ABI_UPPER)
string(REPLACE "-" "_" _ABI_UPPER "${_ABI_UPPER}")

# Check for ABI-specific vars first, then fall back to generic
if(DEFINED OPENSSL_ROOT_DIR_${_ABI_UPPER})
    set(OPENSSL_ROOT_DIR "${OPENSSL_ROOT_DIR_${_ABI_UPPER}}")
    message(STATUS "Using ABI-specific OPENSSL_ROOT_DIR: ${OPENSSL_ROOT_DIR}")
endif()
if(DEFINED CURL_ROOT_${_ABI_UPPER})
    set(CURL_ROOT "${CURL_ROOT_${_ABI_UPPER}}")
    message(STATUS "Using ABI-specific CURL_ROOT: ${CURL_ROOT}")
endif()
if(DEFINED SQLCIPHER_ROOT_${_ABI_UPPER})
    set(SQLCIPHER_ROOT "${SQLCIPHER_ROOT_${_ABI_UPPER}}")
    message(STATUS "Using ABI-specific SQLCIPHER_ROOT: ${SQLCIPHER_ROOT}")
endif()

message(STATUS "Final OPENSSL_ROOT_DIR = ${OPENSSL_ROOT_DIR}")
message(STATUS "Final CURL_ROOT = ${CURL_ROOT}")
message(STATUS "Final SQLCIPHER_ROOT = ${SQLCIPHER_ROOT}")

# Include project headers (target-level)

# Allow the builder to specify a directory with prebuilt Android libs
set(PREBUILT_LIB_DIR "" CACHE PATH "Directory containing prebuilt Android libraries (optional)")

# Core includes
# Use target include directories after the target is created to keep modern CMake usage

# Core sources (exclude UI-related sources like main.cpp, mainwindow.cpp, helpdialog.cpp)
set(SOURCES
    src/config.cpp
    src/database.cpp
    src/envmanager.cpp
    src/obfuscated_strings_android.cpp
    src/telegramhandler.cpp
    src/apiserver.cpp
    src/fileuploader.cpp
    src/filedownloader.cpp
    src/chunkedupload.cpp
    src/chunkeddownload.cpp
    src/batchoperations.cpp
    src/uploadprogressmanager.cpp
    src/logger.cpp
    src/universallinkgenerator.cpp
    src/universallinkdownloader.cpp
    src/telegramnotifier.cpp
    src/backupmanager.cpp
    src/tempdownloaddb.cpp
)

# JNI / Android glue (telegram_cloud_jni_wrapper.cpp is the real implementation)
list(APPEND SOURCES
    android_jni/telegram_cloud_jni_wrapper.cpp
)

set(HEADERS
    include/config.h
    include/database.h
    include/envmanager.h
    include/telegramhandler.h
    include/apiserver.h
    include/fileuploader.h
    include/filedownloader.h
    include/chunkedupload.h
    include/uploadprogressmanager.h
    include/logger.h
    include/universallinkgenerator.h
    include/universallinkdownloader.h
    include/telegramnotifier.h
    include/backupmanager.h
    include/tempdownloaddb.h
)

# Create shared library
add_library(telegramcloud_core SHARED ${SOURCES} ${HEADERS})

# Targeted include directories
target_include_directories(telegramcloud_core
    PUBLIC
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/third_party/json/include
        ${CMAKE_SOURCE_DIR}/third_party/httplib
)

# Link to Android log library by default
find_library(log-lib log)

target_link_libraries(telegramcloud_core PRIVATE
    ${log-lib}
)

# If a prebuilt directory was provided, try to pick up common libs there
if(PREBUILT_LIB_DIR)
    message(STATUS "Searching prebuilt libs in ${PREBUILT_LIB_DIR}")
    find_library(PREBUILT_CURL NAMES curl PATHS ${PREBUILT_LIB_DIR} NO_DEFAULT_PATH)
    find_library(PREBUILT_SQLCIPHER NAMES sqlcipher sqlite3 PATHS ${PREBUILT_LIB_DIR} NO_DEFAULT_PATH)
    find_library(PREBUILT_SSL NAMES ssl PATHS ${PREBUILT_LIB_DIR} NO_DEFAULT_PATH)
    find_library(PREBUILT_CRYPTO NAMES crypto PATHS ${PREBUILT_LIB_DIR} NO_DEFAULT_PATH)

    if(PREBUILT_CURL)
        target_link_libraries(telegramcloud_core PRIVATE ${PREBUILT_CURL})
    endif()
    if(PREBUILT_SQLCIPHER)
        target_link_libraries(telegramcloud_core PRIVATE ${PREBUILT_SQLCIPHER})
    endif()
    if(PREBUILT_SSL AND PREBUILT_CRYPTO)
        target_link_libraries(telegramcloud_core PRIVATE ${PREBUILT_SSL} ${PREBUILT_CRYPTO})
    endif()
endif()

# If prebuilt dependency dirs are provided via CMake cache, link them directly
# Using absolute paths since find_library has issues with static libs on Android

if(DEFINED OPENSSL_ROOT_DIR)
    message(STATUS "Using OpenSSL from ${OPENSSL_ROOT_DIR}")
    target_include_directories(telegramcloud_core PRIVATE ${OPENSSL_ROOT_DIR}/include)
    
    set(_ssl_lib "${OPENSSL_ROOT_DIR}/lib/libssl.a")
    set(_crypto_lib "${OPENSSL_ROOT_DIR}/lib/libcrypto.a")
    
    if(EXISTS "${_ssl_lib}" AND EXISTS "${_crypto_lib}")
        message(STATUS "Found OpenSSL: ${_ssl_lib}, ${_crypto_lib}")
        target_link_libraries(telegramcloud_core PRIVATE ${_ssl_lib} ${_crypto_lib})
    else()
        message(WARNING "OpenSSL libraries not found at ${_ssl_lib}")
    endif()
endif()

if(DEFINED CURL_ROOT)
    message(STATUS "Using libcurl from ${CURL_ROOT}")
    target_include_directories(telegramcloud_core PRIVATE ${CURL_ROOT}/include)
    
    set(_curl_lib "${CURL_ROOT}/lib/libcurl.a")
    
    if(EXISTS "${_curl_lib}")
        message(STATUS "Found libcurl: ${_curl_lib}")
        target_link_libraries(telegramcloud_core PRIVATE ${_curl_lib})
    else()
        message(WARNING "libcurl not found at ${_curl_lib}")
    endif()
endif()

if(DEFINED SQLCIPHER_ROOT)
    message(STATUS "Using SQLCipher/SQLite3 from ${SQLCIPHER_ROOT}")
    target_include_directories(telegramcloud_core PRIVATE ${SQLCIPHER_ROOT}/include)
    
    set(_sqlite_lib "${SQLCIPHER_ROOT}/lib/libsqlite3.a")
    set(_sqlcipher_lib "${SQLCIPHER_ROOT}/lib/libsqlcipher.a")
    
    if(EXISTS "${_sqlcipher_lib}")
        message(STATUS "Found SQLCipher: ${_sqlcipher_lib}")
        target_link_libraries(telegramcloud_core PRIVATE ${_sqlcipher_lib})
    elseif(EXISTS "${_sqlite_lib}")
        message(STATUS "Found SQLite3: ${_sqlite_lib}")
        target_link_libraries(telegramcloud_core PRIVATE ${_sqlite_lib})
    else()
        message(WARNING "sqlcipher/sqlite3 not found in ${SQLCIPHER_ROOT}/lib")
    endif()
endif()

# Link zlib if available (needed by curl and openssl)
if(DEFINED CURL_ROOT)
    set(_zlib_lib "${CURL_ROOT}/lib/libz.a")
    if(EXISTS "${_zlib_lib}")
        message(STATUS "Found zlib: ${_zlib_lib}")
        target_link_libraries(telegramcloud_core PRIVATE ${_zlib_lib})
    endif()
endif()

# Common compile flags for Android
target_compile_options(telegramcloud_core PRIVATE
    -fvisibility=hidden
    -Wall
    -Wextra
)

# Export a simple C API/visibility for JNI wrappers if needed
target_compile_definitions(telegramcloud_core PRIVATE -DTELEGRAMCLOUD_ANDROID)

install(TARGETS telegramcloud_core
    LIBRARY DESTINATION lib
)
