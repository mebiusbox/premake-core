@echo off
set VSPROMPT_2015="%VS140COMNTOOLS%vsvars32.bat"
set VSPROMPT_2017="C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvars64.bat"
set VSPROMPT_2017C="C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvars64.bat"
set VSPROMPT_2019="C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvars64.bat"
set VSPROMPT_2019C="C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
set VSPROMPT=
if exist %VSPROMPT_2015% ( 
    echo found %VSPROMPT_2015%
    set VSPROMPT=%VSPROMPT_2015% 
)
if exist %VSPROMPT_2017C% (
    echo found %VSPROMPT_2017C%
    set VSPROMPT=%VSPROMPT_2017C%
)
if exist %VSPROMPT_2017% (
    echo found %VSPROMPT_2017%
    set VSPROMPT=%VSPROMPT_2017%
)
if exist %VSPROMPT_2019C% (
    echo found %VSPROMPT_2019C%
    set VSPROMPT=%VSPROMPT_2019C%
)
if exist %VSPROMPT_2019% (
    echo found %VSPROMPT_2019%
    set VSPROMPT=%VSPROMPT_2019%
)
call %VSPROMPT%
