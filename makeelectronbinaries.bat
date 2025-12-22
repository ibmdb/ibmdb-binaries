@echo off
setlocal enabledelayedexpansion

REM ibmdb-binaries repo should be cloned in the same directory where node-ibm_db is cloned. 
set "CURR_DIR=%CD%"
for %%I in ("%CURR_DIR%\..") do set "PARENT_DIR=%%~fI"
set "IBMDB_DIR=%PARENT_DIR%\ibm_db"

if not exist "%IBMDB_DIR%\installer\driverInstall.js" (
    echo Error: unable to find ibm_db directory!
    exit /b 1
)

REM Dependencies check
where node >nul 2>nul
if errorlevel 1 (
    echo Required command 'node' not found. Please install it.
    exit /b 1
)

REM Check for PowerShell (should be available on all modern Windows systems)
where powershell >nul 2>nul
if errorlevel 1 (
    echo Required command 'powershell' not found. Please install it.
    exit /b 1
)

REM Config
for /f "tokens=*" %%v in ('node -v') do set "INSTALLED_NODE_V=%%v"
set "LATEST_VERSION="
set "versionFound=false"
set "LATEST_VER=37.1.0"
set "MAJOR_VER=37"
for %%I in ("%~dp0..\..") do set "NODEWORK=%%~fI"
echo Installed node = !INSTALLED_NODE_V!
set "IBM_DB_HOME="

set "CREATE_BINARY=true"
set "FORCE_BINARY=false"
if "%~1"=="force" (
    set "FORCE_BINARY=true"
    echo FORCE_BINARY = !FORCE_BINARY!
)

set "PLAT=win"
set "OSDIR=ntx64"

goto :main

:getLatestElectronVersion
set "electronVerFile=!CURR_DIR!\electronVersions.txt"
echo Fetching the latest Electron v!MAJOR_VER!.x versions...

REM Create temporary PowerShell script with expanded variables
set "PS_SCRIPT=!TEMP!\getElectronVersion_!MAJOR_VER!.ps1"
echo try { > "!PS_SCRIPT!"
echo     $ErrorActionPreference = 'Stop' >> "!PS_SCRIPT!"
echo     $headers = @{ 'User-Agent' = 'Mozilla/5.0' } >> "!PS_SCRIPT!"
echo     $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/electron/electron/releases?per_page=100' -Headers $headers >> "!PS_SCRIPT!"
echo     $version = ($response ^| Where-Object { $_.tag_name -match '^v!MAJOR_VER!\.[0-9]+\.[0-9]+$' } ^| Select-Object -First 1).tag_name >> "!PS_SCRIPT!"
echo     if ($version) { $version.TrimStart('v') } >> "!PS_SCRIPT!"
echo } catch { } >> "!PS_SCRIPT!"

REM Execute PowerShell script and capture output
set "version="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"`) do (
    set "version=%%a"
)

REM Clean up temporary script
del "!PS_SCRIPT!" 2>nul

REM Output results
if "!version!"=="" (
    echo X No stable Electron v!MAJOR_VER!.x version found.
    set "versionFound=false"
) else (
    echo + Latest stable Electron v!MAJOR_VER!.x version: !version!
    set "versionFound=true"
    set "LATEST_VER=!version!"
)
exit /b 0

:createBinary
where node >nul 2>nul
if not errorlevel 1 (
    for /f "tokens=*" %%v in ('node -v') do set "NODEVER=%%v"
    echo Using node version: !NODEVER!
) else (
    echo Unable to find installed nodejs version.
    exit /b 1
)

cd /d "!IBMDB_DIR!"
set "ELECTRON=!LATEST_VER!"
call npm install
echo !errorlevel!

if not exist "!CURR_DIR!\!OSDIR!" (
    mkdir "!CURR_DIR!\!OSDIR!"
)

if exist "!IBMDB_DIR!\build\Release\odbc_bindings.node" (
    copy "!IBMDB_DIR!\build\Release\odbc_bindings.node" "!CURR_DIR!\!OSDIR!\odbc_bindings_!PLAT!_!MAJOR_VER!.node"
    echo Copied !CURR_DIR!\!OSDIR!\odbc_bindings_!PLAT!_!MAJOR_VER!.node for electron !LATEST_VER!
    echo.
    call :updateReadmeFile
    call :updateVersionFile
    echo Running basic tests...
    node "!IBMDB_DIR!\test\test-basic-test.js
)
cd /d "!CURR_DIR!"
exit /b 0

:checkForNewVersion
set "FILE_NAME=!CURR_DIR!\binaryVersions.txt"
set "CREATE_BINARY=true"

if not exist "!FILE_NAME!" (
    echo Error: File '!FILE_NAME!' not found.
    exit /b 1
)

set "PATTERN=Windows x86_64 Electron !MAJOR_VER! Version = "
set "MATCHING_LINE="

for /f "tokens=*" %%a in ('findstr /b /c:"!PATTERN!" "!FILE_NAME!"') do (
    set "MATCHING_LINE=%%a"
)

