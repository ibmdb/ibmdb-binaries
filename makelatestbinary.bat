@echo off
setlocal enabledelayedexpansion

REM Build the NAPI ibm_db binary with the latest Node.js on Windows x64.
REM Usage: makelatestbinary.bat [force]

set "CURR_DIR=%~dp0"
if "%CURR_DIR:~-1%"=="\" set "CURR_DIR=%CURR_DIR:~0,-1%"
for %%I in ("%CURR_DIR%\..") do set "IBMDB_DIR=%%~fI\ibm_db"
for %%I in ("%CURR_DIR%\..\..") do set "NODEWORK=%%~fI"
set "FORCE_BINARY=false"
if "%~1"=="force" set "FORCE_BINARY=true"
set "BINARY_NAME=odbc_bindings_win.node"
set "ARCHIVE_PATTERN=win-x64.zip"

if not exist "%IBMDB_DIR%\installer\driverInstall.js" (
    echo Error: unable to find ibm_db directory at %IBMDB_DIR%
    exit /b 1
)

where curl >nul 2>nul
if errorlevel 1 (
    echo Required command 'curl' not found. Please install it.
    exit /b 1
)
where powershell >nul 2>nul
if errorlevel 1 (
    echo Required command 'powershell' not found.
    exit /b 1
)

REM Find the latest Node.js release
set "BASE_URL=https://nodejs.org/download/release/latest/"
set "TARBALL="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$r = (Invoke-WebRequest -UseBasicParsing '%BASE_URL%').Content; if ($r -match 'node-v\d+\.\d+\.\d+-%ARCHIVE_PATTERN%') { $Matches[0] }"`) do set "TARBALL=%%a"
if "!TARBALL!"=="" (
    echo Failed to detect latest Node.js version.
    exit /b 1
)
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "'!TARBALL!' -replace '^node-(v\d+\.\d+\.\d+)-.*','$1'"`) do set "LATEST_VERSION=%%a"
set "NODEDIR=!NODEWORK!\node!LATEST_VERSION!"
set "UNZIP_NAME=!TARBALL:.zip=!"
echo Latest Node.js = !LATEST_VERSION!

set "INSTALLED_NODE_V="
where node >nul 2>nul
if not errorlevel 1 for /f "tokens=*" %%v in ('node -v') do set "INSTALLED_NODE_V=%%v"

if exist "!NODEDIR!\node.exe" (
    echo Found !NODEDIR!
) else if "!INSTALLED_NODE_V!"=="!LATEST_VERSION!" (
    for /f "delims=" %%p in ('where node') do (
        if not defined NODE_EXE set "NODE_EXE=%%p"
    )
    for %%I in ("!NODE_EXE!") do set "NODEDIR=%%~dpI"
    if "!NODEDIR:~-1!"=="\" set "NODEDIR=!NODEDIR:~0,-1!"
    echo Latest version is already installed at !NODEDIR!
) else (
    echo Downloading !BASE_URL!!TARBALL!
    cd /d "!NODEWORK!"
    curl -fLO "!BASE_URL!!TARBALL!"
    if errorlevel 1 (
        echo Download failed!
        cd /d "!CURR_DIR!"
        exit /b 1
    )
    powershell -NoProfile -Command "Expand-Archive -Path '!TARBALL!' -DestinationPath '!NODEWORK!' -Force"
    if errorlevel 1 (
        echo Extraction failed!
        cd /d "!CURR_DIR!"
        exit /b 1
    )
    move "!NODEWORK!\!UNZIP_NAME!" "!NODEDIR!" >nul
    del "!TARBALL!"
    cd /d "!CURR_DIR!"
)

REM Make the latest node the effective one: NODEWORK\nodejs, keeping the old one as node<version>
set "ACTIVE_DIR=!NODEWORK!\nodejs"
for %%I in ("!NODEDIR!\..") do set "NODEDIR_PARENT=%%~fI"
if /i "!NODEDIR_PARENT!"=="!NODEWORK!" if /i not "!NODEDIR!"=="!ACTIVE_DIR!" (
    if exist "!ACTIVE_DIR!" (
        set "OLD_VERSION="
        for /f "tokens=*" %%v in ('"!ACTIVE_DIR!\node.exe" -v 2^>nul') do set "OLD_VERSION=%%v"
        if "!OLD_VERSION!"=="" (
            echo Error: cannot determine version of !ACTIVE_DIR!
            exit /b 1
        )
        if exist "!NODEWORK!\node!OLD_VERSION!" (
            echo Error: !NODEWORK!\node!OLD_VERSION! already exists; cannot preserve !ACTIVE_DIR!
            exit /b 1
        )
        move "!ACTIVE_DIR!" "!NODEWORK!\node!OLD_VERSION!" >nul
        if errorlevel 1 exit /b 1
        echo Moved old nodejs to !NODEWORK!\node!OLD_VERSION!
    )
    move "!NODEDIR!" "!ACTIVE_DIR!" >nul
    if errorlevel 1 exit /b 1
    set "NODEDIR=!ACTIVE_DIR!"
    echo Latest node !LATEST_VERSION! is now !ACTIVE_DIR!
)

set "PATH=!NODEDIR!;!PATH!"
for /f "tokens=*" %%v in ('node -v') do echo Using node %%v

REM Skip the build if the binary for this version already exists
set "VERSION_FILE=!CURR_DIR!\binaryVersions.txt"
set "PATTERN=Windows x86_64 NAPI Node Version = "
if "!FORCE_BINARY!"=="false" if exist "!CURR_DIR!\!BINARY_NAME!" if exist "!VERSION_FILE!" (
    findstr /x /c:"!PATTERN!!LATEST_VERSION!" "!VERSION_FILE!" >nul 2>nul
    if not errorlevel 1 (
        echo !BINARY_NAME! is already built with !LATEST_VERSION!. Use 'force' to rebuild.
        exit /b 0
    )
)

set "IBM_DB_HOME="
set "DOWNLOAD_CLIDRIVER=true"
cd /d "!IBMDB_DIR!"
call npm install
if errorlevel 1 (
    echo npm install failed!
    cd /d "!CURR_DIR!"
    exit /b 1
)

set "BUILT=!IBMDB_DIR!\build\Release\odbc_bindings.node"
if not exist "!BUILT!" (
    echo Error: !BUILT! was not created.
    cd /d "!CURR_DIR!"
    exit /b 1
)

copy /y "!BUILT!" "!CURR_DIR!\!BINARY_NAME!" >nul
if errorlevel 1 exit /b 1
echo Copied !BUILT! to !CURR_DIR!\!BINARY_NAME!
node "!IBMDB_DIR!\test\test-basic-test.js"
echo.

if exist "!VERSION_FILE!" (
    findstr /b /c:"!PATTERN!" "!VERSION_FILE!" >nul 2>nul
    if errorlevel 1 (
        >>"!VERSION_FILE!" echo !PATTERN!!LATEST_VERSION!
    ) else (
        powershell -NoProfile -Command "$f='!VERSION_FILE!'; $p='!PATTERN!'; (Get-Content $f) | ForEach-Object { if ($_.StartsWith($p)) { $p + '!LATEST_VERSION!' } else { $_ } } | Set-Content $f"
    )
)

cd /d "!CURR_DIR!"
git status
echo Done!
endlocal
