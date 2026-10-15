# Qeet ID Kit - implementation of every Windows command.
#
# The windows/ commands call it: QeetIdKit.ps1 <command> [args].
# core/scripts/common.sh implements the same flow for macOS/Linux, and CI diffs
# the docker commands both issue (validate.yml, parity test). Keep the two in
# step.
#
# Environments: DEV, TEST, STAGING - separate Compose projects (core/compose.yaml)
# behind one shared edge (core/edge.compose.yaml) that alone owns 127.0.0.1:80. They
# can run at the same time.
#
# Windows PowerShell 5.1 and Constrained Language Mode compatible: cmdlets and
# core types only, ASCII only (5.1 reads BOM-less files as ANSI), no embedded
# double quotes in native-command arguments (5.1 strips them), and native
# failures are checked through $LASTEXITCODE, never through 'Stop'.

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# The kit root (this file is core\scripts\QeetIdKit.ps1).
$KitDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$KitVersion = (Get-Content -LiteralPath (Join-Path $KitDir 'VERSION') -TotalCount 1).Trim()
$Registry = if ($env:QEET_KIT_REGISTRY) { $env:QEET_KIT_REGISTRY } else { 'ghcr.io/qeetgroup' }
$StateRoot = if ($env:QEET_KIT_STATE_DIR) { $env:QEET_KIT_STATE_DIR }
             elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'QeetIdTestKit' }
             else { Join-Path $HOME '.qeet-id-test-kit' }
$WaitSeconds = if ($env:QEET_KIT_WAIT_SECONDS) { $env:QEET_KIT_WAIT_SECONDS } else { '300' }
$script:DebugMode = ($env:QEET_KIT_DEBUG -eq '1')

# Every environment the shared edge routes. The environments in THIS kit are
# those with a folder in environments\ (an environment exists when its folder
# exists), so TEST, STAGING and DEV can arrive one at a time.
$KnownEnvironments = @('dev', 'test', 'staging')
$Environments = @($KnownEnvironments | Where-Object { Test-Path -LiteralPath (Join-Path $KitDir "environments/$_/environment.env") })
$Services = @('postgres', 'mailpit', 'server', 'login', 'console', 'website', 'docs')
$Components = @('server', 'login', 'console', 'website', 'docs')
$LabelsFormat = '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}'

# ---------------------------------------------------------------- output ---

function Say([string]$Text) { Write-Host $Text }
function Title([string]$Text) { Write-Host ''; Write-Host $Text -ForegroundColor White; Write-Host '' }
function Ok([string]$Text) { Write-Host '[OK]   ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Warn([string]$Text) { Write-Host '[WARN] ' -ForegroundColor Yellow -NoNewline; Write-Host $Text }
function Fail([string]$Text) { Write-Host '[FAIL] ' -ForegroundColor Red -NoNewline; Write-Host $Text }
function Hint([string]$Text) { Write-Host ('       ' + $Text) -ForegroundColor DarkGray }
function Die([string]$Text, [string[]]$Hints = @()) {
    Fail $Text
    foreach ($h in $Hints) { Hint $h }
    exit 1
}
function Debug-Line([string]$Text) { if ($script:DebugMode) { Write-Host ('+ ' + $Text) -ForegroundColor DarkGray } }

# Runs docker with the given arguments; returns the exit code. Output is kept in
# $script:LastLog (shown on failure or with --verbose).
$script:LastLog = @()
function Invoke-Docker([string[]]$DockerArgs) {
    Debug-Line ('docker ' + ($DockerArgs -join ' '))
    $script:LastLog = @(& docker @DockerArgs 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    if ($script:DebugMode) { $script:LastLog | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray } }
    return $code
}
function Show-LastLog([int]$Lines = 15) {
    $script:LastLog | Select-Object -Last $Lines | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor DarkGray }
}
function Get-DockerText([string[]]$DockerArgs) {
    Debug-Line ('docker ' + ($DockerArgs -join ' '))
    $out = @(& docker @DockerArgs 2>$null | ForEach-Object { "$_" })
    return ($out -join "`n")
}

# --------------------------------------------------------------- options ---

$Opt = @{ Yes = $false; NoBrowser = $false; Reset = $false; Follow = $false; Build = $false; Tail = '200'
          Candidate = ''; Manifest = ''; Env = ''; Images = @() }
$Positional = @()
function Read-Options([string[]]$Arguments) {
    $i = 0
    while ($i -lt $Arguments.Count) {
        $a = $Arguments[$i]
        switch -CaseSensitive ($a) {
            { $_ -eq '-y' -or $_ -eq '--yes' } { $Opt.Yes = $true; break }
            '--no-browser' { $Opt.NoBrowser = $true; break }
            '--reset' { $Opt.Reset = $true; break }
            '--build' { $Opt.Build = $true; break }
            { $_ -eq '-f' -or $_ -eq '--follow' } { $Opt.Follow = $true; break }
            { $_ -eq '-n' -or $_ -eq '--tail' } { $i++; $Opt.Tail = $Arguments[$i]; break }
            '--candidate' { $i++; $Opt.Candidate = $Arguments[$i]; break }
            '--manifest' { $i++; $Opt.Manifest = $Arguments[$i]; break }
            '--image' { $i++; $Opt.Images += $Arguments[$i]; break }
            '--env' { $i++; $Opt.Env = $Arguments[$i]; break }
            { $_ -eq '-v' -or $_ -eq '--verbose' } { $script:DebugMode = $true; break }
            { $_ -eq '-h' -or $_ -eq '--help' } { Show-Usage; exit 0 }
            default {
                if ($a.StartsWith('-')) { Die "Unknown option: $a" @('Run with --help to see the options.') }
                $script:Positional += $a
            }
        }
        $i++
    }
}

function Show-Usage {
    Say "Qeet ID Kit $KitVersion - local environments: $(Get-EnvList)"
    Say ''
    Say 'Run from the qeet-id-kit folder:'
    foreach ($e in $Environments) { Say ('  {0,-34} start, update, stop, reset, rollback, status, logs' -f (Get-KitCmd $e '<command>')) }
    Say ('  {0,-34} login, doctor, cleanup, stop-all, update-kit' -f (Get-KitCmd 'tools' '<command>'))
}

# --------------------------------------------------------- small helpers ---

# Reads KEY from a KEY=VALUE file without executing it.
function Get-Kv([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line.StartsWith("$Key=")) {
            $v = $line.Substring($Key.Length + 1)
            if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            return $v
        }
    }
    return ''
}

# Writes text with LF line endings and no BOM (ASCII), as Compose expects.
function Write-TextFile([string]$Path, [string[]]$Lines) {
    $text = ($Lines -join "`n") + "`n"
    Set-Content -LiteralPath $Path -Value $text -Encoding Ascii -NoNewline
}

function Test-VersionAtLeast([string]$A, [string]$B) {
    $pa = ($A -split '-')[0] -split '\.'
    $pb = ($B -split '-')[0] -split '\.'
    for ($i = 0; $i -lt 3; $i++) {
        $x = 0; $y = 0
        if ($i -lt $pa.Count -and $pa[$i] -match '^\d+$') { $x = [int]$pa[$i] }
        if ($i -lt $pb.Count -and $pb[$i] -match '^\d+$') { $y = [int]$pb[$i] }
        if ($x -gt $y) { return $true }
        if ($x -lt $y) { return $false }
    }
    return $true
}

function Get-Label([string]$Env) { return $Env.ToUpper() }
# The command a tester types, e.g. .\windows\test\reset.cmd. <Group> is an
# environment or 'tools'.
function Get-KitCmd([string]$Group, [string]$Name) { return ".\windows\$Group\$Name.cmd" }
# 'test' / 'dev, test, staging' - the environments in this kit.
function Get-EnvList { return ($Environments -join ', ') }
# The single source of every browser-facing name: http://<svc>.<env>.id.qeet.localhost,
# except the website, which is the environment's bare zone (as id.qeet.in is).
function Get-KitHost([string]$Env, [string]$Svc) {
    if ($Svc -eq 'website') { return "http://$Env.id.qeet.localhost" }
    return "http://$Svc.$Env.id.qeet.localhost"
}
function Get-ServiceName([string]$Svc) {
    switch ($Svc) {
        'postgres' { 'PostgreSQL' } 'mailpit' { 'Mail inbox' } 'server' { 'Qeet ID Server' }
        'login' { 'Login' } 'console' { 'Console' } 'website' { 'Website' } 'docs' { 'Docs' } default { $Svc }
    }
}

