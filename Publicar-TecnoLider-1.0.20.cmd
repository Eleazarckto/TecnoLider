@echo off
setlocal
pushd "%~dp0" || exit /b 1

set "VERSION_TECNOLIDER=1.0.20"
set "BUILD_TECNOLIDER=20"
set "ENTREGA_TECNOLIDER=release\%VERSION_TECNOLIDER%"
set "APK_TECNOLIDER=%ENTREGA_TECNOLIDER%\tecnolider-%VERSION_TECNOLIDER%.apk"
if not exist "%APK_TECNOLIDER%" goto :falta_apk
if not exist "%ENTREGA_TECNOLIDER%\tecnolider-windows-%VERSION_TECNOLIDER%.zip" goto :falta_zip
findstr /b /l /c:"version: %VERSION_TECNOLIDER%+%BUILD_TECNOLIDER%" "pubspec.yaml" >nul
if errorlevel 1 goto :version_incorrecta

set "SDK_TECNOLIDER=%ANDROID_HOME%"
if not defined SDK_TECNOLIDER set "SDK_TECNOLIDER=%ANDROID_SDK_ROOT%"
if not defined SDK_TECNOLIDER set "SDK_TECNOLIDER=%LOCALAPPDATA%\Android\Sdk"
set "AAPT_TECNOLIDER="
for /f "delims=" %%D in ('dir /ad /b /o-n "%SDK_TECNOLIDER%\build-tools" 2^>nul') do (
    if not defined AAPT_TECNOLIDER if exist "%SDK_TECNOLIDER%\build-tools\%%D\aapt.exe" set "AAPT_TECNOLIDER=%SDK_TECNOLIDER%\build-tools\%%D\aapt.exe"
)
if not defined AAPT_TECNOLIDER goto :falta_sdk
"%AAPT_TECNOLIDER%" dump badging "%APK_TECNOLIDER%" | findstr /b /l /c:"package: name='com.tecnolider.tecno_lider' versionCode='%BUILD_TECNOLIDER%' versionName='%VERSION_TECNOLIDER%'" >nul
if errorlevel 1 goto :apk_incorrecto

set "BASH_TECNOLIDER=%ProgramFiles%\Git\bin\bash.exe"
if exist "%BASH_TECNOLIDER%" goto :publicar
for /f "delims=" %%G in ('where git.exe 2^>nul') do (
    if exist "%%~dpG..\bin\bash.exe" set "BASH_TECNOLIDER=%%~dpG..\bin\bash.exe"
)
if not exist "%BASH_TECNOLIDER%" goto :falta_git

:publicar
set "VERIFICACION_TECNOLIDER="
if /i "%~1"=="--verificar" set "VERIFICACION_TECNOLIDER=--verificar"
"%BASH_TECNOLIDER%" tool/publicar.sh --sin-compilar --con-correccion-precios %VERIFICACION_TECNOLIDER%
set "ESTADO_TECNOLIDER=%ERRORLEVEL%"
goto :salir

:falta_apk
echo Falta el APK de Android %VERSION_TECNOLIDER%.
goto :error

:falta_zip
echo Falta el ZIP de Windows en "%ENTREGA_TECNOLIDER%".
goto :error

:falta_sdk
echo No se encontro aapt.exe para comprobar la version del APK.
goto :error

:apk_incorrecto
echo El APK no corresponde a TecnoLider %VERSION_TECNOLIDER%+%BUILD_TECNOLIDER%.
goto :error

:version_incorrecta
echo Esta copia del proyecto debe tener la version %VERSION_TECNOLIDER%+%BUILD_TECNOLIDER%.
goto :error

:falta_git
echo No se encontro Git Bash.

:error
set "ESTADO_TECNOLIDER=1"

:salir
popd
if /i not "%~1"=="--verificar" pause
exit /b %ESTADO_TECNOLIDER%
