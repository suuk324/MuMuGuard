#Requires -Version 5.1
#
# 出站通道：程序主动连到公共 MQTT，手机也从外面连同一个 broker
# 这样不需要公网 IP、不改路由器、不受本机 VPN 影响
#
# topic:
#   mumuguard/<uid>/state  程序发布（retained，手机连上立刻拿到最新状态）
#   mumuguard/<uid>/cmd    手机发布，程序订阅后丢进同一个指令队列
#
# 手机页面地址（GitHub Pages 静态页）：
#   https://<owner>.github.io/<repo>/remote/?u=<uid>

$script:mqttPs = $null
$script:mqttRs = $null
$script:mqttHandle = $null

function New-OutboundUid {
    $bytes = New-Object byte[] 12
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join '')
}

function Get-OutboundUid {
    $u = ''
    try { $u = [string]$script:cfg.OutboundUid } catch { }
    if (-not $u) {
        $u = New-OutboundUid
        try { $script:cfg.OutboundUid = $u; Save-Config } catch { }
    }
    return $u
}

function New-OutboundKey {
    $bytes = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join '')
}

function Get-OutboundKey {
    $k = ''
    try { $k = [string]$script:cfg.OutboundKey } catch { }
    if (-not $k) {
        $k = New-OutboundKey
        try { $script:cfg.OutboundKey = $k; Save-Config } catch { }
    }
    return $k
}

function Get-OutboundPageUrl {
    $base = ''
    try { $base = [string]$script:cfg.OutboundPage } catch { }
    if (-not $base) { $base = 'https://suuk324.github.io/MuMuGuard/remote/' }
    if ($base -notmatch '/$') { $base += '/' }
    return ($base + '?u=' + (Get-OutboundUid) + '&k=' + (Get-OutboundKey))
}