function Assert-Env([string]$Env) {
    if (-not $Env) { Die "Choose an environment: $(Get-EnvList)." }
    if ($Environments -cnotcontains $Env) { Die "Unknown environment '$Env'. This kit has: $(Get-EnvList)." }
}
function Assert-ReleaseEnv([string]$Env) {
    Assert-Env $Env
    if ($Env -eq 'dev') { Die 'DEV does not follow release candidates.' @("Use $(Get-KitCmd 'dev' 'start') --build (it builds DEV's images from your working trees).") }
}

function Open-Url([string]$Url) {
    if ($Opt.NoBrowser) { return }
    if ((Get-Kv (Join-Path $KitDir 'settings/.env') 'QEET_KIT_OPEN_BROWSER') -eq 'false') { return }
    if ($env:OS -eq 'Windows_NT') { Start-Process $Url }
}

function Confirm-Typed([string]$Expected, [string]$Prompt) {
    if ($Opt.Yes) { return $true }
    $reply = Read-Host $Prompt
    return ($reply -eq $Expected)
}

# ----------------------------------------------------------------- state ---

function Get-StateDir([string]$Env) { return (Join-Path $StateRoot $Env) }
function Test-VolumeExists([string]$Env) { & docker volume inspect "qeet-id-$Env-postgres" *> $null; return ($LASTEXITCODE -eq 0) }
function Test-ProjectRunning([string]$Env) {
    $ids = Get-DockerText @('ps', '-q', '--filter', "label=com.docker.compose.project=qeet-id-$Env")
    return [bool]$ids
}
function Test-AnyEnvRunning { foreach ($e in $Environments) { if (Test-ProjectRunning $e) { return $true } }; return $false }
function Test-SecretsPresent([string]$Env) {
    $d = Join-Path (Get-StateDir $Env) 'secrets'
    foreach ($f in @('postgres.env', 'server.env', 'console.env')) {
        $p = Join-Path $d $f
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        if ((Get-Item -LiteralPath $p).Length -eq 0) { return $false }
    }
    return $true
}

$script:KitImage = ''
function Get-KitImage {
    if (-not $script:KitImage) {
        $script:KitImage = Get-Kv (Join-Path $KitDir 'kit.lock') 'QEET_KIT_IMAGE'
        if (-not $script:KitImage) { $script:KitImage = 'qeet-id-test-kit:dev' }
    }
    return $script:KitImage
}
function Confirm-KitImage {
    if ((Get-KitImage) -eq 'qeet-id-test-kit:dev') {
        $code = Invoke-Docker @('build', '-q', '-t', 'qeet-id-test-kit:dev', '-f', (Join-Path $KitDir 'core/image/Dockerfile'), $KitDir)
        if ($code -ne 0) { Show-LastLog; Die 'Could not build the test-kit tools image.' }
    }
}

function Set-ComposeEnv([string]$Env) {
    $env:QEET_KIT_ENV = $Env
    $env:QEET_KIT_STATE_DIR = $StateRoot
    $env:QEET_KIT_IMAGE = Get-KitImage
    if ($env:OS -eq 'Windows_NT') { $env:QEET_KIT_UID = '0'; $env:QEET_KIT_GID = '0' }
    else { $env:QEET_KIT_UID = (& id -u); $env:QEET_KIT_GID = (& id -g) }
}
function Get-ComposeArgs([string]$Env, [string]$Rel, [string[]]$Rest) {
    return @('compose', '--project-name', "qeet-id-$Env", '--project-directory', $KitDir,
             '--file', (Join-Path $KitDir 'core/compose.yaml'), '--env-file', (Join-Path $KitDir "environments/$Env/environment.env"),
             '--env-file', $Rel) + $Rest
}
# Every environment Compose call goes through here; returns the exit code.
function Invoke-Compose([string]$Env, [string]$Rel, [string[]]$Rest) {
    Set-ComposeEnv $Env
    return (Invoke-Docker (Get-ComposeArgs $Env $Rel $Rest))
}
function Get-ComposeText([string]$Env, [string]$Rel, [string[]]$Rest) {
    Set-ComposeEnv $Env
    return (Get-DockerText (Get-ComposeArgs $Env $Rel $Rest))
}
function Get-EdgeArgs([string[]]$Rest) {
    return @('compose', '--project-name', 'qeet-id-edge', '--project-directory', $KitDir,
             '--file', (Join-Path $KitDir 'core/edge.compose.yaml')) + $Rest
}

# ------------------------------------------------------------------ edge ---

function Test-EdgeRunning { return [bool](Get-DockerText @('ps', '-q', '--filter', 'label=com.docker.compose.project=qeet-id-edge')) }
function Get-Port80Owner {
    # Returns the listening process id, 0 if port 80 is free, -1 if unknown.
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $c = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return [int]$c.OwningProcess } else { return 0 }
    }
    return 0
}
function Assert-Port80Free {
    $owner = Get-Port80Owner
    if ($owner -gt 0) {
        $hints = @('The test kit serves http://*.id.qeet.localhost on port 80. Stop the other program and try again.')
        if ($owner -eq 4) { $hints += 'Port 80 is held by Windows (http.sys): typically IIS / World Wide Web Publishing Service. Stop it in Services, or ask IT.' }
        else { $hints += "The program has process id $owner (see Task Manager > Details)." }
        Die 'Port 80 is already in use by another program.' $hints
    }
}

function Start-Edge {
    foreach ($e in $KnownEnvironments) {
        & docker network inspect "qeet-id-$e-edge" *> $null
        if ($LASTEXITCODE -ne 0) {
            $code = Invoke-Docker @('network', 'create', '--label', 'in.qeet.test-kit=edge', "qeet-id-$e-edge")
            if ($code -ne 0) { Show-LastLog; Die "Could not create the Docker network qeet-id-$e-edge." }
        }
    }
    if (-not (Test-EdgeRunning)) { Assert-Port80Free }
    $code = Invoke-Docker (Get-EdgeArgs @('up', '-d', '--wait', '--wait-timeout', '60'))
    if ($code -ne 0) {
        Show-LastLog
        # Doctor cannot see a registry rate limit on the edge's image; say so here.
        if ((Get-RegistryErrorCode ($script:LastLog -join "`n")) -eq 15) { Stop-OnRegistryFailure 15 '' }
        Die 'The local edge (port 80) did not start.' @("Run Doctor: $(Get-KitCmd 'tools' 'doctor')")
    }
}

function Stop-EdgeIfIdle {
    if (Test-AnyEnvRunning) { return }
    if (-not (Test-EdgeRunning)) { return }
    if ((Invoke-Docker (Get-EdgeArgs @('down'))) -eq 0) { Ok 'Stopped the local edge (no environment is running)' }
}

# --------------------------------------------------------------- release ---

$ReleaseLineRe = '^QEET_ID_[A-Z0-9_]+=[A-Za-z0-9@:/._+,-]*$'
$PinnedImageRe = '^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(:[A-Za-z0-9._-]+)?@sha256:[0-9a-f]{64}$'

# QEET_ID_<COMPONENT>_IMAGE for every component.
function Get-ImageKeys { return @($Components | ForEach-Object { "QEET_ID_$($_.ToUpper())_IMAGE" }) }

function Test-Release([string]$Path, [switch]$AllowUnpinned) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $lines = @(Get-Content -LiteralPath $Path | Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) { return $false }
    foreach ($l in $lines) { if ($l -cnotmatch $ReleaseLineRe) { Debug-Line "bad release line: $l"; return $false } }
    if ((Get-Kv $Path 'QEET_ID_MANIFEST_SCHEMA') -ne '1') { return $false }
    foreach ($k in (@('QEET_ID_VERSION', 'QEET_ID_DATA_EPOCH', 'QEET_ID_MIN_KIT_VERSION', 'QEET_ID_SERVER_SCHEMA_VERSION') + (Get-ImageKeys))) {
        if (-not (Get-Kv $Path $k)) { Debug-Line "release is missing $k"; return $false }
    }
    if ($AllowUnpinned) { return $true }
    foreach ($k in (Get-ImageKeys)) {
        if ((Get-Kv $Path $k) -cnotmatch $PinnedImageRe) { Debug-Line "$k is not digest-pinned"; return $false }
    }
    return $true
}

