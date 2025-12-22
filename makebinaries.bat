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

where curl >nul 2>nul
if errorlevel 1 (
    echo Required command 'curl' not found. Please install it.
    exit /b 1
)

REM Config
for /f "tokens=*" %%v in ('node -v') do set "INSTALLED_NODE_V=%%v"
set "LATEST_VERSION="
set "downloaded=false"
set "MAJOR_VER=24"
for %%I in ("%~dp0..\..") do set "NODEWORK=%%~fI"
echo Installed node = !INSTALLED_NODE_V!
echo NODEWORK = !NODEWORK!
set "IBM_DB_HOME="
set "DOWNLOAD_CLIDRIVER=true"

set "CREATE_BINARY=true"
set "FORCE_BINARY=false"
if "%~1"=="force" set "FORCE_BINARY=true"

set "ARCHIVE_PATTERN=win-x64.zip"
set "PLAT=ntx64"

goto :main

:downloadLatestNodejs
set "BASE_URL=https://nodejs.org/download/release/latest-v!MAJOR_VER!.x/"
set "downloaded=false"
set "TARBALL="
set "LATEST_VERSION="

REM Get latest version filename using curl
for /f "tokens=*" %%a in ('curl -s "!BASE_URL!" ^| findstr /r "node-v!MAJOR_VER!\.[0-9]*\.[0-9]*-!ARCHIVE_PATTERN!"') do (
    set "line=%%a"
    for /f "tokens=2 delims=<>" %%b in ("!line!") do (
        if "!TARBALL!"=="" (
            set "TARBALL=%%b"
        )
    )
)

if "!TARBALL!"=="" (
    echo Failed to detect latest Node.js version.
    exit /b 1
)

REM Extract version string from filename (e.g., node-v24.1.0-win-x64.zip -> v24.1.0)
for /f "tokens=1,2,3,4 delims=-." %%a in ("!TARBALL!") do (
    set "LATEST_VERSION=%%b.%%c.%%d"
)

set "NODEDIR_NAME=!NODEWORK!\node!LATEST_VERSION!"

REM Check if we already have this version
if "!LATEST_VERSION!"=="!INSTALLED_NODE_V!" (
    echo No new version found. Latest version ^(!LATEST_VERSION!^) already installed.
    set "downloaded=true"
    exit /b 0
)
if exist "!NODEDIR_NAME!" (
    echo No new version found. Latest version ^(!LATEST_VERSION!^) already exist.
    set "downloaded=true"
    exit /b 0
)

REM Download new version
set "DOWNLOAD_URL=!BASE_URL!!TARBALL!"
echo New version detected: !LATEST_VERSION!
echo Downloading from: !DOWNLOAD_URL!
cd /d "!NODEWORK!"

curl -LO "!DOWNLOAD_URL!"

if errorlevel 1 (
    echo Download failed!
    cd /d "!CURR_DIR!"
    exit /b 1
)

echo Download complete: !TARBALL!

REM Extract zip file (requires PowerShell or tar on Windows 10+)
powershell -command "Expand-Archive -Path '!TARBALL!' -DestinationPath '!NODEWORK!' -Force"

REM Rename extracted directory
for /f "tokens=*" %%a in ("!TARBALL!") do set "UNTAR_NAME=%%~na"
if exist "!NODEWORK!\!UNTAR_NAME!" (
    move "!NODEWORK!\!UNTAR_NAME!" "!NODEDIR_NAME!"
)

del "!TARBALL!"
dir "!NODEWORK!"
set "downloaded=true"
cd /d "!CURR_DIR!"
exit /b 1

:createBinary
where node >nul 2>nul
if not errorlevel 1 (
    for /f "tokens=*" %%v in ('node -v') do set "NODEVER=%%v"
    if exist "!NODEWORK!\nodejs" (
        move "!NODEWORK!\nodejs" "!NODEWORK!\node!NODEVER!"
    )
) else (
    echo Unable to find installed nodejs version.
)

if exist "!NODEWORK!\node!LATEST_VERSION!" (
    move "!NODEWORK!\node!LATEST_VERSION!" "!NODEWORK!\nodejs"
)

cd /d "!IBMDB_DIR!"
call npm install

if not exist "!CURR_DIR!\!PLAT!" (
    mkdir "!CURR_DIR!\!PLAT!"
)

if exist "!IBMDB_DIR!\build\Release\odbc_bindings.node" (
    copy "!IBMDB_DIR!\build\Release\odbc_bindings.node" "!CURR_DIR!\!PLAT!\odbc_bindings.node.!MAJOR_VER!"
    echo Copied !CURR_DIR!\!PLAT!\odbc_bindings.node.!MAJOR_VER! for !LATEST_VERSION!
    echo.
    call :updateReadmeFile
    call :updateVersionFile
    echo Running basic tests...
    node "!IBMDB_DIR!\test\test-basic-test.js

)
cd /d "!CURR_DIR!"
exit /b 0

:checkLatestVersionInFile
set "README=!CURR_DIR!\binaryVersions.txt"
set "CREATE_BINARY=true"

if not exist "!README!" (
    echo Error: File '!README!' not found.
    exit /b 1
)

