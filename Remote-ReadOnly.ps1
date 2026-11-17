#Requires -Version 5.1
<#
  MuMuGuard 只读远程查看（原型）
  ---------------------------------
  用途：只读取现有文件 + 查询模拟器运行状态，起一个网页给手机看。
  安全：不写入、不控制、不修改 MuMuGuard 的任何状态。
  退出：Ctrl+C 即可。

  用法：powershell -ExecutionPolicy Bypass -File Remote-ReadOnly.ps1
#>

param(
    [int]$Port = 8787,
    [string]$Token = ''
)

$ErrorActionPreference = 'Continue'

# 隐藏进程里控制台默认是 GBK，会把 MuMuManager 的 UTF-8 输出读成乱码并破坏 JSON
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Root = $PSScriptRoot

function Write-Info([string]$msg, [string]$color = 'Gray') {
    Write-Host $msg -ForegroundColor $color
}

# ---------------- 令牌（首次运行自动生成并保存） ----------------
$tokenFile = Join-Path $Root 'remote-token.txt'
if (-not $Token) {
    if (Test-Path $tokenFile) {
        $Token = (Get-Content $tokenFile -Raw).Trim()
    }
    if (-not $Token) {
        $bytes = New-Object byte[] 16
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $Token = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
        [System.IO.File]::WriteAllText($tokenFile, $Token, (New-Object System.Text.UTF8Encoding $false))
    }
}

# ---------------- 数据收集（只读） ----------------
$script:cacheInfo = @{ At = [datetime]::MinValue; Rows = @() }

function Get-MuMuRows {
    # 5 秒缓存，避免每次请求都去拉起 MuMuManager
    if (((Get-Date) - [datetime]$script:cacheInfo.At).TotalSeconds -lt 5 -and $script:cacheInfo.Rows.Count -gt 0) {
        return $script:cacheInfo.Rows
    }
    $rows = @()
    try {
        $cfg = $null
        $cfgPath = Join-Path $Root 'config.json'
        if (Test-Path $cfgPath) { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        $root = ''
        if ($cfg -and $cfg.MuMuRoot) { $root = [string]$cfg.MuMuRoot }
        if (-not $root) { $root = 'D:\Program Files\Netease\MuMu' }
        $mgr = Join-Path $root 'nx_main\MuMuManager.exe'
        if (Test-Path $mgr) {
            $out = & $mgr info -v all 2>&1 | Out-String
            $j = $out | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                $v = $p.Value
                $rows += [pscustomobject]@{
                    Index  = [string]$p.Name
                    Name   = [string]$v.name
                    Running = [bool]$v.is_process_started
                }
            }
        }
    } catch { }
    $script:cacheInfo = @{ At = (Get-Date); Rows = $rows }
    return $rows
}

