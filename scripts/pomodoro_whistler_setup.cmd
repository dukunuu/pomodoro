@echo off
setlocal
chcp 65001 >nul
where py >nul 2>&1
if not errorlevel 1 goto use_py
where python >nul 2>&1
if not errorlevel 1 goto use_python
echo Python 3 was not found. Install Python 3 or set POMODORO_PYTHON. 1>&2
set "exitCode=9009"
goto finish
:use_py
py -3 "%~dp0pomodoro_whistler_setup.py" %*
set "exitCode=%errorlevel%"
goto finish
:use_python
python "%~dp0pomodoro_whistler_setup.py" %*
set "exitCode=%errorlevel%"
goto finish
:finish
echo.
echo This window will remain open so you can review the result.
pause
exit /b %exitCode%
