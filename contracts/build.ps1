# Build script for Soroban Smart Contracts
# Compiles all workspace members into optimized WASM targets

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
    Push-Location $scriptDir
} else {
    if (Test-Path "contracts") {
        Push-Location contracts
    }
}

Write-Host "Compiling Soroban smart contracts to WebAssembly..." -ForegroundColor Green

# Resolve absolute cargo path
$cargoPath = "cargo"
$localCargo = "$env:USERPROFILE\.cargo\bin\cargo.exe"
if (!(Get-Command "cargo" -ErrorAction SilentlyContinue)) {
    if (Test-Path $localCargo) {
        $cargoPath = $localCargo
        Write-Host "Using cargo from user profile path: $cargoPath" -ForegroundColor Cyan
    } else {
        Write-Error "cargo was not found. Please install Rust from rustup.rs"
        exit 1
    }
}

Write-Host "Building translate_credits contract first..." -ForegroundColor Green
& $cargoPath build --target wasm32-unknown-unknown --release -p translate_credits

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to compile translate_credits contract!"
    Pop-Location
    exit $LASTEXITCODE
}

Write-Host "Building remaining contracts..." -ForegroundColor Green
& $cargoPath build --target wasm32-unknown-unknown --release

if ($LASTEXITCODE -ne 0) {
    Write-Error "WASM compilation failed! Ensure you have Rust and the wasm32-unknown-unknown target installed."
    Pop-Location
    exit $LASTEXITCODE
}

Write-Host "Optimizing contract binaries using soroban contract optimize (optional)..." -ForegroundColor Cyan
# Ensure the contracts outputs directory exists
New-Item -ItemType Directory -Force -Path "../assets/contracts" | Out-Null

$contracts = @("translate_credits", "gift_voucher", "referrals", "marketplace", "subscriptions", "family_org_wallet")

foreach ($c in $contracts) {
    $wasmFile = "./target/wasm32-unknown-unknown/release/$c.wasm"
    if (Test-Path $wasmFile) {
        Copy-Item -Path $wasmFile -Destination "../assets/contracts/$c.wasm" -Force
        Write-Host "Copied $c.wasm to assets/contracts/" -ForegroundColor Green
    } else {
        Write-Warning "Could not find compiled binary: $wasmFile"
    }
}

Write-Host "Soroban Build Complete." -ForegroundColor Green
Pop-Location