# 10 = authentication, 11 = not found, 12 = other, 14 = Docker's credential
# helper is broken, 15 = rate limited.
function Get-RegistryErrorCode([string]$Text) {
    if ($Text -match 'error getting credentials|docker-credential-[a-z-]+') { return 14 }
    if ($Text -match 'toomanyrequests|too many requests|rate exceeded|rate limit') { return 15 }
    if ($Text -match 'unauthorized|denied|authentication required|no basic auth|forbidden|403') { return 10 }
    if ($Text -match 'not found|manifest unknown|does not exist|404') { return 11 }
    return 12
}

# Pulls a release manifest image and writes its fields; returns 0 or an error code.
function Get-Release([string]$Ref, [string]$Out) {
    $code = Invoke-Docker @('pull', '-q', $Ref)
    if ($code -ne 0) { return (Get-RegistryErrorCode ($script:LastLog -join "`n")) }
    $labels = Get-DockerText @('image', 'inspect', '--format', $LabelsFormat, $Ref)
    $fields = @($labels -split "`n" | Where-Object { $_.StartsWith('qeet.release.') } |
                ForEach-Object { $_.Substring('qeet.release.'.Length) } | Sort-Object)
    Write-TextFile "$Out.tmp" $fields
    if (Test-Release "$Out.tmp") { Move-Item -LiteralPath "$Out.tmp" -Destination $Out -Force; return 0 }
    Remove-Item -LiteralPath "$Out.tmp" -Force -ErrorAction SilentlyContinue
    return 13
}

# The package name of an image reference: ghcr.io/qeetgroup/qeet-id-server:sha-1@sha256:... -> qeet-id-server
function Get-ImageName([string]$Ref) {
    $n = ($Ref -split '@')[0]
    $i = $n.LastIndexOf(':'); if ($i -gt $n.LastIndexOf('/')) { $n = $n.Substring(0, $i) }
    return $n.Substring($n.LastIndexOf('/') + 1)
}

function Write-AccessProblem([int]$Code, [string]$What) {
    switch ($Code) {
        10 { Fail "This GitHub sign-in cannot read $What." }
        11 { Fail "$What was not found in the registry." }
        13 { Fail "The release record $What is unreadable or needs a newer Qeet ID Kit." }
        14 { Fail "Docker's sign-in helper is not working (while checking $What)." }
        15 { Fail "The registry is limiting downloads right now (while checking $What) - try again in a minute." }
        default { Fail "Could not check ${What}: the registry did not answer." }
    }
}

# Can this computer's sign-in read everything Start downloads? For every
# environment in this kit: its release channel and each image the candidate
# names; plus the kit image when kit.lock pins one. Metadata only (docker
# manifest inspect); nothing is downloaded. Returns the number of problems.
function Test-Access {
    $problems = 0
    $tmp = Join-Path $StateRoot 'access-release.env'
    foreach ($e in $Environments) {
        $channel = Get-Kv (Join-Path $KitDir "environments/$e/environment.env") 'QEET_KIT_CHANNEL'
        if (-not $channel) { continue }
        $rc = Get-Release "$Registry/qeet-id-release:$channel" $tmp
        if ($rc -eq 11) { Warn "No $(Get-Label $e) candidate has been published yet (channel '$channel')"; continue }
        if ($rc -ne 0) { Write-AccessProblem $rc "qeet-id-release:$channel"; $problems++; continue }
        $n = 0; $good = 0
        foreach ($k in (Get-ImageKeys)) {
            $ref = Get-Kv $tmp $k
            $n++
            if ((Invoke-Docker @('manifest', 'inspect', $ref)) -eq 0) { $good++ }
            else { Write-AccessProblem (Get-RegistryErrorCode ($script:LastLog -join "`n")) (Get-ImageName $ref); $problems++ }
        }
        if ($good -eq $n) { Ok "Can download $(Get-Label $e) $(Get-Kv $tmp 'QEET_ID_VERSION') (all $n images)" }
    }
    if (Test-Path -LiteralPath (Join-Path $KitDir 'kit.lock')) {
        if ((Invoke-Docker @('manifest', 'inspect', (Get-KitImage))) -eq 0) { Ok 'Can download the kit image' }
        else { Write-AccessProblem (Get-RegistryErrorCode ($script:LastLog -join "`n")) (Get-ImageName (Get-KitImage)); $problems++ }
    }
    Remove-Item -LiteralPath $tmp, "$tmp.tmp" -Force -ErrorAction SilentlyContinue
    return $problems
}

function Stop-OnRegistryFailure([int]$Code, [string]$Name) {
    switch ($Code) {
        10 { Die "Unable to download Qeet ID: this computer's GitHub sign-in cannot read the Qeet ID packages." @(
                "Run Login again: $(Get-KitCmd 'tools' 'login')",
                'Use a CLASSIC token (github.com/settings/tokens > Tokens (classic)) with read:packages - fine-grained tokens do not work with GitHub Packages.',
                'Sign in with your own GitHub account, and make sure it has been given access to the qeetgroup packages (ask your team lead).') }
        14 { Die "Docker's sign-in helper is not working, so Docker cannot use your GitHub sign-in." @(
                'Restart Docker Desktop and try again. If it keeps happening, reinstall Docker Desktop.') }
        15 { Die 'The image registry is limiting downloads right now (too many requests).' @('Wait a minute, then run the same command again.') }
        11 { Die "No Qeet ID release candidate is published as '$Name' yet." @('Ask the release manager to publish one.') }
        13 { Die "The release manifest for '$Name' is invalid or needs a newer Qeet ID Kit." @("Run Update Kit: $(Get-KitCmd 'tools' 'update-kit')   then try again.") }
        default { Die "Cannot reach the image registry ($Registry)." @('Check your internet connection or proxy, then try again. Run Doctor for details: ' + (Get-KitCmd 'tools' 'doctor')) }
    }
}

# "<version> <dirty>" from this environment's database, or '' for a fresh one.
function Get-DbSchema([string]$Env, [string]$Rel) {
    $code = Invoke-Compose $Env $Rel @('up', '-d', '--wait', '--wait-timeout', '120', 'postgres')
    if ($code -ne 0) { return $null }
    $out = Get-ComposeText $Env $Rel @('exec', '-T', 'postgres', 'psql', '-U', 'qeet_id', '-d', "qeet_id_$Env", '-tA',
                                       '-c', 'SELECT version || chr(32) || dirty FROM schema_migrations')
    return (($out -split "`n") | Select-Object -First 1)
}

# ------------------------------------------------------------ DEV images ---

