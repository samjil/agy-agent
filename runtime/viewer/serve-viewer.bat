@echo off
setlocal
chcp 65001 >nul
title samjil Unified Dashboard
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve-viewer.ps1" %*
