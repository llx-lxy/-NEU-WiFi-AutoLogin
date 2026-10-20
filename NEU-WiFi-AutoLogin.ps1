param(
    [ValidateSet('Install','Once','Connect','Check','Remove')]
    [string]$Action = 'Check'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'NEU WiFi Auto Login'
$appDir = Join-Path $env:LOCALAPPDATA 'NEU-WiFi-AutoLogin'
$configPath = Join-Path $appDir 'config.json'
$logPath = Join-Path $appDir 'autologin.log'
$pausePath = Join-Path $appDir 'needs-reconfiguration.txt'
$self = $MyInvocation.MyCommand.Path

function Write-Log([string]$message) {
    if (-not (Test-Path -LiteralPath $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null }
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1048576) {
        Move-Item -LiteralPath $logPath -Destination (Join-Path $appDir 'autologin.previous.log') -Force
    }
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    if ($Action -ne 'Once') { Write-Host $line }
}

function Get-ConnectedSSID {
    $lines = @(netsh wlan show interfaces 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^\s*SSID\s*:\s*(.*?)\s*$') { return $Matches[1] }
    }
    return $null
}

function Connect-CampusWifi([bool]$allowSwitch) {
    $current = Get-ConnectedSSID
    if ($current -in @('NEU-2.4G','NEU')) { return $current }
    if ($current -and $current -ne 'NEU-Mobile' -and -not $allowSwitch) {
        Write-Log ('当前使用其他 Wi-Fi（{0}），自动任务不切换网络。' -f $current)
        return $null
    }
    foreach ($target in @('NEU-2.4G','NEU')) {
        Write-Log ('正在连接 Wi-Fi：{0}' -f $target)
        & netsh wlan connect "name=$target" "ssid=$target" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            Start-Sleep -Seconds 2
            $current = Get-ConnectedSSID
            if ($current -eq $target) {
                Write-Log ('已连接 Wi-Fi：{0}，开始检查校园网认证。' -f $target)
                return $target
            }
        }
    }
    Write-Log '未能连接 NEU-2.4G 或 NEU。请确认处于校园 Wi-Fi 覆盖范围，且已保存对应网络配置。'
    return $null
}

function Get-Python312 {
    $candidate = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $candidate) { throw '未找到 Python 3.12。' }
    $python = $candidate.Source
    $version = & $python --version 2>&1
    if ($version -notmatch '^Python 3\.12\.') { throw '本程序包需要 64 位 Python 3.12。' }
    return $python
}

function Get-PlainPassword([string]$encrypted) {
    $secure = ConvertTo-SecureString $encrypted
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Invoke-Once([bool]$allowSwitch) {
    if (-not (Test-Path -LiteralPath $configPath)) { throw '请先运行 Install.cmd。' }
    $ssid = Get-ConnectedSSID
    if ($ssid -notin @('NEU','NEU-2.4G')) { $ssid = Connect-CampusWifi $allowSwitch }
    if ($ssid -notin @('NEU','NEU-2.4G')) { return }
    if (Test-Path -LiteralPath $pausePath) { Write-Log '认证已暂停：请检查账号、密码或费用，然后重新运行 Install.cmd。'; return }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $password = Get-PlainPassword $config.ProtectedPassword
    $payload = @{ username = [string]$config.Username; password = $password } | ConvertTo-Json -Compress
    $password = $null
    $python = [string]$config.PythonPath
    $worker = Join-Path $appDir 'login_worker.py'
    $oldOutputEncoding = $OutputEncoding
    $oldConsoleEncoding = [Console]::OutputEncoding
    $oldPythonEncoding = $env:PYTHONIOENCODING
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $env:PYTHONIOENCODING = 'utf-8'
        $result = @($payload | & $python $worker 2>&1)
        $exitCode = $LASTEXITCODE
        if ($result.Count -eq 0) { Write-Log ('{0}：程序没有返回结果（代码 {1}）。' -f $ssid, $exitCode) }
        else { Write-Log ('{0}：{1}' -f $ssid, (($result | Select-Object -Last 1) -replace '[\r\n]', '')) }
        if ($exitCode -eq 2) {
            Set-Content -LiteralPath $pausePath -Value 'Authentication rejected; rerun Install.cmd.' -Encoding ASCII
            Write-Log '认证被拒绝，已暂停自动重试，避免反复提交错误密码。'
        }
    } catch {
        Write-Log ('{0}：启动认证程序失败：{1}' -f $ssid, $_.Exception.GetType().Name)
    } finally {
        $OutputEncoding = $oldOutputEncoding
        [Console]::OutputEncoding = $oldConsoleEncoding
        $env:PYTHONIOENCODING = $oldPythonEncoding
    }
}

