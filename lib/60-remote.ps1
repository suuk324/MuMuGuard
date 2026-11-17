#Requires -Version 5.1
#
# 远程访问：内置网页服务 + 指令队列
# 本文件由 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）
#
# 设计要点：
#   1. 服务跑在独立 runspace，绝不碰界面对象
#   2. 状态由 UI 线程定时生成 JSON 快照，服务只读这个字符串（不跨线程读活对象）
#   3. 指令进并发队列，由 UI 线程的定时器取出执行 —— 和本地点按钮走同一套函数

$script:remotePs    = $null
$script:remoteRs    = $null
$script:remoteHandle = $null

function New-RemoteToken {
    $bytes = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join '')
}

function Get-RemoteToken {
    $t = ''
    try { $t = [string]$script:cfg.RemoteToken } catch { }
    if (-not $t) {
        $t = New-RemoteToken
        try { $script:cfg.RemoteToken = $t; Save-Config } catch { }
    }
    return $t
}

function Get-RemoteUrls {
    $port = 8787
    try { if ($script:cfg.RemotePort) { $port = [int]$script:cfg.RemotePort } } catch { }
    $token = Get-RemoteToken
    $urls = @()
    try {
        foreach ($a in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            if ($a.IPAddress -match '^(127\.|169\.254\.|198\.18\.)') { continue }
            $desc = ''
            try { $desc = (Get-NetAdapter -InterfaceIndex $a.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceDescription } catch { }
            if ($desc -match 'VMware|VirtualBox|TAP-|Hyper-V|xxyun|Clash|Loopback|Meta Tunnel') { continue }
            $urls += [pscustomobject]@{
                Ip  = $a.IPAddress
                Url = "http://$($a.IPAddress):$port/?k=$token"
            }
        }
    } catch { }
    return $urls
}

# ---------------- 状态快照（UI 线程调用） ----------------
function Build-RemoteState {
    $list = @()
    try {
        foreach ($r in @($script:lastInstances)) {
            if (-not $r) { continue }
            $state = 'unknown'
            $extra = ''
            $wake = ''
            try {
                if ($r.PSObject.Properties.Name -contains 'Sleeping' -and $r.Sleeping) {
                    $state = 'sleep'
                    if ($r.WakeAt) { $wake = ([datetime]$r.WakeAt).ToString('HH:mm') }
                    if ($r.SleepUpgrade) { $extra = [string]$r.SleepUpgrade }
                } elseif ($r.Online -eq $true) {
                    $state = 'run'
                    if ($r.UpLeft) { $extra = '剩 ' + [string]$r.UpLeft }
                } elseif ($r.Online -eq $false) {
                    $state = 'off'
                }
            } catch { }
            $list += [pscustomobject][ordered]@{
                i     = "$($r.Index)"
                name  = "$($r.Name)"
                state = $state
                wake  = $wake
                extra = $extra
                judge = "$($r.Judge)"
                mem   = [int]$r.Private
                cores = [double]$r.Cores
            }
        }
    } catch { }

    $hostInfo = [ordered]@{ used = 0; total = 0; avail = 0 }
    try {
        $mi = [MemInfo]::Get()
        $totalMB = [math]::Round($mi[0] / 1MB)
        $freeMB  = [math]::Round($mi[1] / 1MB)
        $hostInfo.total = $totalMB
        $hostInfo.avail = $freeMB
        $hostInfo.used  = $totalMB - $freeMB
    } catch { }

    $events = @()
    try {
        $csv = Get-LogFile
        if (Test-Path $csv) {
            $rows = @(Import-Csv $csv -ErrorAction Stop)
            $events = @($rows | Select-Object -Last 8 | ForEach-Object {
                $t = ''
                try { $t = ([datetime]$_.Time).ToString('HH:mm:ss') } catch { $t = [string]$_.Time }
                [pscustomobject][ordered]@{ t = $t; m = ([string]('{0} {1}' -f $_.Action, $_.Detail)).Trim() }
            })
        }
    } catch { }

    $obj = [ordered]@{
        v         = 1
        ts        = [int][double]::Parse((Get-Date -UFormat %s))
        guard     = [bool]$script:guardRunning
        sleep     = [bool]$script:cfg.AutoSleep
        host      = $hostInfo
        instances = $list
        events    = $events
    }
    try { return ($obj | ConvertTo-Json -Depth 6 -Compress) } catch { return '{}' }
}

# ---------------- 服务端脚本（后台 runspace 运行） ----------------
$script:remoteServerScript = {
    param($sync, $port, $token, $root)

    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        $sync.ServerError = ''
    } catch {
        $sync.ServerError = $_.Exception.Message
        return
    }

    function Read-Req($client) {
        $stream = $client.GetStream()
        $client.ReceiveTimeout = 4000
        $buffer = New-Object byte[] 8192
        $sb = New-Object System.Text.StringBuilder
        $deadline = (Get-Date).AddSeconds(4)
        $headEnd = -1
        $need = 0
        while ((Get-Date) -lt $deadline) {
            $text = $sb.ToString()
            if ($headEnd -lt 0) {
                $idx = $text.IndexOf("`r`n`r`n")
                if ($idx -ge 0) {
                    $headEnd = $idx + 4
                    if ($text -match '(?i)Content-Length:\s*(\d+)') { $need = [int]$Matches[1] }
                }
            }
            if ($headEnd -ge 0 -and ($sb.Length - $headEnd) -ge $need) { break }
            if (-not $stream.DataAvailable) { Start-Sleep -Milliseconds 15; continue }
            $n = $stream.Read($buffer, 0, $buffer.Length)
            if ($n -le 0) { break }
            [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $n))
        }
        return $sb.ToString()
    }
    function Send-Res($client, $code, $ctype, $body) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $reason = switch ($code) { 200 { 'OK' } 401 { 'Unauthorized' } 404 { 'Not Found' } 405 { 'Method Not Allowed' } default { 'OK' } }
        $head = "HTTP/1.1 $code $reason`r`nContent-Type: $ctype`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
        $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
        $stream = $client.GetStream()
        $stream.Write($hb, 0, $hb.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    }

    while ($true) {
        if ($sync.Stop) { break }
        $client = $null
        try { $client = $listener.AcceptTcpClient() } catch { break }
        try {
            $req = Read-Req $client
            $first = ($req -split "`r`n")[0]
            $method = 'GET'; $path = '/'
            if ($first -match '^(\w+)\s+(\S+)') { $method = $Matches[1]; $path = $Matches[2] }

            $query = ''
            if ($path -match '\?(.*)$') { $query = $Matches[1]; $path = $path -replace '\?.*$', '' }

            $given = ''
            foreach ($kv in ($query -split '&')) {
                if ($kv -match '^k=(.*)$') { $given = [System.Uri]::UnescapeDataString($Matches[1]) }
            }
            if ($given -ne $token) {
                Send-Res $client 401 'text/plain; charset=utf-8' 'TOKEN'
                continue
            }

            if ($path -eq '/' -or $path -eq '/index.html') {
                Send-Res $client 200 'text/html; charset=utf-8' $sync.RemotePage
            }
            elseif ($path -eq '/api/state') {
                $state = [string]$sync.RemoteState
                if (-not $state) { $state = '{}' }
                Send-Res $client 200 'application/json; charset=utf-8' $state
            }
            elseif ($path -eq '/api/action' -and $method -eq 'POST') {
                $body = ''
                if ($req -match "\r\n\r\n(.*)$") { $body = $Matches[1] }
                $cmd = $null
                try { $cmd = $body | ConvertFrom-Json } catch { }
                if (-not $cmd -or -not $cmd.cmd) {
                    Send-Res $client 200 'application/json; charset=utf-8' '{"ok":false,"msg":"bad request"}'
                } else {
                    $item = [ordered]@{ cmd = "$($cmd.cmd)"; i = "$($cmd.i)"; at = (Get-Date).ToString('HH:mm:ss') }
                    [void]$sync.RemoteQueue.Enqueue([pscustomobject]$item)
                    Send-Res $client 200 'application/json; charset=utf-8' '{"ok":true}'
                }
            }
            else {
                Send-Res $client 404 'text/plain; charset=utf-8' 'not found'
            }
        } catch { }
        finally { try { $client.Close() } catch { } }
    }
    try { $listener.Stop() } catch { }
}

