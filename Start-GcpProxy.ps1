param([switch]$NoSystemProxy)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskBinary = Join-Path $taskRoot 'client\sing-box-1.14.3-windows-amd64\sing-box.exe'
$taskConfig = Join-Path $taskRoot 'sing-box-windows.json'
$taskStatePath = Join-Path $taskRoot 'previous-system-proxy.json'
$taskRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Update-ProxyNotification {
    if (-not ('GcpProxy.WinInet' -as [type])) {
        Add-Type 'namespace GcpProxy { public static class WinInet { [System.Runtime.InteropServices.DllImport("wininet.dll")] public static extern bool InternetSetOption(System.IntPtr h, int option, System.IntPtr buffer, int length); } }'
    }
    [void][GcpProxy.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
    [void][GcpProxy.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
}

if (Get-NetTCPConnection -State Listen -LocalPort 17899 -ErrorAction SilentlyContinue) {
    throw 'Port 17899 is already in use. Close the previous GCP client before starting again.'
}
& $taskBinary check -D $taskRoot -c $taskConfig
if ($LASTEXITCODE -ne 0) { throw 'Client configuration validation failed.' }

if (-not $NoSystemProxy) {
    if (Test-Path -LiteralPath $taskStatePath) {
        throw 'A previous proxy backup exists. Run Restore-Proxy.ps1 first.'
    }
    $taskCurrent = Get-ItemProperty -LiteralPath $taskRegistryPath
    $taskBackup = @{}
    foreach ($taskName in @('ProxyEnable','ProxyServer','ProxyOverride','AutoConfigURL')) {
        $taskProperty = $taskCurrent.PSObject.Properties[$taskName]
        $taskBackup[$taskName] = @{ Present = ($null -ne $taskProperty); Value = if ($taskProperty) { $taskProperty.Value } else { $null } }
    }
    $taskBackup | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskStatePath -Encoding UTF8
}

try {
    if (-not $NoSystemProxy) {
        Set-ItemProperty -LiteralPath $taskRegistryPath -Name ProxyServer -Value '127.0.0.1:17899'
        Set-ItemProperty -LiteralPath $taskRegistryPath -Name ProxyEnable -Type DWord -Value 1
        Remove-ItemProperty -LiteralPath $taskRegistryPath -Name AutoConfigURL -ErrorAction SilentlyContinue
        Update-ProxyNotification
    }
    Write-Host 'GCP proxy: 127.0.0.1:17899'
    Write-Host 'Keep this window open. Press Ctrl+C to stop and restore the previous proxy.'
    Write-Host 'If this window is closed abruptly, run Restore-Proxy.ps1.'
    & $taskBinary run -D $taskRoot -c $taskConfig
    if ($LASTEXITCODE -ne 0) { throw "Client exited with code $LASTEXITCODE" }
}
finally {
    if (-not $NoSystemProxy) { & (Join-Path $taskRoot 'Restore-Proxy.ps1') }
}
