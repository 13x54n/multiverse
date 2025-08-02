@echo off
echo Building Fusion+ contracts...

REM Check if forge is available
if exist "forge" (
    echo Found forge executable
    forge build
) else (
    echo Forge not found in current directory
    echo Please install Foundry or ensure forge is in PATH
    echo You can install Foundry with: curl -L https://foundry.paradigm.xyz | bash
)

echo Build complete!
pause 