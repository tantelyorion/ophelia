@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

:: ============================================================
::                        OPHELIA
::          Folder Structure Generator - v1.0.0
::                   Open Source (MIT)
:: ============================================================
:: Paste any tree-style folder structure and Ophelia will
:: create every file and directory automatically.
::
:: Usage:
::   ophelia.bat                        interactive mode
::   ophelia.bat -i structure.txt       from a file
::   ophelia.bat -i s.txt -o C:\output  custom output folder
::   ophelia.bat --preview              dry-run only
::   ophelia.bat --help
:: ============================================================

:: --- ANSI colors (Windows 10+) ---
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "RESET=%ESC%[0m"
set "BOLD=%ESC%[1m"
set "DIM=%ESC%[2m"
set "GREEN=%ESC%[32m"
set "CYAN=%ESC%[36m"
set "YELLOW=%ESC%[33m"
set "RED=%ESC%[31m"
set "PURPLE=%ESC%[35m"

:: --- Parse arguments ---
set "INPUT_FILE="
set "OUTPUT_DIR="
set "PREVIEW=0"
set "SHOW_HELP=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="-i"        ( set "INPUT_FILE=%~2" & shift & shift & goto parse_args )
if /i "%~1"=="--input"   ( set "INPUT_FILE=%~2" & shift & shift & goto parse_args )
if /i "%~1"=="-o"        ( set "OUTPUT_DIR=%~2" & shift & shift & goto parse_args )
if /i "%~1"=="--output"  ( set "OUTPUT_DIR=%~2" & shift & shift & goto parse_args )
if /i "%~1"=="--preview" ( set "PREVIEW=1"       & shift & goto parse_args )
if /i "%~1"=="--help"    ( set "SHOW_HELP=1"     & shift & goto parse_args )
if /i "%~1"=="-h"        ( set "SHOW_HELP=1"     & shift & goto parse_args )
shift
goto parse_args
:args_done

:: --- Banner ---
echo.
echo %PURPLE%%BOLD%  #######  ######   #     #  #######  #        ###    #     #%RESET%
echo %PURPLE%%BOLD%  #     # #     # #     # #       #        #   # #%RESET%
echo %PURPLE%%BOLD%  #     # #     # ####### #####   #       #   ####%RESET%
echo %PURPLE%%BOLD%  #     # ######  #     # #       #       #   # #%RESET%
echo %PURPLE%%BOLD%  ####### #       #     # ####### ####### ### #    #%RESET%
echo %DIM%  Folder Structure Generator v1.0.0 -- Open Source MIT%RESET%
echo.

:: --- Help ---
if %SHOW_HELP%==1 (
    echo %BOLD%Usage:%RESET%
    echo   ophelia.bat                           Interactive mode
    echo   ophelia.bat -i structure.txt          Read from file
    echo   ophelia.bat -i s.txt -o C:\path       Custom output folder
    echo   ophelia.bat --preview                 Dry-run
    echo.
    echo %BOLD%Supported tree formats:%RESET%
    echo   +--- folder/    ASCII pipes
    echo   ^|-- file.txt    Pipe + dash
    echo   folder/         Plain indentation
    echo   - file.txt      Bullet/dash
    echo   ^(works with output from: tree, AI tools, GitHub, etc.^)
    echo.
    echo %BOLD%Rules:%RESET%
    echo   - Names ending with / are created as directories
    echo   - Names with a dot extension are created as files
    echo   - Comments in parentheses are ignored: uploads/ ^(photos^)
    echo.
    goto :eof
)

:: --- Temp workspace ---
set "TMP_WORKSPACE=%TEMP%\ophelia_%RANDOM%_%RANDOM%"
mkdir "%TMP_WORKSPACE%" >nul 2>&1
set "STRUCT_FILE=%TMP_WORKSPACE%\structure.txt"
set "PY_SCRIPT=%TMP_WORKSPACE%\engine.py"