if not "!MATCHING_LINE!"=="" (
    REM Extract current version from version file (token 7: Windows x86_64 Electron 35 Version = 35.7.5)
    for /f "tokens=7 delims= " %%v in ("!MATCHING_LINE!") do set "CURRENT_VERSION=%%v"

    if "!CURRENT_VERSION!"=="!LATEST_VER!" (
        echo Electron !MAJOR_VER! Version is already !LATEST_VER!. No update needed.
        set "CREATE_BINARY=false"
    )
)

REM Check if force option is used
if "!FORCE_BINARY!"=="true" set "CREATE_BINARY=true"

REM Check for binary file
if "!CREATE_BINARY!"=="false" (
    if not exist "!CURR_DIR!\!OSDIR!\odbc_bindings_!PLAT!_!MAJOR_VER!.node" (
        set "CREATE_BINARY=true"
    )
)
exit /b 0

:updateVersionFile
set "FILE_NAME=!CURR_DIR!\binaryVersions.txt"

if not exist "!FILE_NAME!" (
    echo Error: File '!FILE_NAME!' not found.
    exit /b 1
)

set "PATTERN=Windows x86_64 Electron !MAJOR_VER! Version = "
set "MATCHING_LINE="

for /f "tokens=*" %%a in ('findstr /b /c:"!PATTERN!" "!FILE_NAME!"') do (
    set "MATCHING_LINE=%%a"
)

if not "!MATCHING_LINE!"=="" (
    REM Extract current version from version file (token 7: Windows x86_64 Electron 35 Version = 35.7.5)
    for /f "tokens=7 delims= " %%v in ("!MATCHING_LINE!") do set "CURRENT_VERSION=%%v"

    if "!CURRENT_VERSION!"=="!LATEST_VER!" (
        echo Electron !MAJOR_VER! Version is already !LATEST_VER!. No update needed.
        exit /b 0
    )

    REM Replace existing line
    set "TMP_FILE=!TEMP!\binaryVersions_temp.txt"
    type nul > "!TMP_FILE!"
    for /f "usebackq delims=" %%a in ("!FILE_NAME!") do (
        set "line=%%a"
        if "!line:~0,34!"=="!PATTERN:~0,34!" (
            echo !PATTERN!!LATEST_VER!>> "!TMP_FILE!"
        ) else (
            echo %%a>> "!TMP_FILE!"
        )
    )
    move /y "!TMP_FILE!" "!FILE_NAME!" >nul
    echo Updated Electron !MAJOR_VER! Version from !CURRENT_VERSION! to !LATEST_VER! in version file
) else (
    REM Add new line at the end
    echo !PATTERN!!LATEST_VER!>> "!FILE_NAME!"
    echo Added new line: !PATTERN!!LATEST_VER! to version file
)
exit /b 0

:updateReadmeFile
set "FILE_NAME=!CURR_DIR!\README.md"

if not exist "!FILE_NAME!" (
    echo Error: File '!FILE_NAME!' not found.
    exit /b 1
)

set "PATTERN=* Electron !MAJOR_VER! Version = "
set "MATCHING_LINE="

for /f "tokens=*" %%a in ('findstr /b /c:"!PATTERN!" "!FILE_NAME!"') do (
    set "MATCHING_LINE=%%a"
)

if not "!MATCHING_LINE!"=="" (
    REM Extract current electron version from readme file (token 6: * Electron 35 Version = 35.7.5)
    for /f "tokens=6 delims= " %%v in ("!MATCHING_LINE!") do set "CURRENT_VERSION=%%v"

    if "!CURRENT_VERSION!"=="!LATEST_VER!" (
        echo Electron !MAJOR_VER! Version is already !LATEST_VER!. No update needed.
        exit /b 0
    )

    REM Replace existing line
    set "TMP_FILE=!TEMP!\README_temp.txt"
    type nul > "!TMP_FILE!"
    for /f "usebackq delims=" %%a in ("!FILE_NAME!") do (
        set "line=%%a"
        if "!line:~0,20!"=="!PATTERN:~0,20!" (
            echo !PATTERN!!LATEST_VER!>> "!TMP_FILE!"
        ) else (
            echo %%a>> "!TMP_FILE!"
        )
    )
    move /y "!TMP_FILE!" "!FILE_NAME!" >nul
    echo Updated Electron !MAJOR_VER! Version from !CURRENT_VERSION! to !LATEST_VER! in Readme.md file
) else (
    REM Add new line at the end
    echo !PATTERN!!LATEST_VER!>> "!FILE_NAME!"
    echo Added new line: !PATTERN!!LATEST_VER! to Readme.md file
)
exit /b 0

:main
REM Loop through Electron versions 32 to 40
for %%v in (32 33 34 35 36 37 38 39 40) do (
    set "MAJOR_VER=%%v"
    call :getLatestElectronVersion
    
    if "!versionFound!"=="true" (
        call :checkForNewVersion
        if "!CREATE_BINARY!"=="true" (
            call :createBinary
        )
    )
)

dir "!CURR_DIR!\!OSDIR!"
echo Done!
endlocal
