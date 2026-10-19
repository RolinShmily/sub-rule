#Requires -Version 5.1
<#
递归扫描脚本所在的 singbox-dual443/ 目录及子目录中的 .json/.yaml；仅覆写识别出的双 443 服务端与客户端配置。
请只在本机填写下方参数：脚本和覆写后的配置都将包含明文凭据，切勿提交或公开分享。
首次覆写后仍可修改参数再次运行；按配置字段定位，不依赖旧占位符。
示例：pwsh -File .custom/singbox-dual443/Update-SingboxDual443.ps1 -Preview
      pwsh -File .custom/singbox-dual443/Update-SingboxDual443.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = '',
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigRoot)) {
    $ConfigRoot = $PSScriptRoot
}

# --- 只编辑这里；保持所有密钥为单引号字符串，内部单引号写成两个 '' ---
$Values = @{
    NodeAddress          = 'REPLACE_WITH_NODE_ADDRESS'           # VPS 域名或 IP，客户端连接地址
    Hy2Sni               = 'REPLACE_WITH_HY2_SNI'                # Hy2 证书覆盖的域名
    RealitySni           = 'REPLACE_WITH_REALITY_SNI'            # Reality 客户端 SNI / 服务端 server_name
    HandshakeHost        = 'REPLACE_WITH_REALITY_HANDSHAKE_HOST' # Reality 握手目标主机；可与 SNI 不同
    HandshakePort        = 443                                    # Reality 握手目标端口；Nginx 8443 时改为 8443
    Uuid                 = 'REPLACE_WITH_UUID'
    RealityPrivateKey    = 'REPLACE_WITH_REALITY_PRIVATE_KEY'    # 只写服务端
    RealityPublicKey     = 'REPLACE_WITH_REALITY_PUBLIC_KEY'     # 只写客户端
    ShortId              = 'REPLACE_WITH_REALITY_SHORT_ID'       # 2-16 位偶数长度十六进制
    Hy2Password          = 'REPLACE_WITH_HYSTERIA2_PASSWORD'
    CertificatePath      = 'REPLACE_WITH_CERTIFICATE_PATH'       # Debian fullchain.pem 绝对路径
    KeyPath              = 'REPLACE_WITH_KEY_PATH'               # Debian privkey.pem 绝对路径
    SingboxApiSecret     = 'REPLACE_WITH_SINGBOX_API_SECRET'     # 桌面端本机控制 API
    MihomoApiSecret      = 'REPLACE_WITH_MIHOMO_API_SECRET'      # Mihomo 本机控制 API
    
    # --- 可选：Headscale / Tailscale 自建组网直连（若不使用自建 Headscale，保持 '' 或占位符即可） ---
    HeadscaleServer      = 'REPLACE_WITH_HEADSCALE_SERVER'      # 例如 'hs.example.com'，为空时自动剔除对应域名规则
    HeadscaleBaseDomain  = 'REPLACE_WITH_HEADSCALE_BASE_DOMAIN'  # 例如 'tail.net'，为空时自动剔除对应域名规则
}

