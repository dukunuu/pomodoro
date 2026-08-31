@echo off
setlocal
where py >nul 2>&1
if not errorlevel 1 goto use_py
where python >nul 2>&1
if not errorlevel 1 goto use_python
echo Python 3 was not found. Install Python 3 or set POMODORO_PYTHON. 1>&2
exit /b 9009
:use_py
py -3 "%~dp0pomodoro_whistler_import.py" %*
exit /b %errorlevel%
:use_python
python "%~dp0pomodoro_whistler_import.py" %*
exit /b %errorlevel%
