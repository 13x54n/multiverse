Write-Host "Building Fusion+ contracts..." -ForegroundColor Green

# Check if forge is available
if (Test-Path "forge") {
    Write-Host "Found forge executable" -ForegroundColor Yellow
    & .\forge build
} else {
    Write-Host "Forge not found in current directory" -ForegroundColor Red
    Write-Host "Please install Foundry or ensure forge is in PATH" -ForegroundColor Red
    Write-Host "You can install Foundry with: curl -L https://foundry.paradigm.xyz | bash" -ForegroundColor Red
}

Write-Host "Build complete!" -ForegroundColor Green 