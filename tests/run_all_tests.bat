@echo off
setlocal
set "DIR=%~dp0"
set FAIL=0

echo ################################################
echo # GDScript headless tests
echo ################################################
call "%DIR%run_gdscript_tests.bat"
if errorlevel 1 set FAIL=1

echo.
echo ################################################
echo # C++ tests
echo ################################################
call "%DIR%run_cpp_tests.bat"
if errorlevel 1 set FAIL=1

echo.
echo ################################################
echo # Packaging tests
echo ################################################
call "%DIR%run_packaging_tests.bat"
if errorlevel 1 set FAIL=1

echo.
echo ################################################
if %FAIL%==0 (
	echo ALL SUITES PASSED
) else (
	echo ONE OR MORE SUITES FAILED
)
echo ################################################
exit /b %FAIL%
