@echo off
setlocal
node "%~dp0uia.mjs" %*
exit /b %ERRORLEVEL%