# ---------------- 页面 ----------------
function Get-RemotePage {
    return @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0B0E13">
<title>MuMuGuard</title>
<style>
  :root{--bg:#0B0E13;--card:#12161D;--line:#232A36;--text:#E8ECF2;--sub:#9BA5B4;--dim:#6B7485;--green:#3FB950;--amber:#D29922;--red:#F85149}
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;padding:14px 14px 26px;max-width:640px;margin:0 auto}
  header{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}
  .brand{font-size:17px;font-weight:600}
  .pill{display:flex;align-items:center;gap:6px;font-size:13px;color:var(--sub)}
  .dot{width:7px;height:7px;border-radius:50%;background:var(--green)}
  .dot.off{background:var(--dim)}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:13px;margin-bottom:10px}
  .row{display:flex;align-items:center;justify-content:space-between;padding:8px 0}
  .row+.row{border-top:1px solid rgba(35,42,54,.6)}
  .name{font-size:15px}
  .meta{font-size:12px;color:var(--sub);margin-top:2px}
  .tag{font-size:12px;color:var(--sub);white-space:nowrap}
  .tag.run{color:var(--green)}.tag.sleep{color:var(--sub)}.tag.off{color:var(--dim)}
  .bar{height:8px;border-radius:6px;background:#1E242E;overflow:hidden;margin-top:2px}
  .bar>i{display:block;height:100%;background:var(--green);border-radius:6px;transition:width .4s}
  .bar.hi>i{background:var(--amber)}
  .kv{display:flex;justify-content:space-between;font-size:12px;color:var(--sub);margin-top:8px}
  .title{font-size:12px;color:var(--dim);margin:0 0 6px 2px}
  .ev{font-size:12px;color:var(--sub);padding:3px 0;font-variant-numeric:tabular-nums}
  .ev b{color:var(--dim);font-weight:400;margin-right:8px}
  .ev.warn{color:var(--amber)}.ev.err{color:var(--red)}
  .empty{color:var(--dim);font-size:13px;padding:4px 0}
  .btns{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:2px}
  button{appearance:none;border:1px solid var(--line);background:#1A1F29;color:var(--text);border-radius:10px;padding:11px 8px;font-size:14px;font-family:inherit}
  button:active{background:#232A36}
  button.warn{color:var(--amber);border-color:#3A2F14}
  button.danger{color:var(--red);border-color:#3A1A1A}
  button:disabled{opacity:.45}
  .toast{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);background:#1A1F29;border:1px solid var(--line);color:var(--text);padding:9px 16px;border-radius:10px;font-size:13px;opacity:0;transition:opacity .2s;pointer-events:none}
  .toast.show{opacity:1}
  footer{text-align:center;color:var(--dim);font-size:11px;margin-top:14px}
</style>
</head>
<body>
<header>
  <div class="brand">MuMuGuard</div>
  <div class="pill"><span class="dot" id="dot"></span><span id="guardText">连接中…</span></div>
</header>

<div class="card"><div class="title">实例</div><div id="instances"><div class="empty">正在读取…</div></div></div>

<div class="card">
  <div class="title">操作</div>
  <div class="btns">
    <button id="bGuard">停止看护</button>
    <button id="bSleep">休眠 关</button>
    <button id="bClean">立即清理</button>
    <button id="bWakeAll" class="warn">全部唤醒</button>
  </div>
</div>

<div class="card">
  <div class="title">主机内存</div>
  <div class="bar" id="membar"><i id="memfill" style="width:0%"></i></div>
  <div class="kv"><span id="memUsed">--</span><span id="memTotal">--</span></div>
</div>

<div class="card"><div class="title">最近事件</div><div id="events"><div class="empty">暂无</div></div></div>

<footer>每 2 秒刷新 · 数据仅在本机与手机之间</footer>
<div class="toast" id="toast"></div>

<script>
const K = new URLSearchParams(location.search).get('k') || '';
let lastState = null;

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }
function toast(msg){
  const t = document.getElementById('toast');
  t.textContent = msg; t.classList.add('show');
  clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 1600);
}

async function act(cmd, i){
  if(cmd === 'guard' || cmd === 'sleep'){
    const now = lastState ? (cmd === 'guard' ? lastState.guard : lastState.sleep) : null;
    if(now === null) return;
  }
  try{
    const r = await fetch('/api/action?k=' + encodeURIComponent(K), {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify(i ? {cmd:cmd, i:i} : {cmd:cmd})
    });
    const j = await r.json();
    toast(j.ok ? '已发送' : '发送失败');
    setTimeout(tick, 400);
  }catch(e){ toast('网络错误'); }
}

async function tick(){
  try{
    const r = await fetch('/api/state?k=' + encodeURIComponent(K), {cache:'no-store'});
    if(!r.ok) throw new Error('HTTP ' + r.status);
    const d = await r.json();
    lastState = d;

    const dot = document.getElementById('dot');
    dot.className = 'dot' + (d.guard ? '' : ' off');
    const gt = document.getElementById('guardText');
    gt.textContent = d.guard ? '看护中' : '已停止';
    gt.style.color = d.guard ? '' : 'var(--dim)';

    document.getElementById('bGuard').textContent = d.guard ? '停止看护' : '启动看护';
    document.getElementById('bSleep').textContent = d.sleep ? '休眠 开' : '休眠 关';
    document.getElementById('bSleep').className = d.sleep ? '' : 'warn';

    const box = document.getElementById('instances');
    if(!d.instances || !d.instances.length){
      box.innerHTML = '<div class="empty">没有检测到实例</div>';
    } else {
      box.innerHTML = d.instances.map(it => {
        let tag = '离线', cls = 'off', meta = '实例 ' + esc(it.i);
        if(it.state === 'run'){ tag = '运行中'; cls = 'run'; if(it.extra) meta = esc(it.extra); }
        else if(it.state === 'sleep'){ tag = it.wake ? ('休眠到 ' + it.wake) : '休眠中'; cls = 'sleep'; if(it.extra) meta = esc(it.extra); }
        else if(it.state === 'unknown'){ tag = '未知'; cls = 'off'; }
        if(it.judge && it.judge !== '正常'){ meta += ' · ' + esc(it.judge); }
        return '<div class="row"><div><div class="name">' + esc(it.name) + '</div><div class="meta">' + meta + '</div></div>' +
               '<div class="tag ' + cls + '">' + esc(tag) + '</div></div>';
      }).join('');
    }

    const used = d.host ? d.host.used : 0, total = d.host ? d.host.total : 0;
    const pct = total ? Math.min(100, Math.round(used / total * 100)) : 0;
    document.getElementById('memfill').style.width = pct + '%';
    document.getElementById('membar').className = 'bar' + (pct >= 85 ? ' hi' : '');
    document.getElementById('memUsed').textContent  = '已用 ' + (used/1024).toFixed(1) + ' GB';
    document.getElementById('memTotal').textContent = '共 ' + (total/1024).toFixed(1) + ' GB';

    const ev = document.getElementById('events');
    if(!d.events || !d.events.length){
      ev.innerHTML = '<div class="empty">今天还没有事件</div>';
    } else {
      ev.innerHTML = d.events.map(e => {
        let cls = 'ev'; const m = String(e.m || '');
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

document.getElementById('bGuard').onclick   = () => act('guard');
document.getElementById('bSleep').onclick   = () => act('sleep');
document.getElementById('bClean').onclick   = () => { if(confirm('立即清理？')) act('clean'); };
document.getElementById('bWakeAll').onclick = () => { if(confirm('唤醒所有休眠实例？')) act('wakeall'); };

tick();
setInterval(tick, 2000);
</script>
</body>
</html>
'@
}

# ---------------- 启停 ----------------
function Start-RemoteServer {
    if ($script:remoteHandle) { return $true }
    $port = 8787
    try { if ($script:cfg.RemotePort) { $port = [int]$script:cfg.RemotePort } } catch { }
    $token = Get-RemoteToken

    $sync = $script:adbSync
    $sync | Add-Member -NotePropertyName RemoteState -NotePropertyValue '{}' -Force
    $sync | Add-Member -NotePropertyName RemotePage -NotePropertyValue (Get-RemotePage) -Force
    $sync | Add-Member -NotePropertyName RemoteQueue -NotePropertyValue (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]') -Force
    $sync | Add-Member -NotePropertyName RemotePort -NotePropertyValue $port -Force
    $sync | Add-Member -NotePropertyName RemoteStop -NotePropertyValue $false -Force
    $sync | Add-Member -NotePropertyName ServerError -NotePropertyValue '' -Force

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:remoteServerScript).AddArgument($sync).AddArgument($port).AddArgument($token).AddArgument($Root)
    $handle = $ps.BeginInvoke()

    $script:remotePs = $ps
    $script:remoteRs = $rs
    $script:remoteHandle = $handle
    Start-Sleep -Milliseconds 300
    if ($sync.ServerError) {
        Write-Diag "远程服务启动失败: $($sync.ServerError)"
        Stop-RemoteServer
        return $false
    }
    Write-Diag "远程服务已启动，端口 $port"
    return $true
}

function Stop-RemoteServer {
    try { if ($script:adbSync) { $script:adbSync.RemoteStop = $true } } catch { }
    try { if ($script:remotePs) { [void]$script:remotePs.Stop() } } catch { }
    try { if ($script:remotePs) { $script:remotePs.Dispose() } } catch { }
    try { if ($script:remoteRs) { $script:remoteRs.Close(); $script:remoteRs.Dispose() } } catch { }
    $script:remotePs = $null
    $script:remoteRs = $null
    $script:remoteHandle = $null
}

# ---------------- 指令处理（UI 线程） ----------------
function Invoke-RemoteCommands {
    $sync = $script:adbSync
    if (-not $sync -or -not ($sync.PSObject.Properties.Name -contains 'RemoteQueue')) { return }
    $q = $sync.RemoteQueue
    $obj = $null
    $n = 0
    while ($n -lt 8 -and $q.TryDequeue([ref]$obj)) {
        $n++
        try {
            switch ("$($obj.cmd)") {
                'guard'   { Set-GuardState; Write-Diag '远程：切换看护' }
                'sleep'   {
                    $script:cfg.AutoSleep = -not [bool]$script:cfg.AutoSleep
                    Save-Config; Update-SleepButton
                    Write-Diag ("远程：升级休眠 = {0}" -f $script:cfg.AutoSleep)
                }
                'clean'   { Invoke-GuardCleanup; Write-Diag '远程：立即清理' }
                'restart' {
                    if ($obj.i) { Start-InstanceRecover "$($obj.i)"; Write-Diag "远程：重启实例 $($obj.i)" }
                }
                'wakeall' { try { Start-Waker } catch { }; Write-Diag '远程：全部唤醒' }
                default   { write-Diag "远程：未知指令 $($obj.cmd)" }
            }
        } catch {
            Write-Diag "远程指令执行失败（$($obj.cmd)）: $($_.Exception.Message)"
        }
    }
    # 快照交给服务线程
    try { $sync.RemoteState = Build-RemoteState } catch { }
}

# ---------------- 手机访问窗口（XAML 构建，和设置面板同一套做法，DPI 才正常） ----------------
$script:remoteXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="手机访问" Width="420" Height="580"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ShowInTaskbar="False">
  <Window.Resources>
    <Style x:Key="DlgBtn" TargetType="Button">
      <Setter Property="Background" Value="#1A1F29"/>
      <Setter Property="Foreground" Value="#E8ECF2"/>
      <Setter Property="BorderBrush" Value="#232A36"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="0,7,0,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="8" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Viewbox Stretch="Uniform"><Border CornerRadius="12" Background="#0B0E13" BorderBrush="#232A36" BorderThickness="1" Padding="22">
    <StackPanel>
      <DockPanel Margin="0,0,0,6">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="BtnModeLan" Content="局域网" Style="{StaticResource DlgBtn}" Padding="10,4,10,4" Margin="0,0,6,0"/>
          <Button x:Name="BtnModeWan" Content="出门用" Style="{StaticResource DlgBtn}" Padding="10,4,10,4"/>
        </StackPanel>
        <TextBlock Text="手机访问" Foreground="#E8ECF2" FontSize="13" FontWeight="Bold" VerticalAlignment="Center"/>
      </DockPanel>
      <TextBlock x:Name="TxtHint" Foreground="#6B7485" FontSize="11" TextWrapping="Wrap"
                 Width="330" HorizontalAlignment="Left" Margin="0,0,0,14"/>
      <Border x:Name="QrBox" Width="210" Height="210" Background="White" CornerRadius="8"
              HorizontalAlignment="Center" Margin="0,0,0,12">
        <Image x:Name="ImgQr" Width="186" Height="186" Stretch="Uniform"/>
      </Border>
      <TextBlock x:Name="TxtUrl" Foreground="#9BA5B4" FontSize="10" TextWrapping="Wrap"
                 Width="330" TextAlignment="Center" Margin="0,0,0,14"/>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
        </Grid.ColumnDefinitions>
        <Button x:Name="BtnPower" Grid.Column="0" Style="{StaticResource DlgBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnRefresh" Grid.Column="1" Content="刷新令牌" Style="{StaticResource DlgBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnClose" Grid.Column="2" Content="关闭" Style="{StaticResource DlgBtn}"/>
      </Grid>
    </StackPanel>
  </Border></Viewbox>
</Window>
"@

function Show-RemoteDialog {
    if ($script:remoteDlg) {
        try { $script:remoteDlg.Activate() } catch { }
        return
    }
    $dlg = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme $script:remoteXaml))
    Set-ThemeResources $dlg (Get-ActiveTheme)
   if ($win -and $win.IsVisible) { try { $dlg.Owner = $win } catch { } }

    $hint     = $dlg.FindName('TxtHint')
    $qrBox    = $dlg.FindName('QrBox')
    $imgQr    = $dlg.FindName('ImgQr')
    $txtUrl   = $dlg.FindName('TxtUrl')
    $btnPower = $dlg.FindName('BtnPower')
    $btnRefresh = $dlg.FindName('BtnRefresh')
    $btnModeLan = $dlg.FindName('BtnModeLan')
    $btnModeWan = $dlg.FindName('BtnModeWan')

    $script:remoteMode = 'lan'

    $refreshUi = {
        $isLan = ($script:remoteMode -eq 'lan')
        $btnModeLan.Foreground = if ($isLan) { Brush '#E8ECF2' } else { Brush '#6B7485' }
        $btnModeWan.Foreground = if ($isLan) { Brush '#6B7485' } else { Brush '#E8ECF2' }

        $enabled = if ($isLan) { [bool]$script:cfg.RemoteEnabled } else { [bool]$script:cfg.OutboundEnabled }
        if ($isLan) {
            $hint.Text = '手机扫下面的二维码，或直接输入网址。同一 WiFi 下即可访问。'
        } else {
            $hint.Text = '出门在外也能用：手机打开下面的地址（走公共中转，不需要同一 WiFi）。'
        }

        if ($enabled) {
            $btnPower.Content = '停止'
            $btnRefresh.IsEnabled = $isLan
            if ($isLan) {
                $urls = @(Get-RemoteUrls)
                $url = ''
                if ($urls.Count -gt 0) { $url = $urls[0].Url }
                if ($url) {
                    $txtUrl.Text = $url
                    $qrBox.Visibility = 'Visible'
                    try { $imgQr.Source = New-QrBitmap $url 8 3 } catch { $imgQr.Source = $null }
                } else {
                    $txtUrl.Text = '没有找到可用的局域网地址'
                    $qrBox.Visibility = 'Collapsed'
                }
            } else {
                $url = Get-OutboundPageUrl
                $txtUrl.Text = $url
                $qrBox.Visibility = 'Visible'
                try { $imgQr.Source = New-QrBitmap $url 8 3 } catch { $imgQr.Source = $null }
            }
        } else {
            $btnPower.Content = '启用'
            $btnRefresh.IsEnabled = $false
            $txtUrl.Text = ''
            $qrBox.Visibility = 'Collapsed'
        }
    }

    $btnModeLan.Add_Click({ $script:remoteMode = 'lan'; & $refreshUi })
    $btnModeWan.Add_Click({ $script:remoteMode = 'wan'; & $refreshUi })
    $btnPower.Add_Click({
        try {
            if ($script:remoteMode -eq 'lan') {
                if ([bool]$script:cfg.RemoteEnabled) {
                    Stop-RemoteServer
                    $script:cfg.RemoteEnabled = $false
                } else {
                    $script:cfg.RemoteEnabled = $true
                    if (-not $script:cfg.RemoteToken) { $script:cfg.RemoteToken = New-RemoteToken }
                    if (-not (Start-RemoteServer)) { $script:cfg.RemoteEnabled = $false }
                }
            } else {
                if ([bool]$script:cfg.OutboundEnabled) {
                    Stop-Outbound
                    $script:cfg.OutboundEnabled = $false
                } else {
                    $script:cfg.OutboundEnabled = $true
                    if (-not (Get-OutboundUid)) { $script:cfg.OutboundUid = New-OutboundUid }
                    if (-not (Start-Outbound)) { $script:cfg.OutboundEnabled = $false }
                }
            }
            Save-Config
        } catch { Write-Diag "切换手机访问失败: $($_.Exception.Message)" }
        & $refreshUi
    })
    $btnRefresh.Add_Click({
        try {
            $script:cfg.RemoteToken = New-RemoteToken
            Save-Config
            if ($script:cfg.RemoteEnabled) {
                Stop-RemoteServer
                [void](Start-RemoteServer)
            }
            Write-Diag '手机访问：令牌已刷新'
        } catch { Write-Diag "刷新令牌失败: $($_.Exception.Message)" }
        & $refreshUi
    })

    $dlg.FindName('BtnClose').Add_Click({ $dlg.Close() })
    $dlg.Add_Closed({ $script:remoteDlg = $null })
    $dlg.Add_MouseLeftButtonDown({ try { $dlg.DragMove() } catch { } })

    $script:remoteDlg = $dlg
    & $refreshUi
    [void]$dlg.Show()
}
