@echo off

REM Get the current build configuration
if "%1" == "Debug" (
  set DEBUG_OR_RELEASE=Debug
) else (
  set DEBUG_OR_RELEASE=Release
)

REM Perform the install action for the specified configuration
copy "%2\..\..\shared\%DEBUG_OR_RELEASE%\recovery.dll" "%2\..\..\runner\%DEBUG_OR_RELEASE%\recovery.dll" /Y