function Get-DevSource([string]$C) {
    $v = Get-Kv (Join-Path $KitDir 'settings/.env') ('QEET_KIT_DEV_' + $C.ToUpper() + '_SRC')
    if ($v) { return $v }
    $candidate = Join-Path (Split-Path -Parent $KitDir) "qeet-id-$C"
    if (Test-Path -LiteralPath (Join-Path $candidate 'Dockerfile')) { return $candidate }
    return ''
}
function Get-ImageLabel([string]$Image, [string]$Key) {
    $labels = Get-DockerText @('image', 'inspect', '--format', $LabelsFormat, $Image)
    foreach ($l in ($labels -split "`n")) { if ($l.StartsWith("$Key=")) { return $l.Substring($Key.Length + 1) } }
    return ''
}
function Get-UtcStamp { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function New-DevRelease([string]$Out) {
    $cur = Join-Path (Get-StateDir 'dev') 'current.env'
    if (-not $Opt.Build -and $Opt.Images.Count -eq 0 -and -not (Test-Path -LiteralPath $cur)) {
        Die 'DEV has no images yet.' @('Build them from your working trees: ' + (Get-KitCmd 'dev' 'start') + ' --build',
                                       "or choose images: QeetIdKit.ps1 start dev --image <component>=<ref> for each of: $($Components -join ' ')")
    }
    $lines = @('QEET_ID_MANIFEST_SCHEMA=1', 'QEET_ID_VERSION=dev', 'QEET_ID_RELEASE=dev', 'QEET_ID_DATA_EPOCH=0',
               "QEET_ID_MIN_KIT_VERSION=$KitVersion", "QEET_ID_CREATED_AT=$(Get-UtcStamp)")
    foreach ($c in $Components) {
        $uc = $c.ToUpper(); $pick = ''; $rev = ''; $schema = ''
        foreach ($item in $Opt.Images) { if ($item.StartsWith("$c=")) { $pick = $item.Substring($c.Length + 1) } }
        if ($pick) {
            $ref = $pick
            & docker image inspect $ref *> $null
            if ($LASTEXITCODE -ne 0) {
                if ((Invoke-Docker @('pull', '-q', $ref)) -ne 0) { Show-LastLog; Die "DEV: cannot use image $ref for $c." }
            }
            $rev = Get-ImageLabel $ref 'org.opencontainers.image.revision'
            if ($c -eq 'server') { $schema = Get-ImageLabel $ref 'in.qeet.id.schema-version' }
        } elseif ($Opt.Build) {
            $src = Get-DevSource $c
            if (-not $src) { Die "DEV: cannot find the qeet-id-$c source." @("Set QEET_KIT_DEV_${uc}_SRC in settings\.env to its folder.") }
            $rev = (& git -C $src rev-parse HEAD 2>$null)
            if (-not $rev) { $rev = 'unknown' }
            $changes = & git -C $src status --porcelain 2>$null
            if ($changes) { $rev = "$rev-dirty" }
            $ref = "qeet-id-${c}:dev"
            Say "Building $c from $src ..."
            if ($c -eq 'server') {
                $code = Invoke-Docker @('build', '-t', $ref, '--build-arg', 'VERSION=dev', '--build-arg', "COMMIT=$rev",
                                        '--build-arg', "DATE=$(Get-UtcStamp)", $src)
                $migrations = Join-Path $src 'internal/platform/database/migrations'
                $nums = @(Get-ChildItem -LiteralPath $migrations -Filter '*.up.sql' -ErrorAction SilentlyContinue |
                          ForEach-Object { if ($_.Name -match '^0*(\d+)_') { [int]$Matches[1] } } | Sort-Object)
                if ($nums.Count -gt 0) { $schema = [string]$nums[-1] }
            } else {
                $code = Invoke-Docker @('build', '-t', $ref, '--build-arg', 'VERSION=dev', '--build-arg', "REVISION=$rev", $src)
            }
            if ($code -ne 0) { Show-LastLog 25; Die "DEV: building $c failed." }
            Ok "Built $ref"
        } else {
            $ref = Get-Kv $cur "QEET_ID_${uc}_IMAGE"
            $rev = Get-Kv $cur "QEET_ID_${uc}_REVISION"
            if ($c -eq 'server') { $schema = Get-Kv $cur 'QEET_ID_SERVER_SCHEMA_VERSION' }
        }
        if (-not $rev) { $rev = 'unknown' }
        $lines += "QEET_ID_${uc}_IMAGE=$ref"
        $lines += "QEET_ID_${uc}_REVISION=$rev"
        if ($c -eq 'server') { if (-not $schema) { $schema = '0' }; $lines += "QEET_ID_SERVER_SCHEMA_VERSION=$schema" }
    }
    Write-TextFile $Out ($lines | Sort-Object)
    if (-not (Test-Release $Out -AllowUnpinned)) { Die 'DEV: an image reference is not usable.' @('Run with --verbose for details.') }
}

# ---------------------------------------------------------------- guards ---

# The keys settings\.env may set: every "KEY=" (or "# KEY=") line of
# settings\.example.env. Its reference blocks list the other keys without "=".
function Get-LocalEnvKeys {
    $example = Join-Path $KitDir 'settings/.example.env'
    $keys = @()
    if (-not (Test-Path -LiteralPath $example)) { return $keys }
    foreach ($line in (Get-Content -LiteralPath $example)) {
        if ($line -cmatch '^#? ?([A-Z][A-Z0-9_]*)=') { $keys += $Matches[1] }
    }
    return $keys
}

function Assert-LocalEnv {
    $f = Join-Path $KitDir 'settings/.env'
    if (-not (Test-Path -LiteralPath $f)) { return }
    $keys = @(Get-LocalEnvKeys)
    if ($keys.Count -eq 0) {
        Die 'settings\.example.env is missing from this kit folder.' @('Extract the kit ZIP again (keep your settings\.env), then try again.')
    }
    foreach ($line in (Get-Content -LiteralPath $f)) {
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $key = ($line -split '=', 2)[0]
        if ($keys -cnotcontains $key) {
            Die "settings\.env contains '$key', which the kit does not accept." @('The kit sets it for each environment, or it is not a Qeet ID setting (see the reference at the end of settings\.example.env).',
                'The keys you can set are the KEY= lines in settings\.example.env. Remove the line and try again.')
        }
    }
}

function Assert-Prerequisites {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Die 'Docker is not installed.' @('Install Docker Desktop (https://www.docker.com/products/docker-desktop/), start it, and try again.')
    }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { Die 'Docker Desktop is installed but is not running.' @('Start Docker Desktop and try again.') }
    if ((Get-DockerText @('info', '--format', '{{.OSType}}')).Trim() -ne 'linux') {
        Die 'Docker is running Windows containers.' @('Switch Docker Desktop to Linux containers: right-click the Docker icon > Switch to Linux containers, then try again.')
    }
    $v = (Get-DockerText @('compose', 'version', '--short')).Trim().TrimStart('v')
    if (-not $v) { Die 'Docker Compose is not available.' @('Update Docker Desktop to a current version.') }
    if (-not (Test-VersionAtLeast $v '2.24.0')) { Die "Docker Compose $v is too old (2.24 or newer is required)." @('Update Docker Desktop.') }
}

# ----------------------------------------------------------------- start ---

function Stop-Project([string]$Env) {
    $cur = Join-Path (Get-StateDir $Env) 'current.env'
    if (Test-Path -LiteralPath $cur) {
        if ((Invoke-Compose $Env $cur @('down', '--remove-orphans')) -eq 0) { return }
    }
    $ids = @((Get-DockerText @('ps', '-aq', '--filter', "label=com.docker.compose.project=qeet-id-$Env")) -split "`n" | Where-Object { $_ })
    if ($ids.Count -gt 0) { [void](Invoke-Docker (@('rm', '-f') + $ids)) }
}

function Show-StartFailure([string]$Env, [string]$Rel) {
    $logs = Get-ComposeText $Env $Rel @('logs', '--no-color', '--no-log-prefix', '--tail', '200', 'server')
    $reason = ''
    if ($logs -match 'migrations failed') { $reason = 'migration' } elseif ($logs -match 'refusing to start') { $reason = 'config' }
    foreach ($svc in $Services) {
        $id = ((Get-ComposeText $Env $Rel @('ps', '-aq', $svc)) -split "`n" | Select-Object -First 1)
        if (-not $id) { Fail "$(Get-ServiceName $svc) did not start."; continue }
        $st = (Get-DockerText @('inspect', '--format', '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}', $id)).Trim()
        if ($st -eq 'running|healthy' -or $st -eq 'running|') { Ok "$(Get-ServiceName $svc) healthy" }
        else { Fail "$(Get-ServiceName $svc) failed its health check ($(($st -split '\|')[0]))." }
    }
    if ($reason -eq 'migration') {
        Say ''
        Fail "Database migrations for this release failed, so $(Get-Label $Env) is not ready."
        Hint "Run Logs ($(Get-KitCmd $Env 'logs') server) for the error and send it to the Qeet ID team."
        Hint "If the database is older than this release allows, Reset ($(Get-KitCmd $Env 'reset')) starts fresh."
    } elseif ($reason -eq 'config') {
        Say ''
        Fail 'Qeet ID Server refused its configuration:'
        # The newest "refusing to start" line and the "  - reason" lines after it.
        $block = @(); $inReason = $false
        foreach ($line in ($logs -split "`n")) {
            if ($line -match 'refusing to start') { $block = @($line); $inReason = $true }
            elseif ($inReason -and $line.StartsWith('  - ')) { $block += $line }
            else { $inReason = $false }
        }
        $block | ForEach-Object { Hint $_ }
    }
    [void](Invoke-Compose $Env $Rel @('stop', 'server'))
    Say ''
    Hint "Run Logs ($(Get-KitCmd $Env 'logs')) for diagnostics."
    exit 1
}

function Test-Routes([string]$Env) {
    $bad = $false
    foreach ($svc in @('api', 'login', 'console', 'website', 'docs', 'mail')) {
        $path = switch ($svc) { 'api' { '/readyz' } 'mail' { '/livez' } default { '/healthz' } }
        $kitHost = (Get-KitHost $Env $svc).Substring(7)
        $code = Invoke-Docker (Get-EdgeArgs @('exec', '-T', 'edge', 'wget', '-Y', 'off', '-q', '-O', '/dev/null',
                                              '--header', "Host: $kitHost", "http://127.0.0.1$path"))
        if ($code -ne 0) { Fail "$(Get-KitHost $Env $svc) does not answer through the local edge."; $bad = $true }
    }
    if ($bad) { Die "$(Get-Label $Env) started but is not reachable." @("Run Doctor ($(Get-KitCmd 'tools' 'doctor')) and Logs ($(Get-KitCmd $Env 'logs') edge).") }
}

