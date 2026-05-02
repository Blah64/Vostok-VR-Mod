@echo off
setlocal

set "ROOT=%~dp0.."
set "CMAKE=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

if not exist "%CMAKE%" (
	echo ERROR: cmake.exe not found at "%CMAKE%"
	echo Edit tests\run_cpp_tests.bat to point at your cmake install.
	exit /b 1
)

echo == Configuring with -DRTV_VR_BUILD_TESTS=ON ==
"%CMAKE%" -S "%ROOT%" -B "%ROOT%\build" -DRTV_VR_BUILD_TESTS=ON
if errorlevel 1 exit /b 1

echo.
echo == Building test targets ==
"%CMAKE%" --build "%ROOT%\build" --config Release --target test_command_line
if errorlevel 1 exit /b 1

echo.
echo == Running tests via CTest ==
pushd "%ROOT%\build"
"%CMAKE%" --build . --config Release --target RUN_TESTS
set TEST_EXIT=%ERRORLEVEL%
popd

rem Always also run the binary directly so the per-test output is visible
rem (RUN_TESTS only prints pass/fail summary by default).
echo.
echo == Test binary output ==
"%ROOT%\build\tests\Release\test_command_line.exe"
exit /b %ERRORLEVEL%
