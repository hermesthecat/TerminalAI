@echo off
set ENV_PATH=%USERPROFILE%\.virtualenvs\bashai
set COMMAND_PATH=Y:\New folder (18)\bash-ai-main\ai.py

if not exist "%ENV_PATH%" (
    echo Virtual environment not found. Please run install.ps1 first.
    exit /b 1
)

call "%ENV_PATH%\Scripts\activate.bat"
python "%COMMAND_PATH%" %*
