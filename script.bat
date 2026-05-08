@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul

:: ================================================================
::  LAB_SETUP.BAT
::  Автоматичне встановлення ПЗ для комп'ютерної аудиторії
::
::  Встановлює:
::    - Git
::    - Visual Studio Code
::    - Unity Hub
::    - Blender
::    - Unity Editor 6000.3.12f1 (Android, WebGL, iOS, SDK/NDK, JDK)
:: ================================================================

:: ----------------------------------------------------------------
::  НАЛАШТУВАННЯ — підправте назви файлів та шляхи під свої дані
:: ----------------------------------------------------------------

:: Мережева папка з інсталяторами
set PKG_DIR=\\SERVER\labsetup\choco

:: Назви файлів інсталяторів (підправте під реальні назви)
set GIT_INSTALLER=Git-x64.exe
set VSCODE_INSTALLER=VSCodeSetup-x64.exe
set UNITYHUB_INSTALLER=UnityHubSetup.exe
set BLENDER_INSTALLER=blender-windows-x64.msi

:: Мережева папка з Unity Editor (скопійована з референсного ПК)
set UNITY_SHARE=\\SERVER\labsetup\unity

:: Версія Unity Editor
set UNITY_VERSION=6000.3.12f1

:: Куди встановити Unity Editor локально
set UNITY_LOCAL_PATH=C:\Program Files\Unity\Hub\Editor

:: Шлях до Unity Hub після встановлення
set UNITY_HUB_EXE=C:\Program Files\Unity Hub\Unity Hub.exe

:: ================================================================
::  ПЕРЕВІРКА ПРАВ АДМІНІСТРАТОРА
:: ================================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [ПОМИЛКА] Скрипт потребує прав адміністратора.
    echo  Закрийте це вікно, натисніть правою кнопкою на .bat файл
    echo  і оберіть "Запуск від імені адміністратора".
    echo.
    pause
    exit /b 1
)

echo.
echo  ================================================================
echo   LAB SETUP — початок встановлення
echo   %DATE% %TIME%
echo  ================================================================
echo.

:: Перевірити доступність мережевої папки з інсталяторами
if not exist "%PKG_DIR%" (
    echo  [ПОМИЛКА] Мережева папка з інсталяторами недоступна:
    echo           %PKG_DIR%
    echo  Перевірте мережеве з'єднання та повторіть спробу.
    pause
    exit /b 1
)

set INSTALL_ERRORS=0

:: ================================================================
::  КРОК 1/5 — GIT
:: ================================================================
echo  [1/5] Git...
echo  ----------------------------------------------------------------

if not exist "%PKG_DIR%\%GIT_INSTALLER%" (
    echo  [ПОМИЛКА] Файл не знайдено: %PKG_DIR%\%GIT_INSTALLER%
    set /a INSTALL_ERRORS+=1
) else (
    echo  [..] Встановлення / оновлення Git...
    :: /wait — чекаємо повного завершення інсталятора перед наступним кроком
    start "" /wait "%PKG_DIR%\%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES
    if !errorlevel! neq 0 (
        echo  [ПОМИЛКА] Git — помилка встановлення (код: !errorlevel!)
        set /a INSTALL_ERRORS+=1
    ) else (
        echo  [OK] Git — встановлено успішно.
    )
)
echo.

:: ================================================================
::  КРОК 2/5 — VISUAL STUDIO CODE
:: ================================================================
echo  [2/5] Visual Studio Code...
echo  ----------------------------------------------------------------

if not exist "%PKG_DIR%\%VSCODE_INSTALLER%" (
    echo  [ПОМИЛКА] Файл не знайдено: %PKG_DIR%\%VSCODE_INSTALLER%
    set /a INSTALL_ERRORS+=1
) else (
    echo  [..] Встановлення / оновлення VS Code...
    setlocal DisableDelayedExpansion
    start "" /wait "%PKG_DIR%\%VSCODE_INSTALLER%" /VERYSILENT /NORESTART /SUPPRESSMSGBOXES ^
        /MERGETASKS="!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath"
    set VSCODE_ERR=%errorlevel%
    setlocal EnableDelayedExpansion
    if !VSCODE_ERR! neq 0 (
        echo  [ПОМИЛКА] VS Code — помилка встановлення (код: !VSCODE_ERR!)
        set /a INSTALL_ERRORS+=1
    ) else (
        echo  [OK] Visual Studio Code — встановлено успішно.
    )
)
echo.

:: ================================================================
::  КРОК 3/5 — UNITY HUB
:: ================================================================
echo  [3/5] Unity Hub...
echo  ----------------------------------------------------------------