:: --- Get input ---
if not "%INPUT_FILE%"=="" (
    if not exist "%INPUT_FILE%" (
        echo %RED%[ERROR]%RESET% File not found: %INPUT_FILE%
        goto cleanup
    )
    copy /y "%INPUT_FILE%" "%STRUCT_FILE%" >nul
    echo %DIM%Reading from: %INPUT_FILE%%RESET%
    echo.
) else (
    echo %CYAN%%BOLD%Paste your folder structure below.%RESET%
    echo %DIM%When done, type END on its own line and press Enter.%RESET%
    echo.

    :input_loop
        set "LINE="
        set /p "LINE=  > "
        if /i "!LINE!"=="END" goto input_done
        echo(!LINE!>> "%STRUCT_FILE%"
        goto input_loop
    :input_done
    echo.
)

:: Check not empty
for %%F in ("%STRUCT_FILE%") do if %%~zF==0 (
    echo %YELLOW%Nothing to do — empty input.%RESET%
    goto cleanup
)

:: --- Output dir ---
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=%CD%"

:: --- Write the Python engine to a temp file ---
> "%PY_SCRIPT%" (
    echo import sys, re
    echo from pathlib import Path
    echo.
    echo def strip_prefix(line^):
    echo     # Remove tree-drawing characters from the start of a line
    echo     line = re.sub(r'^[\s\u2502\u2503\|]*', '', line^)
    echo     line = re.sub(r'^[\u251C\u2514\u2560\u255A\|+`][\u2500\-]+ *', '', line^)
    echo     line = re.sub(r'^[\-\*\+] +', '', line^)
    echo     return line
    echo.
    echo def leading_len(line^):
    echo     m = re.match(r'^[\s\u2502\u2503\|]*', line^)
    echo     return len(m.group(0^)^) if m else 0
    echo.
    echo def parse(raw^):
    echo     lines = [l.rstrip(^) for l in raw.splitlines(^) if l.strip(^)]
    echo     lines = [l for l in lines if not re.match(r'^[\s\u2500\u2502\u251C\u2514\|=\-]+$', l^)]
    echo     if not lines: return []
    echo     depths = [leading_len(l^) for l in lines]
    echo     deltas = sorted({b-a for a,b in zip(depths,depths[1:]^) if b^>a}^)
    echo     unit = deltas[0] if deltas else 4
    echo     entries = []
    echo     for line in lines:
    echo         depth = leading_len(line^) // max(unit,1^)
    echo         name = strip_prefix(line^).strip(^)
    echo         name = re.sub(r'\s*\(.*?\^)\s*$', '', name^).strip(^)
    echo         if not name or re.match(r'^[\-=\u2500]+$', name^): continue
    echo         is_dir = name.endswith('/'^)
    echo         if is_dir: name = name[:-1]
    echo         entries.append((depth, name, is_dir^)^)
    echo     return entries
    echo.
    echo def build(entries^):
    echo     stack, result = [], []
    echo     for depth, name, is_dir in entries:
    echo         stack = stack[:depth]
    echo         p = Path(*stack, name^) if stack else Path(name^)
    echo         result.append((p, is_dir^)^)
    echo         if is_dir: stack.append(name^)
    echo     return result
    echo.
    echo struct_path = sys.argv[1]
    echo output_dir  = sys.argv[2]
    echo preview     = (sys.argv[3] == '1'^)
    echo.
    echo raw = Path(struct_path^).read_text(encoding='utf-8', errors='replace'^)
    echo entries = parse(raw^)
    echo if not entries:
    echo     print('ERROR: Could not parse any entries from the input.'^)
    echo     sys.exit(1^)
    echo paths = build(entries^)
    echo root = Path(output_dir^)
    echo.
    echo print(f'\nPreview  [root: {root}]'^)
    echo print('-' * 50^)
    echo for rel, is_dir in paths:
    echo     pad = '  ' * len(rel.parts^)
    echo     tag = '[DIR] ' if is_dir else '[FILE]'
    echo     suffix = '/' if is_dir else ''
    echo     print(f'{pad}{tag} {rel.name}{suffix}'^)
    echo.
    echo nd = sum(1 for _,d in paths if d^)
    echo nf = len(paths^) - nd
    echo print(f'\nTotal: {nd} director{"ies" if nd!=1 else "y"}, {nf} file{"s" if nf!=1 else ""}'^)
    echo.
    echo if not preview:
    echo     root.mkdir(parents=True, exist_ok=True^)
    echo     ok_d, ok_f, errs = 0, 0, []
    echo     for rel, is_dir in paths:
    echo         full = root / rel
    echo         try:
    echo             if is_dir:
    echo                 full.mkdir(parents=True, exist_ok=True^); ok_d += 1
    echo                 print(f'  [OK-DIR]  {rel}/'^)
    echo             else:
    echo                 full.parent.mkdir(parents=True, exist_ok=True^)
    echo                 if not full.exists(^): full.touch(^)
    echo                 ok_f += 1
    echo                 print(f'  [OK-FILE] {rel}'^)
    echo         except OSError as e:
    echo             errs.append(str(e^)^)
    echo             print(f'  [ERR]     {rel}: {e}'^)
    echo     print('^)
    echo     print(f'Done!  {ok_d} dir{"s" if ok_d!=1 else ""} + {ok_f} file{"s" if ok_f!=1 else ""} created in: {root}'^)
    echo     if errs:
    echo         print(f'Errors ({len(errs^)}^):'^)
    echo         for e in errs: print(f'  x {e}'^)
)

:: --- Check Python ---
python --version >nul 2>&1
if errorlevel 1 (
    python3 --version >nul 2>&1
    if errorlevel 1 (
        echo %RED%[ERROR]%RESET% Python not found. Install from https://python.org
        goto cleanup
    )
    set "PY=python3"
) else (
    set "PY=python"
)

:: --- Preview pass ---
%PY% "%PY_SCRIPT%" "%STRUCT_FILE%" "%OUTPUT_DIR%" "1"
if errorlevel 1 goto cleanup

echo.
if %PREVIEW%==1 (
    echo %YELLOW%[DRY-RUN] No files or directories were created.%RESET%
    goto cleanup
)

:: --- Confirm ---
echo %BOLD%Output: %OUTPUT_DIR%%RESET%
echo.
set /p "CONF=%BOLD%Create structure? [Y/n]%RESET%  "
if /i "!CONF!"=="n"   goto aborted
if /i "!CONF!"=="no"  goto aborted

echo.
%PY% "%PY_SCRIPT%" "%STRUCT_FILE%" "%OUTPUT_DIR%" "0"
if errorlevel 1 goto cleanup

echo.
echo %GREEN%%BOLD%All done!%RESET% Structure created in: %CYAN%%OUTPUT_DIR%%RESET%
goto cleanup

:aborted
echo.
echo %YELLOW%Aborted. Nothing was created.%RESET%

:cleanup
if exist "%TMP_WORKSPACE%" rmdir /s /q "%TMP_WORKSPACE%" >nul 2>&1
echo.
endlocal
