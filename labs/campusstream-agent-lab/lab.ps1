param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('preflight', 'setup', 'postflight')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Invoke-Docker {
    param([string[]]$DockerArguments)
    & docker @DockerArguments
    if ($LASTEXITCODE -ne 0) { throw "docker $($DockerArguments -join ' ') failed. Check Docker Desktop and docker compose logs --tail 30." }
}

Push-Location $PSScriptRoot
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Install and start Docker Desktop, then reopen PowerShell.'
    }
    Invoke-Docker -DockerArguments @('compose', 'version') | Out-Null
    $engine = Invoke-Docker -DockerArguments @('info', '--format', '{{json .}}') | ConvertFrom-Json
    if ($engine.OSType -ne 'linux') { throw 'Switch Docker Desktop to Linux containers, using the WSL 2 backend.' }
    if ($engine.Architecture -notin @('aarch64', 'arm64', 'x86_64', 'amd64')) {
        throw 'Supported CPU architectures: ARM64 and AMD64.'
    }
    if ([long]$engine.MemTotal -lt 3896508416) {
        throw 'Allocate at least 4 GiB to Docker Desktop/WSL 2; reported memory must cover the 3716 MiB workload.'
    }
    Invoke-Docker -DockerArguments @('compose', 'config', '--quiet')
    Write-Host "PASS preflight: Linux/$($engine.Architecture), Compose, configuration, memory covers 3716 MiB workload."

    if ($Action -eq 'setup') {
        Write-Host 'Starting the lab. First run downloads images and a 1.1 GB model.'
        Invoke-Docker -DockerArguments @('compose', 'up', '--build', '-d')
        Invoke-Docker -DockerArguments @('compose', 'exec', '-T', 'app', 'python', 'verify.py', '--ready')
        Write-Host 'READY: http://localhost:8090'
    }
    if ($Action -eq 'postflight') {
        Invoke-Docker -DockerArguments @('compose', 'exec', '-T', 'app', 'python', 'verify.py')
        New-Item -ItemType Directory -Force -Path results | Out-Null
        Invoke-Docker -DockerArguments @('compose', 'cp', 'app:/tmp/campusstream-e2e.json', 'results/postflight.json')
        Invoke-Docker -DockerArguments @('compose', 'cp', 'app:/tmp/campusstream-dashboard.html', 'results/dashboard.html')
        Write-Host 'PASS postflight. Saved results/postflight.json and results/dashboard.html'
    }
}
catch {
    [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
    exit 1
}
finally { Pop-Location }
