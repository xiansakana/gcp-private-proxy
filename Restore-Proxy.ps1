$ErrorActionPreference = 'Stop'
$taskStatePath = Join-Path $PSScriptRoot 'previous-system-proxy.json'
$taskRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if (-not (Test-Path -LiteralPath $taskStatePath)) {
    Write-Host 'No saved proxy settings to restore. Current settings were left unchanged.'
    return
}
$taskSaved = Get-Content -LiteralPath $taskStatePath -Raw | ConvertFrom-Json
foreach ($taskName in @('ProxyEnable','ProxyServer','ProxyOverride','AutoConfigURL')) {
    $taskEntry = $taskSaved.$taskName
    if ($taskEntry.Present) {
        if ($taskName -eq 'ProxyEnable') {
            Set-ItemProperty -LiteralPath $taskRegistryPath -Name $taskName -Type DWord -Value ([int]$taskEntry.Value)
        } else {
            Set-ItemProperty -LiteralPath $taskRegistryPath -Name $taskName -Value ([string]$taskEntry.Value)
        }
    } else {
        Remove-ItemProperty -LiteralPath $taskRegistryPath -Name $taskName -ErrorAction SilentlyContinue
    }
}
if (-not ('GcpProxy.WinInet' -as [type])) {
    Add-Type 'namespace GcpProxy { public static class WinInet { [System.Runtime.InteropServices.DllImport("wininet.dll")] public static extern bool InternetSetOption(System.IntPtr h, int option, System.IntPtr buffer, int length); } }'
}
[void][GcpProxy.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
[void][GcpProxy.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
Remove-Item -LiteralPath $taskStatePath
Write-Host 'Previous system proxy settings restored.'