function Show-Ready([string]$Env, [string]$Rel) {
    Say ''
    if ($Env -eq 'dev') { Ok 'Qeet ID (local build) is ready in DEV.' }
    else { Ok "Qeet ID $(Get-Kv $Rel 'QEET_ID_VERSION') is ready in $(Get-Label $Env)." }
    Say ''
    Say "  Console        $(Get-KitHost $Env 'console')"
    Say "  Hosted login   $(Get-KitHost $Env 'login')"
    Say "  API            $(Get-KitHost $Env 'api')"
    Say "  Mail inbox     $(Get-KitHost $Env 'mail')   (verification codes, magic links, invites)"
    Say "  Website        $(Get-KitHost $Env 'website')"
    Say "  Docs           $(Get-KitHost $Env 'docs')"
    Say ''
    Say "  Use Google Chrome or Microsoft Edge. Data is kept until you run Reset ($(Get-KitCmd $Env 'reset'))."
}

# Mode: channel | local | rollback | installed | dev
function Start-Release([string]$Env, [string]$Rel, [string]$Mode) {
    $sd = Get-StateDir $Env
    $cur = Join-Path $sd 'current.env'; $prev = Join-Path $sd 'previous.env'
    $fresh = $true

    $min = Get-Kv $Rel 'QEET_ID_MIN_KIT_VERSION'
    if (-not (Test-VersionAtLeast $KitVersion $min)) {
        Die "Qeet ID $(Get-Kv $Rel 'QEET_ID_VERSION') needs Qeet ID Kit $min or newer (this is $KitVersion)." @("Run Update Kit: $(Get-KitCmd 'tools' 'update-kit')   Your environments and data are kept.")
    }
    if (Test-VolumeExists $Env) {
        $fresh = $false
        if (-not (Test-SecretsPresent $Env)) {
            Die "Existing $(Get-Label $Env) data was found, but its keys are missing from $sd\secrets." @(
                "The data cannot be opened without them. Run Reset ($(Get-KitCmd $Env 'reset')) to start fresh.")
        }
        $epoch = Get-Kv (Join-Path $sd 'data.env') 'QEET_KIT_DATA_EPOCH'
        if ($Env -ne 'dev' -and $epoch -and $epoch -ne (Get-Kv $Rel 'QEET_ID_DATA_EPOCH')) {
            Die "Qeet ID $(Get-Kv $Rel 'QEET_ID_VERSION') cannot use your existing $(Get-Label $Env) data (data format $epoch -> $(Get-Kv $Rel 'QEET_ID_DATA_EPOCH'))." @(
                "Nothing was changed. Run Reset ($(Get-KitCmd $Env 'reset')) to start fresh with this release.")
        }
        $db = Get-DbSchema $Env $Rel
        if ($null -eq $db) { Show-LastLog; Die 'PostgreSQL did not start for the compatibility check.' }
        if ($db) {
            $parts = $db.Trim() -split ' '
            if ($parts[1] -eq 't' -or $parts[1] -eq 'true') {
                Die "The last database migration in $(Get-Label $Env) did not finish, so the data is in an unknown state." @("Run Reset ($(Get-KitCmd $Env 'reset')) to start fresh.")
            }
            $cand = Get-Kv $Rel 'QEET_ID_SERVER_SCHEMA_VERSION'
            if ($cand -match '^\d+$' -and $parts[0] -match '^\d+$' -and [int]$cand -gt 0 -and [int]$cand -lt [int]$parts[0]) {
                Die "Qeet ID $(Get-Kv $Rel 'QEET_ID_VERSION') is older than your $(Get-Label $Env) data (schema $($parts[0]), release supports $cand)." @(
                    "Nothing was changed. Reset ($(Get-KitCmd $Env 'reset')) starts fresh with this release.")
            }
        }
    }

    if (-not (Test-SecretsPresent $Env)) {
        Confirm-KitImage
        New-Item -ItemType Directory -Force -Path (Join-Path $sd 'secrets') | Out-Null
        if ((Invoke-Compose $Env $Rel @('--profile', 'tools', 'run', '--rm', 'keygen')) -ne 0) {
            Show-LastLog; Die "Could not generate $(Get-Label $Env)'s local secrets."
        }
        Ok 'Generated local test-only secrets'
    }

    if ($Mode -eq 'channel') {
        if ((Invoke-Compose $Env $Rel @('pull', '--quiet')) -ne 0) {
            Stop-OnRegistryFailure (Get-RegistryErrorCode ($script:LastLog -join "`n")) (Get-Kv $Rel 'QEET_ID_VERSION')
        }
        Ok 'Images ready'
    }

    Start-Edge
    if ($fresh) { Say "Starting $(Get-Label $Env) (first start applies every database migration - about a minute)..." }
    else { Say "Starting $(Get-Label $Env)..." }
    if ((Invoke-Compose $Env $Rel @('up', '-d', '--remove-orphans', '--wait', '--wait-timeout', $WaitSeconds)) -ne 0) {
        Say ''
        Show-StartFailure $Env $Rel
    }
    Ok 'Database ready, migrations completed'
    foreach ($svc in @('server', 'login', 'console', 'website', 'docs', 'mailpit')) { Ok "$(Get-ServiceName $svc) healthy" }
    Test-Routes $Env

    if ((Get-ComposeText $Env $Rel @('logs', '--no-color', '--no-log-prefix', 'server')) -notmatch 'notifier: email via SMTP') {
        Warn "Email is not being delivered to the Mail inbox; verification codes will not arrive. Run Logs ($(Get-KitCmd $Env 'logs') server)."
    }

    if ($fresh) {
        $seed = Get-Kv $Rel 'QEET_ID_SEED_ARGS'
        if ((Get-Kv (Join-Path $KitDir "environments/$Env/environment.env") 'QEET_KIT_SEED') -eq 'true' -and $seed) {
            if ((Invoke-Compose $Env $Rel (@('run', '--rm', '--no-deps', 'server') + ($seed -split ','))) -ne 0) {
                Show-LastLog; Die 'The release''s seed step failed.'
            }
            Ok 'Loaded the release''s synthetic seed data'
        } else {
            Ok 'Fresh environment: empty baseline - create accounts through Sign up'
        }
    }

    if ($Env -ne 'dev' -and (Test-Path -LiteralPath $cur) -and (Get-Kv $cur 'QEET_ID_VERSION') -ne (Get-Kv $Rel 'QEET_ID_VERSION')) {
        Copy-Item -LiteralPath $cur -Destination $prev -Force
    }
    if ($Rel -ne $cur) { Copy-Item -LiteralPath $Rel -Destination $cur -Force }
    $db = ((Get-ComposeText $Env $cur @('exec', '-T', 'postgres', 'psql', '-U', 'qeet_id', '-d', "qeet_id_$Env", '-tA',
                                        '-c', 'SELECT version FROM schema_migrations')) -split "`n" | Select-Object -First 1)
    Write-TextFile (Join-Path $sd 'data.env') @("QEET_KIT_DATA_EPOCH=$(Get-Kv $cur 'QEET_ID_DATA_EPOCH')", "QEET_KIT_DB_SCHEMA=$db")
    if ($Mode -eq 'rollback') { Write-TextFile (Join-Path $sd 'pinned') @('') }
    if ($Mode -eq 'channel' -or $Mode -eq 'local') { Remove-Item -LiteralPath (Join-Path $sd 'pinned') -Force -ErrorAction SilentlyContinue }
    Show-Ready $Env $cur
    Open-Url (Get-KitHost $Env 'console')
}

function Initialize-State([string]$Env) {
    $sd = Get-StateDir $Env
    New-Item -ItemType Directory -Force -Path $sd | Out-Null
    return $sd
}