# 后台脚本：自包含，不依赖外部函数（runspace 里没有模块函数）
$script:mqttScript = {
    param($sync, $broker, $port, $uid, $clientId, $root, $key)

    function Log([string]$m) {
        try { Add-Content -Path (Join-Path $root 'logs\outbound.log') -Value ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $m) -Encoding UTF8 } catch { }
    }
    Log ('循环启动 ' + $broker + ':' + $port)
    $topicState = "mumuguard/$uid/state"
    $topicCmd   = "mumuguard/$uid/cmd"

    function EncLen([int]$len) {
        $out = New-Object System.Collections.Generic.List[byte]
        do {
            $b = $len % 128
            $len = [Math]::Floor($len / 128)
            if ($len -gt 0) { $b = $b -bor 0x80 }
            $out.Add([byte]$b)
        } while ($len -gt 0)
        return ,$out.ToArray()
    }
    function MqStr([string]$s) {
        $b = [System.Text.Encoding]::UTF8.GetBytes($s)
        $out = New-Object System.Collections.Generic.List[byte]
        $out.Add([byte](($b.Length -shr 8) -band 0xFF))
        $out.Add([byte]($b.Length -band 0xFF))
        $out.AddRange($b)
        return ,$out.ToArray()
    }
    function ConnectPkt([string]$cid) {
        $body = New-Object System.Collections.Generic.List[byte]
        $body.AddRange([byte[]](MqStr 'MQTT'))
        $body.Add(4); $body.Add(2); $body.Add(0); $body.Add(60)
        $body.AddRange([byte[]](MqStr $cid))
        $out = New-Object System.Collections.Generic.List[byte]
        $out.Add(0x10)
        $out.AddRange([byte[]](EncLen $body.Count))
        $out.AddRange($body.ToArray())
        return ,$out.ToArray()
    }
    function SubPkt([int]$id, [string]$topic) {
        $body = New-Object System.Collections.Generic.List[byte]
        $body.Add([byte](($id -shr 8) -band 0xFF)); $body.Add([byte]($id -band 0xFF))
        $body.AddRange([byte[]](MqStr $topic)); $body.Add(0)
        $out = New-Object System.Collections.Generic.List[byte]
        $out.Add(0x82)
        $out.AddRange([byte[]](EncLen $body.Count))
        $out.AddRange($body.ToArray())
        return ,$out.ToArray()
    }
    function PubPkt([string]$topic, [string]$payload) {
        $tb = [System.Text.Encoding]::UTF8.GetBytes($topic)
        $pb = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $body = New-Object System.Collections.Generic.List[byte]
        $body.Add([byte](($tb.Length -shr 8) -band 0xFF)); $body.Add([byte]($tb.Length -band 0xFF))
        $body.AddRange($tb); $body.AddRange($pb)
        $out = New-Object System.Collections.Generic.List[byte]
        $out.Add(0x31)   # PUBLISH + retain
        $out.AddRange([byte[]](EncLen $body.Count))
        $out.AddRange($body.ToArray())
        return ,$out.ToArray()
    }
    function ReadPkt($stream) {
        $one = New-Object byte[] 1
        if ($stream.Read($one, 0, 1) -ne 1) { return $null }
        $type = $one[0]
        $mult = 1; $len = 0
        for ($i = 0; $i -lt 4; $i++) {
            if ($stream.Read($one, 0, 1) -ne 1) { return $null }
            $b = $one[0]
            $len += ($b -band 0x7F) * $mult
            $mult *= 128
            if (($b -band 0x80) -eq 0) { break }
        }
        $payload = New-Object byte[] $len
        $read = 0
        while ($read -lt $len) {
            $n = $stream.Read($payload, $read, $len - $read)
            if ($n -le 0) { return $null }
            $read += $n
        }
        return @{ Type = $type; Payload = $payload }
    }
    function ParsePub($payload) {
        if ($payload.Length -lt 2) { return $null }
        $tlen = ([int]$payload[0] -shl 8) -bor [int]$payload[1]
        if ($payload.Length -lt (2 + $tlen)) { return $null }
        $topic = [System.Text.Encoding]::UTF8.GetString($payload, 2, $tlen)
        $body = ''
        if ($payload.Length -gt (2 + $tlen)) {
            $body = [System.Text.Encoding]::UTF8.GetString($payload, 2 + $tlen, $payload.Length - 2 - $tlen)
        }
        return @{ Topic = $topic; Body = $body }
    }

    while (-not $sync.OutboundStop) {
        $client = $null; $ssl = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect($broker, $port)
            $ssl = New-Object System.Net.Security.SslStream($client.GetStream(), $false)
            $ssl.AuthenticateAsClient($broker)
            $stream = $ssl
            $stream.ReadTimeout = 4000

            $pkt = ConnectPkt $clientId
            $stream.Write($pkt, 0, $pkt.Length); $stream.Flush()
            $ack = ReadPkt $stream
            if (-not $ack -or $ack.Type -ne 0x20) { throw 'CONNACK 失败' }

            $pkt = SubPkt 1 $topicCmd
            $stream.Write($pkt, 0, $pkt.Length); $stream.Flush()
            [void](ReadPkt $stream)

            Log 'CONNECT ok'
            $sync.OutboundOk = $true
            $sync.OutboundError = ''
            $lastPub = [datetime]::MinValue
            $lastPing = Get-Date

            while (-not $sync.OutboundStop) {
                $now = Get-Date
                if (($now - $lastPub).TotalSeconds -ge 2) {
                    $state = [string]$sync.RemoteState
                    if (-not $state) { $state = '{}' }
                    # 状态也签名：{"d": <原状态JSON>, "s": <HMAC>}，手机端校验后才显示
                    $h2 = New-Object System.Security.Cryptography.HMACSHA256
                    $h2.Key = [System.Text.Encoding]::UTF8.GetBytes($key)
                    $sig2 = ([BitConverter]::ToString($h2.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($state))) -replace '-', '').ToLower()
                    $h2.Dispose()
                    $env2 = '{"d":' + (ConvertTo-Json $state -Compress) + ',"s":"' + $sig2 + '"}'
                    $pkt = PubPkt $topicState $env2
                    $stream.Write($pkt, 0, $pkt.Length); $stream.Flush()
                    $lastPub = $now
                }
                if (($now - $lastPing).TotalSeconds -ge 30) {
                    $stream.Write([byte[]](0xC0, 0x00), 0, 2); $stream.Flush()
                    $lastPing = $now
                }
                if ($client.Available -gt 0) {
                    $p = ReadPkt $stream
                    if ($p -and $p.Type -eq 0x30) {
                        $msg = ParsePub $p.Payload
                        if ($msg -and $msg.Topic -eq $topicCmd) {
                            $cmd = $null
                            try { $cmd = $msg.Body | ConvertFrom-Json } catch { }
                            $valid = $false
                            if ($cmd -and $cmd.cmd) {
                                # 校验 HMAC-SHA256(key, cmd + '|' + ts)，防止别人乱发指令
                                try {
                                    $expect = ''
                                    $h = New-Object System.Security.Cryptography.HMACSHA256
                                    $h.Key = [System.Text.Encoding]::UTF8.GetBytes($key)
                                    $raw = [System.Text.Encoding]::UTF8.GetBytes(([string]$cmd.cmd + '|' + [string]$cmd.ts))
                                    $expect = ([BitConverter]::ToString($h.ComputeHash($raw)) -replace '-', '').ToLower()
                                    $h.Dispose()
                                    $epoch = New-Object datetime 1970,1,1,0,0,0,([DateTimeKind]::Utc)
                                    $nowTs = [double](([datetime]::UtcNow - $epoch).TotalSeconds)
                                    $age = [Math]::Abs($nowTs - [double]$cmd.ts)
                                    if ($expect -eq ([string]$cmd.sig).ToLower() -and $age -lt 300) { $valid = $true }
                                } catch { }
                            }
                            if (-not $valid -and $cmd -and $cmd.cmd) {
                                Log ('拒绝未签名指令: ' + $cmd.cmd)
                            }
                            if ($valid) {
                                $item = [ordered]@{ cmd = "$($cmd.cmd)"; i = "$($cmd.i)"; at = (Get-Date).ToString('HH:mm:ss') }
                                [void]$sync.RemoteQueue.Enqueue([pscustomobject]$item)
                            }
                        }
                    }
                }
                Start-Sleep -Milliseconds 150
            }
        } catch {
            $sync.OutboundOk = $false
            $sync.OutboundError = $_.Exception.Message
            Log ('异常: ' + $_.Exception.Message)
        } finally {
            try { if ($ssl) { $ssl.Dispose() } } catch { }
            try { if ($client) { $client.Close() } } catch { }
        }
        if (-not $sync.OutboundStop) { Log '5 秒后重连'; Start-Sleep -Seconds 5 }
    }
    $sync.OutboundOk = $false
}

