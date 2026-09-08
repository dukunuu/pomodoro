cmake_minimum_required(VERSION 3.21)

project(Pomodoro VERSION 1.6.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Widgets Svg)

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

# Four QML modules are built here, so each needs its own directory named after
# its URI. Qt lays them out under this root and adds it to the import path.
set(QT_QML_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml)

# ---------------------------------------------------------------------------
# Compatibility modules
#
# core/qml/Service.qml and core/qml/Dashboard.qml are shared verbatim with the
# Omarchy Quickshell plugin. Rather than maintaining a second copy with the
# imports rewritten, the desktop app registers QML modules under the same URIs
# that Quickshell and the Omarchy shell provide, backed by Qt equivalents.
# ---------------------------------------------------------------------------

qt_add_library(pomodoro_quickshell_io STATIC)
qt_add_qml_module(pomodoro_quickshell_io
    URI Quickshell.Io
    VERSION 1.0
    SOURCES
        platform/desktop/src/QuickshellIo.h
        platform/desktop/src/QuickshellIo.cpp
)
target_include_directories(pomodoro_quickshell_io PUBLIC platform/desktop/src)

qt_add_library(pomodoro_qs_commons STATIC)
set_source_files_properties(
    platform/desktop/qml/qs/Commons/Color.qml
    platform/desktop/qml/qs/Commons/Style.qml
    platform/desktop/qml/qs/Commons/Border.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)
qt_add_qml_module(pomodoro_qs_commons
    URI qs.Commons
    VERSION 1.0
    QML_FILES
        platform/desktop/qml/qs/Commons/Color.qml
        platform/desktop/qml/qs/Commons/Style.qml
        platform/desktop/qml/qs/Commons/Border.qml
)

qt_add_library(pomodoro_qs_ui STATIC)
qt_add_qml_module(pomodoro_qs_ui
    URI qs.Ui
    VERSION 1.0
    QML_FILES
        platform/desktop/qml/qs/Ui/BorderSurface.qml
        platform/desktop/qml/qs/Ui/Button.qml
        platform/desktop/qml/qs/Ui/KeyboardPanel.qml
        platform/desktop/qml/qs/Ui/PanelSeparator.qml
        platform/desktop/qml/qs/Ui/PanelToolTip.qml
        core/ui/TextArea.qml
        platform/desktop/qml/qs/Ui/TextField.qml
)
target_link_libraries(pomodoro_qs_ui PRIVATE pomodoro_qs_commonsplugin)

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

qt_add_executable(pomodoro
    platform/desktop/src/main.cpp
    platform/desktop/src/PlatformBridge.cpp
    platform/desktop/src/PlatformBridge.h
)

if (WIN32)
    target_sources(pomodoro PRIVATE assets/pomodoro.rc)
endif()

qt_add_qml_module(pomodoro
    URI Pomodoro
    VERSION 1.0
    QML_FILES
        core/qml/Service.qml
        core/qml/Dashboard.qml
        core/qml/IconSet.qml
        platform/desktop/qml/Platform.qml
        platform/desktop/qml/Main.qml
        platform/desktop/qml/TimerWidget.qml
    RESOURCES
        assets/pomodoro.svg
        assets/pomodoro.ico
)

target_include_directories(pomodoro PRIVATE platform/desktop/src)
target_compile_definitions(pomodoro PRIVATE POMODORO_VERSION="${PROJECT_VERSION}")

target_link_libraries(pomodoro
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Svg
        pomodoro_quickshell_ioplugin
        pomodoro_qs_commonsplugin
        pomodoro_qs_uiplugin
)

if (WIN32)
    target_link_libraries(pomodoro PRIVATE ole32 shell32 uuid)
endif()

set_target_properties(pomodoro PROPERTIES WIN32_EXECUTABLE TRUE)

# ---------------------------------------------------------------------------
# Packaging
# ---------------------------------------------------------------------------

# The integration bridges are plain Python so the same Calendar and Whistler
# request logic runs unchanged on all three platforms and can be tested outside
# the QML host. macOS keeps them inside the bundle; the others beside the
# executable.
if (APPLE)
    set_target_properties(pomodoro PROPERTIES
        MACOSX_BUNDLE TRUE
        OUTPUT_NAME "Pomodoro"
        MACOSX_BUNDLE_BUNDLE_NAME "Pomodoro"
        MACOSX_BUNDLE_GUI_IDENTIFIER "local.pomodoro.Pomodoro"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_ICON_FILE "pomodoro.icns"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/packaging/macos/Info.plist.in"
    )

    # An .icns is only buildable with macOS tooling, so it is generated at
    # build time from the shared SVG when it is not already checked in.
    set(POMODORO_ICNS "${CMAKE_CURRENT_BINARY_DIR}/pomodoro.icns")
    add_custom_command(
        OUTPUT ${POMODORO_ICNS}
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/packaging/macos/make-icns.sh
                ${CMAKE_CURRENT_SOURCE_DIR}/assets/pomodoro.svg ${POMODORO_ICNS}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/assets/pomodoro.svg
                ${CMAKE_CURRENT_SOURCE_DIR}/packaging/macos/make-icns.sh
        COMMENT "Generating macOS application icon"
        VERBATIM
    )
    add_custom_target(pomodoro_icns DEPENDS ${POMODORO_ICNS})
    add_dependencies(pomodoro pomodoro_icns)
    target_sources(pomodoro PRIVATE ${POMODORO_ICNS})
    set_source_files_properties(${POMODORO_ICNS} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")

    add_custom_command(TARGET pomodoro POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${CMAKE_CURRENT_SOURCE_DIR}/scripts
                $<TARGET_BUNDLE_CONTENT_DIR:pomodoro>/Resources/scripts
        VERBATIM
    )
else()
    add_custom_command(TARGET pomodoro POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${CMAKE_CURRENT_SOURCE_DIR}/scripts
                $<TARGET_FILE_DIR:pomodoro>/scripts
        VERBATIM
    )
endif()
