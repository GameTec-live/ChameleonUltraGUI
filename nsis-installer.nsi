!include "MUI2.nsh"
; The name of the installer
Name "Chameleon Ultra GUI"

; The file to write
OutFile "chameleonultragui-setup-win.exe"

; Request application privileges for Windows Vista and higher
RequestExecutionLevel admin

; Build Unicode installer
Unicode True

; The default installation directory
InstallDir $PROGRAMFILES\chameleonultragui

; Registry key to check for directory (so if you install again, it will 
; overwrite the old one automatically)
InstallDirRegKey HKLM "Software\chameleonultragui" "Install_Dir"
!define MUI_ICON "chameleonultragui\windows\runner\resources\app_icon.ico"

;--------------------------------

; Pages
!insertmacro MUI_PAGE_LICENSE "LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
  
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

;--------------------------------

!insertmacro MUI_LANGUAGE "English"


; The stuff to install
Section "Chameleon Ultra GUI (required)"

  SectionIn RO
  
  ; Set output path to the installation directory.
  SetOutPath $INSTDIR
  
  ; Put file there
  File "chameleonultragui\build\windows\runner\Release\chameleonultragui.exe"
  File "chameleonultragui\build\windows\runner\Release\flutter_libserialport_plugin.dll"
  File "chameleonultragui\build\windows\runner\Release\flutter_windows.dll"
  File "chameleonultragui\build\windows\runner\Release\recovery.dll"
  File "chameleonultragui\build\windows\runner\Release\serialport.dll"
  File "chameleonultragui\build\windows\runner\Release\file_saver_plugin.dll"
  File "LICENSE"
  File /r "chameleonultragui\build\windows\runner\Release\data"
  
  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\chameleonultragui "Install_Dir" "$INSTDIR"
  
  ; Write the uninstall keys for Windows
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\chameleonultragui" "DisplayName" "Chameleon Ultra GUI"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\chameleonultragui" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\chameleonultragui" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\chameleonultragui" "NoRepair" 1
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
SectionEnd

; Optional section (can be disabled by the user)
Section "Start Menu Shortcuts"
  CreateShortcut "$SMPROGRAMS\Chameleon Ultra GUI.lnk" "$INSTDIR\chameleonultragui.exe"
SectionEnd

; Optional section (can be disabled by the user)
Section "Desktop Shortcut"
  CreateShortcut "$DESKTOP\Chameleon Ultra GUI.lnk" "$INSTDIR\chameleonultragui.exe"
SectionEnd

;--------------------------------

; Uninstaller

Section "Uninstall"
  
  ; Remove registry keys
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\chameleonultragui"
  DeleteRegKey HKLM SOFTWARE\chameleonultragui

  ; Remove files and uninstaller
  Delete $INSTDIR\chameleonultragui.exe
  Delete $INSTDIR\flutter_libserialport_plugin.dll
  Delete $INSTDIR\flutter_windows.dll
  Delete $INSTDIR\recovery.dll
  Delete $INSTDIR\serialport.dll
  Delete  $INSTDIR\file_saver_plugin.dll
  RMDir /r $INSTDIR\data
  Delete $INSTDIR\LICENSE
  Delete $INSTDIR\uninstall.exe

  ; Remove shortcuts, if any
  Delete "$SMPROGRAMS\Chameleon Ultra GUI.lnk"
  Delete "$DESKTOP\Chameleon Ultra GUI.lnk"

  ; Remove directories
  RMDir "$INSTDIR"

SectionEnd