set "PATTERN=Windows x86_64 Node !MAJOR_VER! Version = "
set "MATCHING_LINE="

for /f "tokens=*" %%a in ('findstr /b /c:"!PATTERN!" "!README!"') do (
    set "MATCHING_LINE=%%a"
)

if not "!MATCHING_LINE!"=="" (
    REM Extract current version from version file (token 7: Windows x86_64 Node 24 Version = v24.12.0)
    for /f "tokens=7 delims= " %%v in ("!MATCHING_LINE!") do set "CURRENT_VERSION=%%v"

    if "!CURRENT_VERSION!"=="!LATEST_VERSION!" (
        echo Node version !CURRENT_VERSION! is present in version file.
        set "CREATE_BINARY=false"
    )
)

REM Check if force option is used
if "!FORCE_BINARY!"=="true" set "CREATE_BINARY=true"

REM Check for binary file
if "!CREATE_BINARY!"=="false" (
    if not exist "!CURR_DIR!\!PLAT!\odbc_bindings.node.!MAJOR_VER!" (
        set "CREATE_BINARY=true"
    )
)
exit /b 0

:updateVersionFile
set "README=!CURR_DIR!\binaryVersions.txt"

if not exist "!README!" (
    echo Error: File '!README!' not found.
    exit /b 1
)

set "PATTERN=Windows x86_64 Node !MAJOR_VER! Version = "
set "MATCHING_LINE="

for /f "tokens=*" %%a in ('findstr /b /c:"!PATTERN!" "!README!"') do (
    set "MATCHING_LINE=%%a"
)

if not "!MATCHING_LINE!"=="" (
    REM Extract current version from version file (token 7: Windows x86_64 Node 24 Version = v24.12.0)
    for /f "tokens=7 delims= " %%v in ("!MATCHING_LINE!") do set "CURRENT_VERSION=%%v"

    if "!CURRENT_VERSION!"=="!LATEST_VERSION!" (
        exit /b 0
    )

    REM Replace existing line
    set "TMP_FILE=!TEMP!\binaryVersions_temp.txt"
    type nul > "!TMP_FILE!"
    for /f "usebackq delims=" %%a in ("!README!") do (
        set "line=%%a"
        if "!line:~0,32!"=="!PATTERN:~0,32!" (
            echo !PATTERN!!LATEST_VERSION!>> "!TMP_FILE!"
        ) else (
            echo %%a>> "!TMP_FILE!"
        )
    )
    move /y "!TMP_FILE!" "!README!" >nul
    echo Updated Node !MAJOR_VER! Version from !CURRENT_VERSION! to !LATEST_VERSION! in version file
) else (
    REM Add new line at the end
    echo !PATTERN!!LATEST_VERSION!>> "!README!"
    echo Added new line: !PATTERN!!LATEST_VERSION! to version file
)
exit /b 0

:updateReadmeFile
set "README=!CURR_DIR!\README.md"

if not exist "!README!" (
    echo Error: File '!README!' not found.
    exit /b 1
)

set "PATTERN=* Node !MAJOR_VER! Version = "
set "MATCHING_LINE="

for /f "tokens=*" %%a in ('findstr /b /c:"!PATTERN!" "!README!"') do (
    set "MATCHING_LINE=%%a"
)

if not "!MATCHING_LINE!"=="" (
    REM Extract current version from readme file (token 6: * Node 24 Version = v24.12.0)
    for /f "tokens=6 delims= " %%v in ("!MATCHING_LINE!") do set "CURRENT_VERSION=%%v"

    if "!CURRENT_VERSION!"=="!LATEST_VERSION!" (
        echo Node !MAJOR_VER! Version is already !LATEST_VERSION!. No update needed.
        exit /b 0
    )

    REM Replace existing line
    set "TMP_FILE=!TEMP!\README_temp.txt"
    type nul > "!TMP_FILE!"
    for /f "usebackq delims=" %%a in ("!README!") do (
        set "line=%%a"
        if "!line:~0,16!"=="!PATTERN:~0,16!" (
            echo !PATTERN!!LATEST_VERSION!>> "!TMP_FILE!"
        ) else (
            echo %%a>> "!TMP_FILE!"
        )
    )
    move /y "!TMP_FILE!" "!README!" >nul
    echo Updated Node !MAJOR_VER! Version from !CURRENT_VERSION! to !LATEST_VERSION! in Readme.md file
) else (
    REM Add new line at the end
    echo !PATTERN!!LATEST_VERSION!>> "!README!"
    echo Added new line: !PATTERN!!LATEST_VERSION! to Readme.md file
)
exit /b 0

:main
REM Loop through Node versions 16 to 25
for %%v in (16 17 18 19 20 21 22 23 24 25) do (
    set "MAJOR_VER=%%v"
    call :downloadLatestNodejs
    if "!downloaded!"=="true" (
        call :checkLatestVersionInFile
        if "!CREATE_BINARY!"=="true" (
            call :createBinary
        )
    )
)

REM Create Electron binaries too
if exist "%CURR_DIR%\makeelectronbinaries.bat" (
    call "%CURR_DIR%\makeelectronbinaries.bat"
) else (
    echo makeelectronbinaries.bat not found, skipping...
)

git status
echo Done!
endlocal
