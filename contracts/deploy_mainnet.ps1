param (
    [string]$Source = $env:STELLAR_MAINNET_SOURCE,
    [string]$ContractName = "",
    [string]$RpcUrl = "https://mainnet.sorobanrpc.com",
    [string]$NetworkPassphrase = "Public Global Stellar Network ; September 2015"
)

if (-not $Source) {
    $Source = "mainnet-deployer"
}

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
    Push-Location $scriptDir
} else {
    if (Test-Path "contracts") {
        Push-Location contracts
    }
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Soroban Mainnet Deployment Script " -ForegroundColor Cyan
Write-Host " Target RPC: $RpcUrl " -ForegroundColor Cyan
Write-Host " Source Identity/Key: $Source " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Resolve absolute stellar CLI path
$stellarPath = "stellar"
$localStellar = "$env:USERPROFILE\.cargo\bin\stellar.exe"
if (!(Get-Command "stellar" -ErrorAction SilentlyContinue)) {
    if (Test-Path $localStellar) {
        $stellarPath = $localStellar
        Write-Host "Using stellar CLI from user profile path: $stellarPath" -ForegroundColor Cyan
    } else {
        Write-Error "stellar CLI was not found. Please install via: cargo install stellar-cli"
        Pop-Location
        exit 1
    }
}

# 1. Determine list of contracts to deploy
if ($ContractName) {
    $contracts = @($ContractName)
} else {
    $contracts = @("translate_credits", "gift_voucher", "referrals", "marketplace", "subscriptions", "family_org_wallet")
}

$deployedContracts = @{}

foreach ($c in $contracts) {
    $wasmFile = "../assets/contracts/$c.wasm"
    $optimizedFile = "../assets/contracts/$c.optimized.wasm"

    if (!(Test-Path $wasmFile)) {
        Write-Error "Compiled WASM not found for $c at $wasmFile"
        continue
    }

    Write-Host "Optimizing contract: $c..." -ForegroundColor Yellow
    & $stellarPath contract optimize --wasm $wasmFile --wasm-out $optimizedFile 2>&1 | Out-Null

    Write-Host "Deploying contract $c to Mainnet..." -ForegroundColor Yellow
    
    # Deploy contract directly from WASM using specified RPC URL and passphrase
    $deployOutput = & $stellarPath contract deploy `
        --wasm $optimizedFile `
        --source $Source `
        --rpc-url $RpcUrl `
        --network-passphrase $NetworkPassphrase 2>&1

    $contractId = $null
    foreach ($line in $deployOutput) {
        $lineStr = $line.ToString().Trim()
        if ($lineStr -match "^C[A-Z0-9]{55}$") {
            $contractId = $lineStr
            break
        }
    }

    if ($contractId) {
        $deployedContracts[$c] = $contractId
        Write-Host "SUCCESS: Deployed $c -> Contract ID: $contractId" -ForegroundColor Green
    } else {
        Write-Host "Output for $($c):" -ForegroundColor DarkGray
        Write-Host ($deployOutput -join "`n") -ForegroundColor Red
        Write-Host "FAILED to deploy $c" -ForegroundColor Red
    }
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Mainnet Contract Deployment Summary " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

foreach ($key in $deployedContracts.Keys) {
    Write-Host "$key : $($deployedContracts[$key])" -ForegroundColor Green
}

Pop-Location
