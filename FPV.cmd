@echo off
title FPV PREP
color 0A
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fpv.ps1" %*