function Assert-Values {
    $optionalKeys = @('HeadscaleServer', 'HeadscaleBaseDomain')
    foreach ($key in $Values.Keys) {
        if ($key -eq 'HandshakePort' -or $key -in $optionalKeys) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$Values[$key]) -or
            [string]$Values[$key] -match '^REPLACE_WITH_') {
            throw "请先在脚本头部填写 $key；未修改任何配置。"
        }
    }
    $parsedUuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Values.Uuid, [ref]$parsedUuid)) {
        throw 'Uuid 必须是有效的 UUID；未修改任何配置。'
    }
    if ([string]$Values.ShortId -cnotmatch '^(?:[0-9a-fA-F]{2}){1,8}$') {
        throw 'ShortId 必须是 2-16 位偶数长度的十六进制字符串；未修改任何配置。'
    }
    if ([int]$Values.HandshakePort -lt 1 -or [int]$Values.HandshakePort -gt 65535) {
        throw 'HandshakePort 必须在 1-65535 之间；未修改任何配置。'
    }
    foreach ($key in @('RealityPrivateKey', 'RealityPublicKey')) {
        if ([string]$Values[$key] -cnotmatch '^[A-Za-z0-9_-]{43}$') {
            throw "$key 的格式不是 43 位 Base64URL；未修改任何配置。"
        }
    }
    foreach ($key in @('CertificatePath', 'KeyPath')) {
        if ([string]$Values[$key] -notmatch '^/') {
            throw "$key 必须是 Debian 上的绝对路径；未修改任何配置。"
        }
    }
    foreach ($key in @('NodeAddress', 'Hy2Sni', 'RealitySni', 'HandshakeHost')) {
        if ([string]$Values[$key] -match '[\s/]') {
            throw "$key 只能填主机名或 IP，不要带协议或路径；未修改任何配置。"
        }
    }
    foreach ($key in $optionalKeys) {
        $val = [string]$Values[$key]
        if (-not [string]::IsNullOrWhiteSpace($val) -and ($val -notmatch '^REPLACE_WITH_')) {
            if ($val -match '[\s/:]') {
                throw "$key 只能填主机名或域名（如 hs.example.com），不要带协议、路径或端口；未修改任何配置。"
            }
        }
    }
    foreach ($key in @('Hy2Password', 'SingboxApiSecret', 'MihomoApiSecret')) {
        if ([string]$Values[$key] -match '[\r\n]' -or ([string]$Values[$key]).Length -lt 16) {
            throw "$key 至少 16 位且不能包含换行；未修改任何配置。"
        }
    }
}

function Get-One([object[]]$Items, [string]$Description) {
    if ($Items.Count -ne 1) { throw "无法唯一定位 $Description（找到 $($Items.Count) 个）；未修改任何配置。" }
    return $Items[0]
}

function Assert-Field([object]$Object, [string]$Field, [string]$Description) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Field]) {
        throw "缺少 $Description.$Field；未修改任何配置。"
    }
}

function ConvertTo-YamlScalar([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Set-YamlField([string]$Block, [string]$Field, [int]$Spaces, [string]$Value) {
    $pattern = '(?m)^(' + (' ' * $Spaces) + [regex]::Escape($Field) + ':[ \t]*).*$'
    $rx = [regex]::new($pattern)
    if ($rx.Matches($Block).Count -ne 1) {
        throw "无法唯一定位 YAML 字段 $Field；未修改任何配置。"
    }
    $scalar = ConvertTo-YamlScalar $Value
    return $rx.Replace($Block, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $match.Groups[1].Value + $scalar
    })
}

function Set-YamlProxy([string]$Text, [string]$Name, [hashtable]$Fields) {
    $pattern = '(?ms)^(  - name: ' + [regex]::Escape($Name) + '[^\r\n]*\r?\n)(.*?)(?=^  - name: |^[^\s#]|\z)'
    $rx = [regex]::new($pattern)
    if ($rx.Matches($Text).Count -ne 1) {
        throw "无法唯一定位 Mihomo 节点 $Name；未修改任何配置。"
    }
    return $rx.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $block = $match.Groups[2].Value
        foreach ($field in $Fields.Keys) {
            $parts = $Fields[$field]
            $block = Set-YamlField $block $field ([int]$parts[0]) ([string]$parts[1])
        }
        return $match.Groups[1].Value + $block
    })
}