function Invoke-Start([string]$Env) {
    Assert-Env $Env
    Assert-Prerequisites
    Assert-LocalEnv
    Title "Qeet ID $(Get-Label $Env)"
    $sd = Initialize-State $Env
    $cur = Join-Path $sd 'current.env'; $cand = Join-Path $sd 'candidate.env'
    $installed = Get-Kv $cur 'QEET_ID_VERSION'

    if ($Env -eq 'dev') { New-DevRelease $cand; Start-Release 'dev' $cand 'dev'; return }
    if ($Opt.Build -or $Opt.Images.Count -gt 0) { Die '--build and --image are for DEV only. TEST and STAGING run published release candidates.' }
    if ($Opt.Manifest) {
        if (-not (Test-Path -LiteralPath $Opt.Manifest)) { Die "Manifest file not found: $($Opt.Manifest)" }
        Write-TextFile $cand @(Get-Content -LiteralPath $Opt.Manifest | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') })
        if (-not (Test-Release $cand -AllowUnpinned)) { Die "$($Opt.Manifest) is not a valid release manifest." }
        Warn "Using a local manifest ($($Opt.Manifest)) - engineering use only."
        Say "Installed: $(if ($installed) { $installed } else { 'none' })"
        Say "Selected:  $(Get-Kv $cand 'QEET_ID_VERSION')"
        Start-Release $Env $cand 'local'
        return
    }
    if ((Test-Path -LiteralPath (Join-Path $sd 'pinned')) -and -not $Opt.Candidate -and (Test-Path -LiteralPath $cur)) {
        Warn "$(Get-Label $Env) is pinned to $installed by Rollback. Run Update ($(Get-KitCmd $Env 'update')) to return to the newest candidate."
        Start-Release $Env $cur 'installed'
        return
    }

    $channel = Get-Kv (Join-Path $KitDir "environments/$Env/environment.env") 'QEET_KIT_CHANNEL'
    $name = if ($Opt.Candidate) { $Opt.Candidate } else { $channel }
    $rc = Get-Release "$Registry/qeet-id-release:$name" $cand
    if ($rc -ne 0) {
        if ((Test-Path -LiteralPath $cur) -and -not $Opt.Candidate -and $rc -ne 13) {
            $why = if ($rc -eq 10) { 'registry authentication' } else { 'registry unreachable' }
            Warn "Could not check for a newer release ($why). Starting the installed version."
            Start-Release $Env $cur 'installed'
            return
        }
        Stop-OnRegistryFailure $rc $name
    }
    Say "Installed: $(if ($installed) { $installed } else { 'none' })"
    Say "Available: $(Get-Kv $cand 'QEET_ID_VERSION')"
    if ($installed -and ((Get-Content -LiteralPath $cand -Raw) -eq (Get-Content -LiteralPath $cur -Raw))) {
        Say "Already on the newest $(Get-Label $Env) candidate."
    } else {
        Say 'Updating...'
    }
    Start-Release $Env $cand 'channel'
}

function Invoke-Update([string]$Only) {
    if ($Only -eq 'dev') { Die "DEV is updated by rebuilding: $(Get-KitCmd 'dev' 'start') --build" }
    if ($Only) { Assert-ReleaseEnv $Only }
    Assert-Prerequisites
    $Opt.NoBrowser = $true
    $any = $false
    foreach ($e in @($Environments | Where-Object { $_ -ne 'dev' })) {
        if ($Only -and $Only -ne $e) { continue }
        if ($Only -or (Test-ProjectRunning $e)) {
            Remove-Item -LiteralPath (Join-Path (Get-StateDir $e) 'pinned') -Force -ErrorAction SilentlyContinue
            Invoke-Start $e
            $any = $true
        }
    }
    if (-not $any) { Die 'No TEST or STAGING environment is running.' @("Start one first, e.g. $(Get-KitCmd 'test' 'start')") }
}

# ------------------------------------------------------------ other cmds ---

function Invoke-Stop([string]$Target) {
    if (-not $Target) { Die 'Stop which environment? dev, test, staging or all.' }
    if (($Environments + 'all') -notcontains $Target) { Die "Unknown environment '$Target'. Use $(Get-EnvList) or all." }
    Assert-Prerequisites
    $any = $false
    foreach ($e in $Environments) {
        if ($Target -ne 'all' -and $Target -ne $e) { continue }
        if (Test-ProjectRunning $e) { Stop-Project $e; Ok "Stopped $(Get-Label $e) (data kept)"; $any = $true }
        elseif ($Target -eq $e) { Say "$(Get-Label $e) is not running." }
    }
    if ($Target -eq 'all') {
        if (Test-EdgeRunning) { if ((Invoke-Docker (Get-EdgeArgs @('down'))) -eq 0) { Ok 'Stopped the local edge' } }
        if (-not $any) { Say 'No environment was running.' }
    } else {
        Stop-EdgeIfIdle
    }
}

function Invoke-Reset([string]$Env, [switch]$ForRollback) {
    Assert-Env $Env
    Assert-Prerequisites
    $sd = Get-StateDir $Env
    Title "Reset Qeet ID $(Get-Label $Env)"
    Say "This permanently deletes every $(Get-Label $Env) account, organization and email on this computer,"
    Say "then starts $(Get-Label $Env) fresh. The other environments are not touched."
    Say ''
    if (-not (Confirm-Typed $Env "Type $Env to confirm")) { Die 'Reset cancelled. Nothing was changed.' }
    Stop-Project $Env
    [void](Invoke-Docker @('volume', 'rm', "qeet-id-$Env-postgres", "qeet-id-$Env-mail"))
    if (Test-VolumeExists $Env) { Die "Could not delete the $(Get-Label $Env) database volume." @('Restart Docker Desktop and try again.') }
    foreach ($p in @('secrets', 'data.env', 'pinned')) {
        Remove-Item -LiteralPath (Join-Path $sd $p) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Ok "Deleted $(Get-Label $Env) data"
    Hint "Also delete any passkeys saved for $Env.id.qeet.localhost in your browser or password manager."
    if ($ForRollback) { return }
    Invoke-Start $Env
}

function Invoke-Rollback([string]$Env) {
    Assert-ReleaseEnv $Env
    Assert-Prerequisites
    $sd = Get-StateDir $Env
    $prev = Join-Path $sd 'previous.env'
    if (-not (Test-Path -LiteralPath $prev)) { Die "No earlier $(Get-Label $Env) candidate is available on this computer." }
    if (-not (Test-Release $prev -AllowUnpinned)) { Die 'The recorded previous release is unreadable.' }
    Title "Roll back Qeet ID $(Get-Label $Env) to $(Get-Kv $prev 'QEET_ID_VERSION')"
    if ((Test-VolumeExists $Env) -and -not $Opt.Reset) {
        $db = Get-DbSchema $Env $prev
        if ($db) {
            $schema = ($db.Trim() -split ' ')[0]
            $prevSchema = Get-Kv $prev 'QEET_ID_SERVER_SCHEMA_VERSION'
            if ($prevSchema -match '^\d+$' -and $schema -match '^\d+$' -and [int]$prevSchema -lt [int]$schema) {
                Die "$(Get-Kv $prev 'QEET_ID_VERSION') is older than your $(Get-Label $Env) data (schema $schema), so it cannot open it." @(
                    "To roll back anyway with fresh data: QeetIdKit.ps1 rollback $Env --reset   (deletes $(Get-Label $Env) data).")
            }
        }
    }
    $tmp = Join-Path $sd 'rollback.env'
    Copy-Item -LiteralPath $prev -Destination $tmp -Force
    if ($Opt.Reset) { Invoke-Reset $Env -ForRollback }
    Start-Release $Env $tmp 'rollback'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

function Invoke-Status([string]$Only) {
    if ($Only) { Assert-Env $Only }
    Title "Qeet ID Local Environments - Qeet ID Kit $KitVersion"
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { Warn 'Docker is not running; showing recorded versions only.' }
    if (Test-EdgeRunning) { Say 'EDGE     running   127.0.0.1:80' } else { Say 'EDGE     stopped' }
    Say ''
    foreach ($e in $Environments) {
        if ($Only -and $Only -ne $e) { continue }
        $sd = Get-StateDir $e
        $cur = Join-Path $sd 'current.env'; $prev = Join-Path $sd 'previous.env'
        if (-not (Test-Path -LiteralPath $cur)) { Say "$(Get-Label $e)  not installed   ($(Get-KitCmd $e 'start'))"; Say ''; continue }
        $running = Test-ProjectRunning $e
        $state = if ($running) { 'running' } else { 'stopped' }
        if (Test-Path -LiteralPath (Join-Path $sd 'pinned')) { $state = "$state, pinned by Rollback" }
        Say "$(Get-Label $e)  $state"
        if ($e -eq 'dev') { Say "  Build:          locally selected images (recorded $(Get-Kv $cur 'QEET_ID_CREATED_AT'))" }
        else { Say "  Release:        $(Get-Kv $cur 'QEET_ID_RELEASE')   Candidate: $(Get-Kv $cur 'QEET_ID_VERSION')   Published: $(Get-Kv $cur 'QEET_ID_CREATED_AT')" }
        foreach ($c in $Components) {
            $uc = $c.ToUpper()
            Say ('  {0,-15} {1}' -f "$(Get-ServiceName $c):", (Get-Kv $cur "QEET_ID_${uc}_IMAGE"))
            $extra = if ($c -eq 'server') { ", schema $(Get-Kv $cur 'QEET_ID_SERVER_SCHEMA_VERSION')" } else { '' }
            Say ('  {0,-15} revision {1}{2}' -f '', (Get-Kv $cur "QEET_ID_${uc}_REVISION"), $extra)
        }
        if (Test-Path -LiteralPath $prev) { Say "  Previous:       $(Get-Kv $prev 'QEET_ID_VERSION') (available for Rollback)" }
        if ($running) {
            $rows = (Get-ComposeText $e $cur @('ps', '-a', '--format', '{{.Service}}|{{.State}}|{{.Health}}')) -split "`n" | Sort-Object
            foreach ($row in $rows) {
                $f = $row -split '\|'
                if (-not $f[0] -or $f[0] -eq 'keygen') { continue }
                $h = if ($f.Count -gt 2 -and $f[2]) { $f[2] } else { $f[1] }
                Say ('  {0,-15} {1}' -f (Get-ServiceName $f[0]), $h)
            }
            Say "  URLs:           $(Get-KitHost $e 'console')  $(Get-KitHost $e 'login')"
            Say "                  $(Get-KitHost $e 'api')  $(Get-KitHost $e 'mail')"
            Say "                  $(Get-KitHost $e 'website')  $(Get-KitHost $e 'docs')"
        }
        Say ''
    }
}

function Invoke-Logs([string]$Svc, [switch]$Interactive) {
    if ($Interactive) {
        $Svc = Read-Host 'Service (server, login, console, website, docs, db, mail, edge - Enter for all)'
        $Opt.Follow = $true
    }
    if ($Svc -eq 'edge' -or $Svc -eq 'proxy' -or $Svc -eq 'router') {
        $a = @('logs', '--timestamps', '--tail', $Opt.Tail); if ($Opt.Follow) { $a += '--follow' }
        & docker @(Get-EdgeArgs $a)
        return
    }
    $env = $Opt.Env
    if (-not $env) {
        $running = @($Environments | Where-Object { Test-ProjectRunning $_ })
        if ($running.Count -eq 1) { $env = $running[0] }
        elseif ($Interactive -and $running.Count -gt 1) { $env = Read-Host "Environment ($($running -join ', '))" }
        else { Die "Which environment? Add --env with one of: $(Get-EnvList)." @("Running now: $(if ($running.Count) { $running -join ' ' } else { 'none' })") }
    }
    Assert-Env $env
    $cur = Join-Path (Get-StateDir $env) 'current.env'
    # A first start that failed has no current.env yet, only the candidate it tried.
    if (-not (Test-Path -LiteralPath $cur)) { $cur = Join-Path (Get-StateDir $env) 'candidate.env' }
    if (-not (Test-Path -LiteralPath $cur)) { Die "$(Get-Label $env) is not installed." }
    switch ($Svc) {
        { $_ -eq '' -or $_ -eq 'all' } { $Svc = ''; break }
        { $_ -eq 'server' -or $_ -eq 'api' } { $Svc = 'server'; break }
        { @('login', 'console', 'website', 'docs') -contains $_ } { break }
        { $_ -eq 'db' -or $_ -eq 'database' -or $_ -eq 'postgres' } { $Svc = 'postgres'; break }
        { $_ -eq 'mail' -or $_ -eq 'mailpit' } { $Svc = 'mailpit'; break }
        default { Die "Unknown service '$Svc'." @('Use one of: server, login, console, website, docs, db, mail, edge (or nothing for all).') }
    }
    $a = @('logs', '--timestamps', '--tail', $Opt.Tail)
    if ($Opt.Follow) { $a += '--follow' }
    if ($Svc) { $a += $Svc }
    Set-ComposeEnv $env
    & docker @(Get-ComposeArgs $env $cur $a)
}

function Invoke-Cleanup {
    Assert-Prerequisites
    $keep = @()
    foreach ($e in $Environments) {
        foreach ($f in @('current', 'previous')) {
            foreach ($k in (Get-ImageKeys)) {
                $v = Get-Kv (Join-Path (Get-StateDir $e) "$f.env") $k
                if ($v -notmatch '@sha256:') { continue }
                $repoTag = ($v -split '@')[0]
                $repo = $repoTag.Substring(0, $repoTag.LastIndexOf(':'))
                $keep += "$repo@$(($v -split '@')[1])"
            }
        }
    }
    $n = 0
    $rows = (Get-DockerText @('image', 'ls', '-a', '--digests', '--format', '{{.Repository}}|{{.Digest}}')) -split "`n" | Sort-Object -Unique
    foreach ($row in $rows) {
        $f = $row -split '\|'
        if ($f.Count -lt 2) { continue }
        if (@($Components | ForEach-Object { "$Registry/qeet-id-$_" }) -notcontains $f[0]) { continue }
        if (-not $f[1].StartsWith('sha256:')) { continue }
        if ($keep -contains "$($f[0])@$($f[1])") { continue }
        # By reference, so only the candidate the kit pulled is removed.
        if ((Invoke-Docker @('image', 'rm', "$($f[0])@$($f[1])")) -eq 0) { $n++ }
    }
    Ok "Removed $n old Qeet ID image(s); kept the current and previous candidate of each environment."
}

function Invoke-Login {
    $registryHost = ($Registry -split '/')[0]
    Assert-Prerequisites
    Title "Sign in to GitHub Packages ($registryHost)"
    Say 'Use your GitHub username and a CLASSIC personal access token with ONLY the'
    Say 'read:packages scope: github.com/settings/tokens > Tokens (classic).'
    Say 'Fine-grained tokens do not work with GitHub Packages.'
    Say 'Docker asks for the token itself (hidden) and keeps it in its credential store, not in the kit.'
    Say ''
    $user = Read-Host 'GitHub username'
    if (-not $user) { Die 'A username is required.' }
    & docker login $registryHost -u $user
    if ($LASTEXITCODE -ne 0) { Die "Sign-in to $registryHost failed." @('Check the username, and that you pasted a classic token with read:packages.') }
    # "Login Succeeded" only proves the token is valid; check it can read Qeet ID.
    Say ''
    Say 'Checking that this sign-in can download Qeet ID...'
    if ((Test-Access) -eq 0) { Ok "Signed in to $registryHost and able to download Qeet ID. Next: $(Get-KitCmd 'test' 'start')" }
    else {
        Die 'Signed in, but this sign-in cannot download everything Qeet ID needs (see above).' @(
            'Use a CLASSIC token (Tokens (classic)) with read:packages - fine-grained tokens do not work.',
            'Sign in with your own GitHub account, and make sure it has been given access to the qeetgroup packages (ask your team lead).',
            "Then run Login again: $(Get-KitCmd 'tools' 'login')")
    }
}

function Invoke-UpdateKit([string]$Want) {
    Assert-Prerequisites
    $tag = if ($Want) { $Want } else { 'stable' }
    $ref = "$Registry/qeet-id-test-kit:$tag"
    Title "Update Kit (installed: $KitVersion)"
    if ((Invoke-Docker @('pull', '-q', $ref)) -ne 0) { Stop-OnRegistryFailure (Get-RegistryErrorCode ($script:LastLog -join "`n")) "qeet-id-test-kit:$tag" }
    $digestRef = (Get-DockerText @('image', 'inspect', '--format', '{{index .RepoDigests 0}}', $ref)).Trim()
    if ($digestRef -notmatch '@sha256:') { Die "Could not resolve $ref to an immutable digest." }
    $label = Get-ImageLabel $digestRef 'org.opencontainers.image.version'
    if ($Want -and $Want -ne 'stable' -and $label -ne $Want) { Die "$ref claims version '$label', not $Want. Not installing it." }
    # Only a newer kit is an update, unless a version was asked for explicitly.
    if ($label -eq $KitVersion -or ((-not $Want -or $Want -eq 'stable') -and (Test-VersionAtLeast $KitVersion $label))) {
        Ok "This Qeet ID Kit ($KitVersion) is already the newest."; return
    }
    $dest = Join-Path (Split-Path -Parent $KitDir) "qeet-id-kit-$label"
    if (Test-Path -LiteralPath $dest) { Die "$dest already exists." @('Use that folder, or remove it and run Update Kit again.') }
    $cid = (Get-DockerText @('create', $digestRef, 'true')).Trim()
    if (-not $cid) { Die 'Could not unpack the Qeet ID Kit image.' }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $code = Invoke-Docker @('cp', "${cid}:/kit/.", $dest)
    [void](Invoke-Docker @('rm', $cid))
    if ($code -ne 0) { Remove-Item -LiteralPath $dest -Recurse -Force; Die 'Could not unpack the Qeet ID Kit image.' }
    $version = (Get-Content -LiteralPath (Join-Path $dest 'VERSION') -TotalCount 1).Trim()
    if ($version -ne $label) {
        Remove-Item -LiteralPath $dest -Recurse -Force
        Die "The downloaded kit reports version '$version' but is labelled '$label'. Not installing it."
    }
    $repo = ($digestRef -split '@')[0]
    Write-TextFile (Join-Path $dest 'kit.lock') @("QEET_KIT_IMAGE=${repo}:$label@$(($digestRef -split '@')[1])")
    $localEnv = Join-Path $KitDir 'settings/.env'
    if (Test-Path -LiteralPath $localEnv) { Copy-Item -LiteralPath $localEnv -Destination (Join-Path $dest 'settings/.env') }
    Ok "Qeet ID Kit $label installed in $dest"
    Say '  Close this window and use the new folder from now on. Your environments,'
    Say '  data and registry sign-in are kept.'
    if ($env:OS -eq 'Windows_NT' -and -not $Opt.NoBrowser) { Start-Process explorer.exe $dest }
}

function Invoke-Doctor {
    $problems = 0
    Title "Qeet ID Kit $KitVersion - Doctor"
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail 'Docker is not installed - install Docker Desktop.'; exit 1 }
    Ok "Docker CLI $((Get-DockerText @('version', '--format', '{{.Client.Version}}')).Trim())"
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { Fail 'Docker Desktop is installed but is not running - start it.'; exit 1 }
    Ok "Docker engine $((Get-DockerText @('version', '--format', '{{.Server.Version}}')).Trim()) is running"
    $v = (Get-DockerText @('compose', 'version', '--short')).Trim().TrimStart('v')
    if ($v -and (Test-VersionAtLeast $v '2.24.0')) { Ok "Docker Compose $v" } else { Fail "Docker Compose $v - 2.24 or newer is required"; $problems++ }
    if ((Get-DockerText @('info', '--format', '{{.OSType}}')).Trim() -eq 'linux') { Ok 'Linux containers' } else { Fail 'Switch Docker Desktop to Linux containers'; $problems++ }
    $memText = (Get-DockerText @('info', '--format', '{{.MemTotal}}')).Trim()
    $mem = 0; if ($memText -match '^\d+$') { $mem = [int]([long]$memText / 1048576) }
    if ($mem -ge 4096) { Ok "Docker memory $([int]($mem / 1024)) GiB (enough for DEV, TEST and STAGING together)" }
    elseif ($mem -ge 2048) { Warn "Docker memory $([int]($mem / 1024)) GiB - enough for one or two environments; 4 GiB runs all three (Docker Desktop > Settings > Resources)" }
    else { Fail "Docker has only $mem MiB of memory; at least 2 GiB is needed (Docker Desktop > Settings > Resources)"; $problems++ }
    $drive = $null
    if ($StateRoot -match '^([A-Za-z]):') { $drive = Get-PSDrive -Name $Matches[1] -ErrorAction SilentlyContinue }
    if ($drive -and $drive.Free) {
        $free = [int]($drive.Free / 1073741824)
        if ($free -ge 10) { Ok "Free disk $free GiB" } else { Warn "Only $free GiB free disk; 10 GiB or more is recommended" }
    }
    $arch = (Get-DockerText @('version', '--format', '{{.Server.Arch}}')).Trim()
    Ok "Architecture: Docker $arch"
    if (Test-EdgeRunning) { Ok 'Port 80 is served by the Qeet ID edge' }
    else {
        $owner = Get-Port80Owner
        if ($owner -eq 4) { Fail 'Port 80 is held by Windows (http.sys, e.g. IIS / World Wide Web Publishing Service)'; $problems++ }
        elseif ($owner -gt 0) { Fail "Port 80 is in use by process $owner (Task Manager > Details)"; $problems++ }
        else { Ok 'Port 80 is free' }
    }
    New-Item -ItemType Directory -Force -Path $StateRoot -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path -LiteralPath $StateRoot) { Ok "State folder $StateRoot" } else { Fail "Cannot write $StateRoot"; $problems++ }
    if ($StateRoot -match 'OneDrive') { Warn 'The state folder is inside OneDrive; set QEET_KIT_STATE_DIR to a local folder' }
    if (Test-Path -LiteralPath (Join-Path $KitDir 'kit.lock')) { Ok "Kit image $(Get-KitImage)" } else { Warn 'No kit.lock - development checkout; the tools image is built locally' }
    $badKey = $false
    $f = Join-Path $KitDir 'settings/.env'
    if (Test-Path -LiteralPath $f) {
        foreach ($line in (Get-Content -LiteralPath $f)) {
            if ($line -eq '' -or $line.StartsWith('#')) { continue }
            if (@(Get-LocalEnvKeys) -cnotcontains (($line -split '=', 2)[0])) { $badKey = $true }
        }
    }
    if ($badKey) { Fail 'settings\.env contains a key the kit does not accept'; $problems++ } else { Ok 'Configuration' }
    if ($env:OS -eq 'Windows_NT') {
        Ok "PowerShell execution policy: $(Get-ExecutionPolicy); language mode: $($ExecutionContext.SessionState.LanguageMode)"
    }
    $tmp = Join-Path $StateRoot 'doctor-release.env'
    $rc = Get-Release "$Registry/qeet-id-release:test" $tmp
    switch ($rc) {
        0 {
            Ok "Registry access ($Registry); TEST channel: $(Get-Kv $tmp 'QEET_ID_VERSION')"
            $problems += (Test-Access)
            if ((',' + (Get-Kv $tmp 'QEET_ID_PLATFORMS') + ',') -match ",linux/$arch,") { Ok "Images available for linux/$arch" }
            else { Warn "TEST images are not published for linux/$arch; Docker will emulate them (slower)" }
            if (-not (Test-VersionAtLeast $KitVersion (Get-Kv $tmp 'QEET_ID_MIN_KIT_VERSION'))) {
                Fail "The TEST candidate needs Qeet ID Kit $(Get-Kv $tmp 'QEET_ID_MIN_KIT_VERSION') - run Update Kit: $(Get-KitCmd 'tools' 'update-kit')"; $problems++
            }
        }
        10 { Fail "This GitHub sign-in cannot read the Qeet ID packages - run Login: $(Get-KitCmd 'tools' 'login')"; $problems++ }
        14 { Fail "Docker's sign-in helper is not working - restart Docker Desktop"; $problems++ }
        15 { Fail 'The registry is limiting downloads right now - run Doctor again in a minute'; $problems++ }
        11 { Warn 'Registry reachable; no TEST candidate has been published yet' }
        13 { Fail "The TEST release manifest is unreadable - run Update Kit: $(Get-KitCmd 'tools' 'update-kit')"; $problems++ }
        default { Fail "Cannot reach $Registry - check your internet connection or proxy"; $problems++ }
    }
    Remove-Item -LiteralPath $tmp, "$tmp.tmp" -Force -ErrorAction SilentlyContinue
    Ok 'Browsers: Chrome and Edge open *.id.qeet.localhost on this computer automatically'
    Say ''
    if ($problems -eq 0) { Ok 'No problems found.' } else { Fail "$problems problem(s) found."; exit 1 }
}

# ------------------------------------------------------------------ main ---

if ($args.Count -lt 1) { Show-Usage; exit 2 }
$command = $args[0]
Read-Options @($args | Select-Object -Skip 1)
$first = if ($Positional.Count -gt 0) { $Positional[0] } else { $Opt.Env }
switch ($command) {
    'start' { Invoke-Start $first }
    'update' { Invoke-Update $first }
    'stop' { Invoke-Stop $first }
    'reset' { Invoke-Reset $first }
    'rollback' { Invoke-Rollback $first }
    'status' { Invoke-Status $first }
    'logs' { Invoke-Logs $(if ($Positional.Count -gt 0) { $Positional[0] } else { '' }) }
    'logs-interactive' { Invoke-Logs '' -Interactive }
    'cleanup' { Invoke-Cleanup }
    'doctor' { Invoke-Doctor }
    'login' { Invoke-Login }
    'update-kit' { Invoke-UpdateKit $(if ($Positional.Count -gt 0) { $Positional[0] } else { '' }) }
    default { Show-Usage; exit 2 }
}
