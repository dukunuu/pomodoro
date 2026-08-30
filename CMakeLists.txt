cmake_minimum_required(VERSION 3.21)

project(PomodoroWindows VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Widgets Svg)

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

qt_add_executable(pomodoro-windows
    src/main.cpp
    src/PlatformBridge.cpp
    src/PlatformBridge.h
)

qt_add_qml_module(pomodoro-windows
    URI PomodoroWindows
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Service.qml
        qml/Dashboard.qml
        qml/Color.qml
        qml/Style.qml
        qml/Border.qml
        qml/KeyboardPanel.qml
        qml/BorderSurface.qml
        qml/Button.qml
        qml/TextField.qml
        qml/PanelSeparator.qml
        qml/PanelToolTip.qml
    RESOURCES
        assets/pomodoro.svg
)

target_include_directories(pomodoro-windows PRIVATE src)

target_link_libraries(pomodoro-windows
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Widgets
        Qt6::Svg
)

set_target_properties(pomodoro-windows PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)