function Update-Server([string]$Path) {
    $cfg = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $vless = Get-One @($cfg.inbounds | Where-Object { $_.tag -eq 'VLESS-Vision-Reality-in' -and $_.type -eq 'vless' }) '服务端 Reality 入站'
    $hy2 = Get-One @($cfg.inbounds | Where-Object { $_.tag -eq 'hysteria-in' -and $_.type -eq 'hysteria2' }) '服务端 Hy2 入站'
    if ($vless.listen_port -ne 443 -or $hy2.listen_port -ne 443) {
        throw '服务端不再是 TCP/UDP 双 443 模板；未修改任何配置。'
    }
    foreach ($field in @('users', 'tls')) { Assert-Field $vless $field '服务端 Reality' }
    foreach ($field in @('users', 'tls')) { Assert-Field $hy2 $field '服务端 Hy2' }
    $user = Get-One @($vless.users) '服务端 Reality 用户'
    $hy2User = Get-One @($hy2.users) '服务端 Hy2 用户'
    Assert-Field $vless.tls 'reality' '服务端 Reality TLS'
    Assert-Field $vless.tls.reality 'handshake' '服务端 Reality'
    foreach ($field in @('certificate_path', 'key_path', 'server_name')) { Assert-Field $hy2.tls $field '服务端 Hy2 TLS' }
    $user.uuid = $Values.Uuid
    $vless.tls.server_name = $Values.RealitySni
    $vless.tls.reality.handshake.server = $Values.HandshakeHost
    $vless.tls.reality.handshake.server_port = [int]$Values.HandshakePort
    $vless.tls.reality.private_key = $Values.RealityPrivateKey
    $vless.tls.reality.short_id = @($Values.ShortId)
    $hy2User.password = $Values.Hy2Password
    $hy2.tls.server_name = $Values.Hy2Sni
    $hy2.tls.certificate_path = $Values.CertificatePath
    $hy2.tls.key_path = $Values.KeyPath
    return $cfg | ConvertTo-Json -Depth 100
}

function Update-SingboxClient([string]$Path) {
    $cfg = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $vless = Get-One @($cfg.outbounds | Where-Object { $_.tag -eq '自建-Reality' -and $_.type -eq 'vless' }) "$Path Reality 出站"
    $hy2 = Get-One @($cfg.outbounds | Where-Object { $_.tag -eq '自建-Hy2' -and $_.type -eq 'hysteria2' }) "$Path Hy2 出站"
    foreach ($field in @('tls', 'uuid', 'server')) { Assert-Field $vless $field "$Path Reality" }
    foreach ($field in @('tls', 'password', 'server')) { Assert-Field $hy2 $field "$Path Hy2" }
    Assert-Field $vless.tls 'reality' "$Path Reality TLS"
    $vless.server = $Values.NodeAddress
    $vless.uuid = $Values.Uuid
    $vless.tls.server_name = $Values.RealitySni
    $vless.tls.reality.public_key = $Values.RealityPublicKey
    $vless.tls.reality.short_id = $Values.ShortId
    $hy2.server = $Values.NodeAddress
    $hy2.password = $Values.Hy2Password
    $hy2.tls.server_name = $Values.Hy2Sni
    foreach ($service in @($cfg.services | Where-Object { $_.type -eq 'api' })) {
        Assert-Field $service 'secret' "$Path API"
        $service.secret = $Values.SingboxApiSecret
    }

    # 处理可选 Headscale / Tailscale 直连域名
    $hsDomains = @()
    foreach ($k in @('HeadscaleServer', 'HeadscaleBaseDomain')) {
        $v = [string]$Values[$k]
        if (-not [string]::IsNullOrWhiteSpace($v) -and ($v -notmatch '^REPLACE_WITH_')) {
            $hsDomains += $v.Trim()
        }
    }

    # 处理 dns.rules
    if ($null -ne $cfg.dns -and $null -ne $cfg.dns.rules) {
        $newDnsRules = @()
        foreach ($r in $cfg.dns.rules) {
            $isHsRule = $false
            if ($null -ne $r.domain_suffix) {
                foreach ($s in @($r.domain_suffix)) {
                    if ($s -match '^REPLACE_WITH_HEADSCALE_' -or ($hsDomains.Count -gt 0 -and $s -in $hsDomains)) {
                        $isHsRule = $true
                        break
                    }
                }
            }
            if ($isHsRule) {
                if ($hsDomains.Count -gt 0) {
                    $r.domain_suffix = @($hsDomains)
                    $newDnsRules += $r
                }
            } else {
                $newDnsRules += $r
            }
        }
        $cfg.dns.rules = $newDnsRules
    }

    # 处理 route.rules
    if ($null -ne $cfg.route -and $null -ne $cfg.route.rules) {
        $newRouteRules = @()
        foreach ($r in $cfg.route.rules) {
            $isHsRule = $false
            if ($null -ne $r.domain_suffix) {
                foreach ($s in @($r.domain_suffix)) {
                    if ($s -match '^REPLACE_WITH_HEADSCALE_' -or ($hsDomains.Count -gt 0 -and $s -in $hsDomains)) {
                        $isHsRule = $true
                        break
                    }
                }
            }
            if ($isHsRule) {
                if ($hsDomains.Count -gt 0) {
                    $r.domain_suffix = @($hsDomains)
                    $newRouteRules += $r
                }
            } else {
                $newRouteRules += $r
            }
        }
        $cfg.route.rules = $newRouteRules
    }

    return $cfg | ConvertTo-Json -Depth 100
}

