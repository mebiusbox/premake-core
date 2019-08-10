@echo off
call vscmd.bat
.\bin\release\premake5 embed
devenv .\build\bootstrap\premake5.sln /Build Release
pause