switch ($Action) {
    'Install' {
        $python = Get-Python312
        $username = Read-Host '请输入统一身份认证账号（学号或工号）'
        if ([string]::IsNullOrWhiteSpace($username)) { throw '账号不能为空。' }
        $securePassword = Read-Host '请输入统一身份认证密码（输入不会显示）' -AsSecureString
        $encrypted = ConvertFrom-SecureString $securePassword
        $sourceDir = Split-Path -Parent $self
        $wheels = Join-Path $sourceDir 'wheels'
        if (-not (Test-Path -LiteralPath $wheels)) { throw '程序包缺少 wheels 目录。' }
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null
        $tempDir = Join-Path $appDir 'tmp'
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $oldTemp = $env:TEMP; $oldTmp = $env:TMP
        try {
            $env:TEMP = $tempDir; $env:TMP = $tempDir
            & $python -m pip install --disable-pip-version-check --no-index --find-links $wheels --target (Join-Path $appDir 'lib') --upgrade NEU-ipgw-manager==3.3
            if ($LASTEXITCODE -ne 0) { throw '安装本地依赖失败。' }
        } finally { $env:TEMP = $oldTemp; $env:TMP = $oldTmp }
        Copy-Item -LiteralPath (Join-Path $sourceDir 'login_worker.py') -Destination (Join-Path $appDir 'login_worker.py') -Force
        $installedScript = Join-Path $appDir 'NEU-WiFi-AutoLogin.ps1'
        if ($self -ne $installedScript) { Copy-Item -LiteralPath $self -Destination $installedScript -Force }
        @{ Username = $username; ProtectedPassword = $encrypted; PythonPath = $python } |
            ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
        $encrypted = $null
        if (Test-Path -LiteralPath $pausePath) { Remove-Item -LiteralPath $pausePath -Force }
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action Once' -f (Join-Path $appDir 'NEU-WiFi-AutoLogin.ps1')
        $taskAction = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument $arguments
        $onLogon = New-ScheduledTaskTrigger -AtLogOn -User $user
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $onLogon -Settings $settings -Principal $principal -Force | Out-Null
        foreach ($campusProfile in @('NEU-2.4G','NEU')) {
            & netsh wlan set profileparameter "name=$campusProfile" connectionmode=auto 2>$null | Out-Null
        }
        Write-Log '已安装：登录 Windows 时连接校园 Wi-Fi 并检查认证状态。'
        Invoke-Once $false
    }
    'Once' { Invoke-Once $false }
    'Connect' { Invoke-Once $true }
    'Check' {
        Write-Host ('当前 Wi-Fi：{0}' -f (Get-ConnectedSSID))
        Write-Host ('配置：{0}' -f $(if (Test-Path -LiteralPath $configPath) { '已保存' } else { '未安装' }))
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Write-Host ('计划任务：{0}' -f $(if ($task) { $task.State } else { '未安装' }))
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 10 }
    }
    'Remove' {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $configPath) { Remove-Item -LiteralPath $configPath -Force }
        if (Test-Path -LiteralPath $pausePath) { Remove-Item -LiteralPath $pausePath -Force }
        Write-Host '已删除自动登录任务和加密密码。'
    }
}