function Get-AliveState {
    $cfg = $null
    $cfgPath = Join-Path $Root 'config.json'
    if (Test-Path $cfgPath) {
        try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $aliases = @{}
    if ($cfg -and $cfg.Aliases) {
        foreach ($pp in $cfg.Aliases.PSObject.Properties) { $aliases[[string]$pp.Name] = [string]$pp.Value }
    }

    # 休眠列表
    $sleep = @{}
    $sleepPath = Join-Path $Root 'sleep.json'
    if (Test-Path $sleepPath) {
        try {
            $arr = @(Get-Content $sleepPath -Raw -Encoding UTF8 | ConvertFrom-Json)
            foreach ($e in $arr) { if ($null -ne $e.Index) { $sleep[[string]$e.Index] = $e } }
        } catch { }
    }

    # 实例
    $list = @()
    foreach ($r in (Get-MuMuRows)) {
        $name = $r.Name
        if ($aliases.ContainsKey($r.Index)) { $name = $aliases[$r.Index] }
        $item = [ordered]@{
            i     = $r.Index
            name  = $name
            state = if ($r.Running) { 'run' } else { 'off' }
            wake  = ''
        }
        if ($sleep.ContainsKey($r.Index)) {
            $item.state = 'sleep'
            try { $item.wake = ([datetime]$sleep[$r.Index].WakeAt).ToString('HH:mm') } catch { }
        }
        $list += [pscustomobject]$item
    }

    # 主机内存
    $host_ = [ordered]@{ used = 0; total = 0; avail = 0 }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $freeMB  = [math]::Round($os.FreePhysicalMemory / 1024)
        $host_.total = $totalMB
        $host_.avail = $freeMB
        $host_.used  = $totalMB - $freeMB
    } catch { }

    # 今日事件（最后 10 条）
    $events = @()
    try {
        $csv = Join-Path $Root ('logs\guard-{0:yyyyMMdd}.csv' -f (Get-Date))
        if (Test-Path $csv) {
            $rows = @(Import-Csv $csv -ErrorAction Stop)
            $events = @($rows | Select-Object -Last 10 | ForEach-Object {
                $t = ''
                try { $t = ([datetime]$_.Time).ToString('HH:mm:ss') } catch { $t = [string]$_.Time }
                [pscustomobject]@{ t = $t; m = ((('{0} {1}' -f $_.Action, $_.Detail)).Trim()) }
            })
        }
    } catch { }

    return [ordered]@{
        v       = 1
        ts      = [int][double]::Parse((Get-Date -UFormat %s))
        guard   = if ($cfg) { [bool]$cfg.GuardRunning } else { $false }
        sleep   = if ($cfg) { [bool]$cfg.AutoSleep } else { $false }
        host    = $host_
        instances = $list
        events  = $events
    }
}