if not exist "%PKG_DIR%\%UNITYHUB_INSTALLER%" (
    echo  [ПОМИЛКА] Файл не знайдено: %PKG_DIR%\%UNITYHUB_INSTALLER%
    set /a INSTALL_ERRORS+=1
) else (
    echo  [..] Встановлення / оновлення Unity Hub...
    :: Unity Hub (NSIS) — /S для тихого встановлення
    :: /wait критично важливий: NSIS може повернути управління раніше завершення
    start "" /wait "%PKG_DIR%\%UNITYHUB_INSTALLER%" /S
    if !errorlevel! neq 0 (
        echo  [ПОМИЛКА] Unity Hub — помилка встановлення (код: !errorlevel!)
        set /a INSTALL_ERRORS+=1
    ) else (
        echo  [OK] Unity Hub — встановлено успішно.
    )
)
echo.

:: ================================================================
::  КРОК 4/5 — BLENDER
:: ================================================================
echo  [4/5] Blender...
echo  ----------------------------------------------------------------

if not exist "%PKG_DIR%\%BLENDER_INSTALLER%" (
    echo  [ПОМИЛКА] Файл не знайдено: %PKG_DIR%\%BLENDER_INSTALLER%
    set /a INSTALL_ERRORS+=1
) else (
    echo  [..] Встановлення / оновлення Blender...
    set BLENDER_EXT=%BLENDER_INSTALLER:~-3%

    if /i "!BLENDER_EXT!"=="msi" (
        :: Blender 4.x — MSI; msiexec за замовчуванням синхронний, /wait не потрібен
        start "" /wait msiexec /i "%PKG_DIR%\%BLENDER_INSTALLER%" /quiet /norestart
    ) else (
        :: Blender старіших версій — NSIS .exe
        start "" /wait "%PKG_DIR%\%BLENDER_INSTALLER%" /S
    )

    if !errorlevel! neq 0 (
        echo  [ПОМИЛКА] Blender — помилка встановлення (код: !errorlevel!)
        set /a INSTALL_ERRORS+=1
    ) else (
        echo  [OK] Blender — встановлено успішно.
    )
)
echo.

:: ================================================================
::  КРОК 5А/5 — КОПІЮВАННЯ UNITY EDITOR З МЕРЕЖЕВОЇ ПАПКИ
:: ================================================================
echo  [5/5] Unity Editor %UNITY_VERSION%...
echo  ----------------------------------------------------------------

if exist "%UNITY_LOCAL_PATH%\%UNITY_VERSION%\Editor\Unity.exe" (
    echo  [OK] Unity Editor вже присутній локально. Копіювання пропущено.
    goto :check_sdk
)

if not exist "%UNITY_SHARE%\%UNITY_VERSION%" (
    echo  [ПОМИЛКА] Unity Editor не знайдено на сервері:
    echo           %UNITY_SHARE%\%UNITY_VERSION%
    echo.
    echo  Переконайтесь що:
    echo    1. Ви підключені до мережі
    echo    2. Папку скопійовано на сервер з референсного ПК
    set /a INSTALL_ERRORS+=1
    goto :register_unity
)

if not exist "%UNITY_LOCAL_PATH%\%UNITY_VERSION%" (
    mkdir "%UNITY_LOCAL_PATH%\%UNITY_VERSION%" 2>nul
)

echo  [..] Копіювання Unity Editor з мережі (robocopy, 8 потоків)...
echo       Джерело : %UNITY_SHARE%\%UNITY_VERSION%
echo       Ціль    : %UNITY_LOCAL_PATH%\%UNITY_VERSION%
echo       Розмір  : ~15-20 ГБ, це займе 10-30 хвилин...
echo.

:: Ключі robocopy:
::   /E      — копіювати всі підпапки включно з порожніми
::   /COPYALL — зберегти всі атрибути файлів
::   /MT:8   — 8 паралельних потоків (значно швидше ніж xcopy)
::   /R:3    — 3 повторні спроби при помилці мережі
::   /W:10   — 10 секунд очікування між спробами
::   /NP     — не показувати відсоток (засмічує лог)
::   /LOG    — зберегти лог копіювання для діагностики
robocopy "%UNITY_SHARE%\%UNITY_VERSION%" "%UNITY_LOCAL_PATH%\%UNITY_VERSION%" ^
    /E /COPY:DAT /MT:8 /R:3 /W:10 /NP ^
    /LOG:"%TEMP%\lab_setup_unity_copy.log"

:: Увага: robocopy повертає коди 0-7 як успіх (бітова маска подій)
:: Код 8 і вище — реальна помилка копіювання
if !errorlevel! geq 8 (
    echo  [ПОМИЛКА] Помилка під час копіювання Unity Editor (код: %errorlevel%)
    echo  Лог збережено: %TEMP%\lab_setup_unity_copy.log
    echo  Перевірте вільне місце на диску та мережеве з'єднання.
    set /a INSTALL_ERRORS+=1
    goto :register_unity
)

echo  [OK] Unity Editor скопійовано успішно.
echo       Лог збережено: %TEMP%\lab_setup_unity_copy.log

:: ================================================================
::  ПЕРЕВІРКА SDK / NDK / JDK ПІСЛЯ КОПІЮВАННЯ
:: ================================================================
:check_sdk
echo.
echo  [..] Перевірка Android SDK / NDK / OpenJDK...