function Start-Outbound {
    if ($script:mqttHandle) { return $true }
    $sync = $script:adbSync
    $broker = 'broker.emqx.io'
    $port = 8883
    try { if ($script:cfg.OutboundBroker) { $broker = [string]$script:cfg.OutboundBroker } } catch { }
    try { if ($script:cfg.OutboundPort) { $port = [int]$script:cfg.OutboundPort } } catch { }
    $uid = Get-OutboundUid
    $clientId = 'mmg-' + [guid]::NewGuid().ToString('N').Substring(0, 12)

    # 出站和局域网共用同一份状态/队列；局域网没开时也要能工作
    if (-not ($sync.PSObject.Properties.Name -contains 'RemoteState')) {
        $sync | Add-Member -NotePropertyName RemoteState -NotePropertyValue '{}' -Force
    }
    if (-not ($sync.PSObject.Properties.Name -contains 'RemoteQueue')) {
        $sync | Add-Member -NotePropertyName RemoteQueue -NotePropertyValue (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]') -Force
    }
    $sync | Add-Member -NotePropertyName OutboundStop -NotePropertyValue $false -Force
    $sync | Add-Member -NotePropertyName OutboundOk -NotePropertyValue $false -Force
    $sync | Add-Member -NotePropertyName OutboundError -NotePropertyValue '' -Force

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:mqttScript).AddArgument($sync).AddArgument($broker).AddArgument($port).AddArgument($uid).AddArgument($clientId).AddArgument($Root).AddArgument((Get-OutboundKey))
    $handle = $ps.BeginInvoke()

    $script:mqttPs = $ps
    $script:mqttRs = $rs
    $script:mqttHandle = $handle
    Write-Diag "出站通道已启动：$broker`:$port  uid=$uid"
    return $true
}

function Stop-Outbound {
    try { if ($script:adbSync) { $script:adbSync.OutboundStop = $true } } catch { }
    try { if ($script:mqttPs) { [void]$script:mqttPs.Stop() } } catch { }
    try { if ($script:mqttPs) { $script:mqttPs.Dispose() } } catch { }
    try { if ($script:mqttRs) { $script:mqttRs.Close(); $script:mqttRs.Dispose() } } catch { }
    $script:mqttPs = $null
    $script:mqttRs = $null
    $script:mqttHandle = $null
    Write-Diag '出站通道已停止'
}