# ---------------- 网页 ----------------
$PageHtml = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0B0E13">
<title>MuMuGuard</title>
<style>
  :root{
    --bg:#0B0E13; --card:#12161D; --line:#232A36; --text:#E8ECF2;
    --sub:#9BA5B4; --dim:#6B7485; --green:#3FB950; --amber:#D29922; --red:#F85149;
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  body{margin:0;background:var(--bg);color:var(--text);
       font:15px/1.5 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;
       padding:14px 14px 28px;max-width:640px;margin:0 auto}
  header{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}
  .brand{font-size:17px;font-weight:600;letter-spacing:.2px}
  .pill{display:flex;align-items:center;gap:6px;font-size:13px;color:var(--sub)}
  .dot{width:7px;height:7px;border-radius:50%;background:var(--green)}
  .dot.off{background:var(--dim)}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:10px}
  .row{display:flex;align-items:center;justify-content:space-between;padding:7px 0}
  .row+.row{border-top:1px solid rgba(35,42,54,.6)}
  .name{font-size:15px}
  .meta{font-size:12px;color:var(--sub);margin-top:1px}
  .tag{font-size:12px;padding:2px 0;color:var(--sub)}
  .tag.run{color:var(--green)}
  .tag.sleep{color:var(--sub)}
  .tag.off{color:var(--dim)}
  .bar{height:8px;border-radius:6px;background:#1E242E;overflow:hidden}
  .bar>i{display:block;height:100%;background:var(--green);border-radius:6px;transition:width .4s}
  .bar.hi>i{background:var(--amber)}
  .kv{display:flex;justify-content:space-between;font-size:12px;color:var(--sub);margin-top:8px}
  .title{font-size:12px;color:var(--dim);margin:0 0 8px 2px;letter-spacing:.3px}
  .ev{font-size:12px;color:var(--sub);padding:3px 0;font-variant-numeric:tabular-nums}
  .ev b{color:var(--dim);font-weight:400;margin-right:8px}
  .ev.warn{color:var(--amber)}
  .ev.err{color:var(--red)}
  .empty{color:var(--dim);font-size:13px;padding:6px 0}
  footer{text-align:center;color:var(--dim);font-size:11px;margin-top:16px}
</style>
</head>
<body>
<header>
  <div class="brand">MuMuGuard</div>
  <div class="pill"><span class="dot" id="dot"></span><span id="guardText">连接中…</span></div>
</header>

<div class="card">
  <div class="title">实例</div>
  <div id="instances"><div class="empty">正在读取…</div></div>
</div>

<div class="card">
  <div class="title">主机内存</div>
  <div class="bar" id="membar"><i id="memfill" style="width:0%"></i></div>
  <div class="kv"><span id="memUsed">--</span><span id="memTotal">--</span></div>
</div>

<div class="card">
  <div class="title">最近事件</div>
  <div id="events"><div class="empty">暂无</div></div>
</div>

<footer>只读模式 · 不提供控制 · 2 秒刷新</footer>

<script>
const K = new URLSearchParams(location.search).get('k') || '';

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

async function tick(){
  try{
    const r = await fetch('/api/state?k=' + encodeURIComponent(K), {cache:'no-store'});
    if(!r.ok) throw new Error('HTTP ' + r.status);
    const d = await r.json();

    const dot = document.getElementById('dot');
    const gt  = document.getElementById('guardText');
    dot.className = 'dot' + (d.guard ? '' : ' off');
    gt.textContent = d.guard ? '看护中' : '已停止';
    if(!d.guard) gt.style.color = 'var(--dim)'; else gt.style.color = '';

    // 实例
    const box = document.getElementById('instances');
    if(!d.instances || !d.instances.length){
      box.innerHTML = '<div class="empty">没有检测到实例</div>';
    } else {
      box.innerHTML = d.instances.map(it => {
        let tag = '离线', cls = 'off', meta = '';
        if(it.state === 'run'){ tag = '运行中'; cls = 'run'; }
        else if(it.state === 'sleep'){ tag = it.wake ? ('休眠到 ' + it.wake) : '休眠中'; cls = 'sleep'; }
        return '<div class="row"><div><div class="name">' + esc(it.name || ('实例 ' + it.i)) +
               '</div><div class="meta">实例 ' + esc(it.i) + '</div></div>' +
               '<div class="tag ' + cls + '">' + esc(tag) + '</div></div>';
      }).join('');
    }

    // 内存
    const used = d.host ? d.host.used : 0, total = d.host ? d.host.total : 0;
    const pct = total ? Math.min(100, Math.round(used / total * 100)) : 0;
    const bar = document.getElementById('membar');
    document.getElementById('memfill').style.width = pct + '%';
    bar.className = 'bar' + (pct >= 85 ? ' hi' : '');
    document.getElementById('memUsed').textContent  = '已用 ' + (used/1024).toFixed(1) + ' GB';
    document.getElementById('memTotal').textContent = '共 ' + (total/1024).toFixed(1) + ' GB';

    // 事件
    const ev = document.getElementById('events');
    if(!d.events || !d.events.length){
      ev.innerHTML = '<div class="empty">今天还没有事件</div>';
    } else {
      ev.innerHTML = d.events.map(e => {
        let cls = 'ev';
        const m = String(e.m || '');
        if(/失败|异常|掉线|未运行|错误/.test(m)) cls += ' err';
        else if(/告警|偏高|接近|不足/.test(m)) cls += ' warn';
        return '<div class="' + cls + '"><b>' + esc(e.t) + '</b>' + esc(m) + '</div>';
      }).join('');
    }
  }catch(err){
    document.getElementById('guardText').textContent = '连接断开';
    document.getElementById('dot').className = 'dot off';
  }
}
tick();
setInterval(tick, 2000);
</script>
</body>
</html>
'@

# ---------------- 极简 HTTP 服务 ----------------
function Read-Request([System.Net.Sockets.TcpClient]$client) {
    $stream = $client.GetStream()
    $client.ReceiveTimeout = 3000
    $buffer = New-Object byte[] 4096
    $sb = New-Object System.Text.StringBuilder
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
        if (-not $stream.DataAvailable) {
            Start-Sleep -Milliseconds 20
            if ($sb.Length -gt 0 -and $sb.ToString() -match "\r\n\r\n") { break }
            continue
        }
        $n = $stream.Read($buffer, 0, $buffer.Length)
        if ($n -le 0) { break }
        [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $n))
        if ($sb.ToString() -match "\r\n\r\n") { break }
    }
    return $sb.ToString()
}