set ANDROID_PLAYER=%UNITY_LOCAL_PATH%\%UNITY_VERSION%\Editor\Data\PlaybackEngines\AndroidPlayer
set SDK_WARNINGS=0

if not exist "%ANDROID_PLAYER%\SDK" (
    echo  [!!] УВАГА: Android SDK не знайдено у скопійованій папці.
    echo       Очікувалось: %ANDROID_PLAYER%\SDK
    set /a SDK_WARNINGS+=1
)
if not exist "%ANDROID_PLAYER%\NDK" (
    echo  [!!] УВАГА: Android NDK не знайдено у скопійованій папці.
    echo       Очікувалось: %ANDROID_PLAYER%\NDK
    set /a SDK_WARNINGS+=1
)
if not exist "%ANDROID_PLAYER%\OpenJDK" (
    echo  [!!] УВАГА: OpenJDK не знайдено у скопійованій папці.
    echo       Очікувалось: %ANDROID_PLAYER%\OpenJDK
    set /a SDK_WARNINGS+=1
)

if !SDK_WARNINGS! gtr 0 (
    echo.
    echo  Можливі причини:
    echo    - На референсному ПК SDK/NDK/JDK були встановлені у нестандартне місце
    echo    - Модулі Android не були встановлені перед копіюванням папки
    echo.
    echo  Що робити:
    echo    1. На референсному ПК перевірте наявність цих папок у Editor
    echo    2. Якщо їх немає — встановіть модулі через Unity Hub CLI:
    echo       "C:\Program Files\Unity Hub\Unity Hub.exe" -- --headless install-modules
    echo         --version %UNITY_VERSION% --module android android-sdk-ndk-tools
    echo         android-open-jdk --childModules
    echo    3. Потім повторно скопіюйте папку на сервер і запустіть скрипт знову
    set /a INSTALL_ERRORS+=!SDK_WARNINGS!
) else (
    echo  [OK] Android SDK, NDK та OpenJDK знайдено — Android-білди працюватимуть.
)

:: ================================================================
::  КРОК 5Б/5 — РЕЄСТРАЦІЯ UNITY EDITOR В UNITY HUB
:: ================================================================
:register_unity
echo.
echo  [..] Реєстрація Unity Editor в Unity Hub...

echo  [..] Очікування ініціалізації Unity Hub...
timeout /t 8 /nobreak >nul

if not exist "%UNITY_HUB_EXE%" (
    echo  [!!] Unity Hub не знайдено за шляхом:
    echo       %UNITY_HUB_EXE%
    echo  Зареєструйте Editor вручну після перезавантаження:
    echo    Unity Hub → Installs → Locate → вкажіть:
    echo    %UNITY_LOCAL_PATH%\%UNITY_VERSION%\Editor\Unity.exe
    set /a INSTALL_ERRORS+=1
    goto :summary
)

if not exist "%UNITY_LOCAL_PATH%\%UNITY_VERSION%\Editor\Unity.exe" (
    echo  [!!] Unity.exe не знайдено локально — реєстрацію пропущено.
    goto :summary
)

"%UNITY_HUB_EXE%" -- --headless install-path --set "%UNITY_LOCAL_PATH%" >nul 2>&1
"%UNITY_HUB_EXE%" -- --headless editors -a "%UNITY_LOCAL_PATH%\%UNITY_VERSION%\Editor\Unity.exe" >nul 2>&1

if !errorlevel! neq 0 (
    echo  [!!] Не вдалося автоматично зареєструвати Unity Editor.
    echo  Зареєструйте вручну:
    echo    Unity Hub → Installs → Locate → вкажіть:
    echo    %UNITY_LOCAL_PATH%\%UNITY_VERSION%\Editor\Unity.exe
) else (
    echo  [OK] Unity Editor %UNITY_VERSION% зареєстровано в Unity Hub.
)

:: ================================================================
::  ПІДСУМОК
:: ================================================================
:summary
echo.
echo  ================================================================
echo   ПІДСУМОК ВСТАНОВЛЕННЯ — %DATE% %TIME%
echo  ----------------------------------------------------------------

if %INSTALL_ERRORS% equ 0 (
    echo.
    echo   Усі компоненти встановлено успішно:
    echo.
    echo     [+] Git
    echo     [+] Visual Studio Code
    echo     [+] Unity Hub
    echo     [+] Blender
    echo     [+] Unity Editor %UNITY_VERSION%
    echo         Модулі: Android, WebGL, iOS, SDK/NDK, OpenJDK
    echo.
    echo   Рекомендується перезавантажити комп'ютер.
) else (
    echo.
    echo   Встановлення завершено з %INSTALL_ERRORS% помилк(ами) або попередженнями.
    echo   Перегляньте повідомлення вище для деталей.
    echo.
    echo   Після виправлення проблем скрипт можна запустити повторно —
    echo   вже встановлені компоненти будуть автоматично пропущені.
)

echo.
echo  ================================================================
echo.
pause
endlocal