function Update-Mihomo([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    $text = Set-YamlProxy $text '自建-Reality' @{
        server = @(4, $Values.NodeAddress)
        uuid = @(4, $Values.Uuid)
        servername = @(4, $Values.RealitySni)
        'public-key' = @(6, $Values.RealityPublicKey)
        'short-id' = @(6, $Values.ShortId)
    }
    $text = Set-YamlProxy $text '自建-Hy2' @{
        server = @(4, $Values.NodeAddress)
        password = @(4, $Values.Hy2Password)
        sni = @(4, $Values.Hy2Sni)
    }
    return Set-YamlField $text 'secret' 0 $Values.MihomoApiSecret
}

Assert-Values
$root = [System.IO.Path]::GetFullPath($ConfigRoot)
if (-not [System.IO.Directory]::Exists($root)) {
    throw "扫描目录不存在：$root；未修改任何配置。"
}

# 仅扫描当前根目录及子目录中的 JSON/YAML；按节点标签和配置段识别，其他文件跳过。
# 先在内存中完成全部目标文件的预检；字段缺失或模板结构不一致时不写入。
$updates = @{}
$skipped = 0
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @('.json', '.yaml') } |
    Sort-Object FullName)
foreach ($file in $files) {
    $path = $file.FullName
    $content = [System.IO.File]::ReadAllText($path)
    if ($file.Extension.ToLowerInvariant() -eq '.json') {
        $isServer = $content -match '"tag"\s*:\s*"(?:VLESS-Vision-Reality-in|hysteria-in)"'
        $isClient = $content -match '"tag"\s*:\s*"(?:自建-Reality|自建-Hy2)"'
        if ($isServer -and $isClient) { throw "文件同时包含服务端与客户端标签：$path；未修改任何配置。" }
        if ($isServer) { $updates[$path] = Update-Server $path }
        elseif ($isClient) { $updates[$path] = Update-SingboxClient $path }
        else { $skipped++ }
    }
    elseif ($content -match '(?m)^proxies:[ \t]*\r?$' -and
            $content -match '(?m)^  - name:[ \t]*(?:自建-Reality|自建-Hy2)[ \t]*\r?$') {
        $updates[$path] = Update-Mihomo $path
    }
    else { $skipped++ }
}
$paths = @($updates.Keys | Sort-Object)
if ($paths.Count -eq 0) { throw "扫描了 $($files.Count) 个 JSON/YAML，但未识别到双 443 配置；未修改任何文件。" }
foreach ($path in $paths) {
    if ($updates[$path] -match 'REPLACE_WITH_') {
        throw "配置中仍有未处理的占位符：$path；未修改任何配置。"
    }
}
if ($Preview) {
    Write-Host "扫描 $($files.Count) 个 JSON/YAML，识别 $($paths.Count) 个配置，跳过 $skipped 个；预览模式未写入，也未输出任何凭据。"
    foreach ($path in $paths) { Write-Host $path }
    return
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($path in $paths) {
    $temp = "$path.tmp-$([guid]::NewGuid().ToString('N'))"
    $backup = "$path.bak-$([guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.File]::WriteAllText($temp, $updates[$path] + "`n", $utf8)
        [System.IO.File]::Replace($temp, $path, $backup)
    }
    finally {
        if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
        if ([System.IO.File]::Exists($backup)) { [System.IO.File]::Delete($backup) }
    }
}
Write-Host "已原地覆写 $($paths.Count) 个配置文件；请在目标系统检查并测试，不要将脚本或含真实凭据的文件提交 Git。"