function Send-Response([System.Net.Sockets.TcpClient]$client, [int]$code, [string]$ctype, [string]$body) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $reason = switch ($code) { 200 { 'OK' } 401 { 'Unauthorized' } 404 { 'Not Found' } default { 'OK' } }
    $head = "HTTP/1.1 $code $reason`r`n" +
            "Content-Type: $ctype`r`n" +
            "Content-Length: $($bytes.Length)`r`n" +
            "Cache-Control: no-store`r`n" +
            "Connection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream = $client.GetStream()
    $stream.Write($hb, 0, $hb.Length)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

$ip = '0.0.0.0'
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
try { $listener.Start() } catch {
    Write-Info "端口 $Port 启动失败：$($_.Exception.Message)" 'Red'
    Write-Info '可能是端口被占用，换个端口：powershell -File Remote-ReadOnly.ps1 -Port 8788' 'Yellow'
    return
}

$lanIps = @()
try {
    $lanIps = @()
    try {
        foreach ($a in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            if ($a.IPAddress -match '^(127\.|169\.254\.|198\.18\.)') { continue }
            $desc = ''
            try { $desc = (Get-NetAdapter -InterfaceIndex $a.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceDescription } catch { }
            # 跳过虚拟网卡（VMware / VirtualBox / 代理 TUN），手机连不上它们
            if ($desc -match 'VMware|VirtualBox|TAP-|Hyper-V|xxyun|Clash|Loopback') { continue }
            $lanIps += $a.IPAddress
        }
    } catch { }
} catch { }

Write-Host ''
Write-Host '=== MuMuGuard 只读远程查看 ===' -ForegroundColor Cyan
Write-Host "  令牌: $Token"
foreach ($ipAddr in $lanIps) {
    Write-Host "  手机打开: http://${ipAddr}:$Port/?k=$Token" -ForegroundColor Green
}
Write-Host '  只读：不会控制、不会修改任何数据' -ForegroundColor DarkGray
Write-Host '  停止：按 Ctrl+C' -ForegroundColor DarkGray
Write-Host ''

while ($true) {
    try {
        $client = $listener.AcceptTcpClient()
        try {
            $remote = $client.Client.RemoteEndPoint.ToString()
            $line = '[{0:HH:mm:ss}] conn {1}' -f (Get-Date), $remote
            [System.IO.File]::AppendAllText((Join-Path $Root 'remote-access.log'), $line + "`r`n", (New-Object System.Text.UTF8Encoding $false))
        } catch { }
    } catch { break }

    try {
        $req = Read-Request $client
        $line = ($req -split "`r`n")[0]
        $path = ''
        if ($line -match '^GET\s+(\S+)') { $path = $Matches[1] }

        $query = ''
        if ($path -match '\?(.*)$') { $query = $Matches[1]; $path = $path -replace '\?.*$', '' }
        $given = ''
        foreach ($kv in ($query -split '&')) {
            if ($kv -match '^k=(.*)$') { $given = [System.Uri]::UnescapeDataString($Matches[1]) }
        }

        if ($path -eq '/' -or $path -eq '/index.html') {
            if ($given -ne $Token) {
                Send-Response $client 401 'text/plain; charset=utf-8' '令牌不正确'
            } else {
                Send-Response $client 200 'text/html; charset=utf-8' $PageHtml
            }
        }
        elseif ($path -eq '/api/state') {
            if ($given -ne $Token) {
                Send-Response $client 401 'application/json; charset=utf-8' '{"error":"token"}'
            } else {
                $state = Get-AliveState
                $json = $state | ConvertTo-Json -Depth 6 -Compress
                Send-Response $client 200 'application/json; charset=utf-8' $json
            }
        }
        else {
            Send-Response $client 404 'text/plain; charset=utf-8' 'not found'
        }
    } catch {
        try { Send-Response $client 500 'text/plain; charset=utf-8' 'error' } catch { }
    } finally {
        try { $client.Close() } catch { }
    }
}