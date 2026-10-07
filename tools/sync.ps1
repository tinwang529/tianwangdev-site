#Requires -Version 5.1
<#
.SYNOPSIS
    当前 git 仓库的「提交 / 收取」助手。

.DESCRIPTION
    对运行时所在目录所属的 git 仓库执行常用同步操作：
      提交并上传 = git add + git commit + git push
      收取更新   = git fetch + git pull
    直接运行（或双击同目录的「同步.bat」）会显示交互菜单。

    操作对象是运行时所处目录所在的仓库，所以本脚本复制到任何 git
    仓库里都能用。

.PARAMETER Action
    menu   —— 显示交互菜单（默认）
    push   —— 提交并上传
    pull   —— 收取更新
    status —— 查看仓库状态

.PARAMETER Message
    提交说明，只对 push 有效。
    留空时：交互模式会提示输入，非交互模式使用时间戳。

.EXAMPLE
    .\sync.ps1

.EXAMPLE
    .\sync.ps1 -Action pull

.EXAMPLE
    .\sync.ps1 -Action push -Message "fix send-mail 参数校验"
#>
[CmdletBinding()]
param(
    [ValidateSet('menu', 'push', 'pull', 'status')]
    [string]$Action = 'menu',

    [string]$Message = ''
)

# 这里刻意不把 $ErrorActionPreference 设成 Stop：
# git 会把进度信息写到 stderr，Windows PowerShell 5.1 会把它当成错误，
# 设成 Stop 反而会打断脚本。所有判断都基于 git 的退出码。
$ErrorActionPreference = 'Continue'

# --------------------------------------------------------------- 输出小工具
function Show-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host ('-' * 58) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('-' * 58) -ForegroundColor DarkGray
}

function Show-Text {
    param([string]$Text, [string]$Color = 'Gray')
    Write-Host "  $Text" -ForegroundColor $Color
}

function Show-Ok   { param([string]$Text) Show-Text $Text 'Green' }
function Show-Note { param([string]$Text) Show-Text $Text 'Yellow' }
function Show-Err  { param([string]$Text) Show-Text $Text 'Red' }

function Pause-Menu {
    if ($script:Interactive) {
        [void](Read-Host '  按回车返回菜单')
    }
}

# 执行 git，并把 stderr 也当普通文本回显，
# 否则 PowerShell 5.1 会把 git 的进度信息标成红色错误。
function Invoke-Git {
    & git @args 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    return $LASTEXITCODE
}

# --------------------------------------------------------------- 读取仓库状态
function Get-RepoRoot {
    $out = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $text = "$out".Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    # git 输出的是正斜杠路径，转成 Windows 习惯的写法
    return ($text -replace '/', '\')
}

function Get-GitState {
    $branch = '(未知)'
    $branchOut = & git rev-parse --abbrev-ref HEAD 2>$null
    if (-not [string]::IsNullOrWhiteSpace($branchOut)) {
        $branch = ("$branchOut").Trim()
    }

    $changed = @(& git status --porcelain 2>$null |
                 Where-Object { -not [string]::IsNullOrWhiteSpace("$_") }).Count

    $state = [pscustomobject]@{
        Branch   = $branch
        Upstream = $null
        Ahead    = 0
        Behind   = 0
        Changed  = $changed
    }

    $upOut = & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($upOut)) {
        $state.Upstream = ("$upOut").Trim()
        $countOut = & git rev-list --left-right --count "$($state.Upstream)...HEAD" 2>$null
        if (-not [string]::IsNullOrWhiteSpace($countOut)) {
            $parts = ("$countOut").Trim() -split '\s+'
            if ($parts.Count -ge 2) {
                $state.Behind = [int]$parts[0]
                $state.Ahead  = [int]$parts[1]
            }
        }
    }
    return $state
}

# 提交说明写成 UTF-8（无 BOM）临时文件再交给 git，
# 避免中文在 PowerShell 5.1 下被按 GBK 传参而变成乱码。
function New-CommitMessageFile {
    param([string]$Text)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('commitmsg-' + [guid]::NewGuid().ToString('N') + '.txt')
    [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($false))
    return $path
}

# --------------------------------------------------------------- 三个动作
function Do-Push {
    Show-Title '提交并上传'

    $state = Get-GitState

    if ($state.Changed -eq 0) {
        Show-Note '没有发现已改动的文件。'
        if ($state.Ahead -gt 0) {
            Show-Text "本地还有 $($state.Ahead) 个提交没上传，继续执行 push。"
        }
        else {
            Show-Text '无需提交，也没有待上传的提交。'
            return
        }
    }
    else {
        Write-Host ''
        Show-Text "以下 $($state.Changed) 个文件有改动："
        [void](Invoke-Git status --short)
        Write-Host ''

        $msg = $Message
        if ([string]::IsNullOrWhiteSpace($msg) -and $script:Interactive) {
            $msg = "$(Read-Host '  提交说明（直接回车 = 用时间戳）')"
        }
        if ([string]::IsNullOrWhiteSpace($msg)) {
            $msg = 'update ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
        }
        Show-Text "提交说明：$msg" 'DarkGray'

        $addCode = Invoke-Git add -A
        if ($addCode -ne 0) { Show-Err 'git add 失败，已中止。'; return }

        $msgFile = New-CommitMessageFile $msg
        try {
            $commitCode = Invoke-Git commit -F $msgFile
        }
        finally {
            Remove-Item -LiteralPath $msgFile -Force -ErrorAction SilentlyContinue
        }
        if ($commitCode -ne 0) { Show-Err 'git commit 失败，已中止。'; return }
    }

    $pushCode = Invoke-Git push
    if ($pushCode -ne 0) {
        Show-Err '上传失败：请检查网络，或确认 GitHub 登录凭据是否有效。'
        return
    }
    Show-Ok '已提交并上传完成。'
}

function Do-Pull {
    Show-Title '收取更新'

    $state = Get-GitState
    if ($state.Changed -gt 0) {
        Show-Note "当前有 $($state.Changed) 个文件还没有提交。"
        if ($script:Interactive) {
            $answer = "$(Read-Host '  未提交就收取可能产生冲突，仍要继续？(y/N)')"
            if ($answer -notmatch '^[Yy]') { return }
        }
        else {
            Show-Err '存在未提交的改动，已跳过收取（请先提交）。'
            return
        }
    }

    Show-Text '正在获取远程信息 ...'
    $fetchCode = Invoke-Git fetch --prune
    if ($fetchCode -ne 0) {
        Show-Err '连接远程仓库失败，请检查网络。'
        return
    }

    $state = Get-GitState
    if (-not $state.Upstream) {
        Show-Note "当前分支 $($state.Branch) 还没有关联远程分支，无法自动收取。"
        return
    }
    if ($state.Behind -eq 0) {
        Show-Ok '已经是最新，没有需要收取的提交。'
        return
    }

    Show-Text "远程有 $($state.Behind) 个新提交，开始收取 ..."
    $pullCode = Invoke-Git pull --ff-only
    if ($pullCode -ne 0) {
        Show-Err '自动快进失败：本地与远程的提交已经分叉。'
        Show-Text "需要手工处理，例如：git pull --rebase   或   git merge $($state.Upstream)"
        return
    }
    Show-Ok '收取完成。'
}

function Do-Status {
    Show-Title '仓库状态'

    $state = Get-GitState
    Show-Text "仓库：$(Get-Location)" 'DarkGray'
    if ($state.Upstream) {
        Show-Text "分支：$($state.Branch)  ->  $($state.Upstream)" 'DarkGray'
        Show-Text "领先 $($state.Ahead) 个提交 / 落后 $($state.Behind) 个提交" 'DarkGray'
    }
    else {
        Show-Text "分支：$($state.Branch)（没有关联远程分支）" 'DarkGray'
    }

    Write-Host ''
    [void](Invoke-Git status --short)
    if ($state.Changed -eq 0) { Show-Text '工作区干净，没有未提交的改动。' 'DarkGray' }

    Write-Host ''
    Show-Text '最近 5 条提交：'
    [void](Invoke-Git --no-pager log --oneline -5)
}

# --------------------------------------------------------------- 启动
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  没有找到 git 命令，请先安装 Git for Windows。' -ForegroundColor Red
    Write-Host ''
    [void](Read-Host '  按回车退出')
    exit 1
}

$repoRoot = Get-RepoRoot
if (-not $repoRoot) {
    Write-Host ''
    Write-Host '  当前目录不在任何 git 仓库里。' -ForegroundColor Red
    Write-Host "  当前目录：$(Get-Location)" -ForegroundColor Gray
    Write-Host '  请进入某个仓库目录再运行，或双击仓库里的「同步.bat」。' -ForegroundColor Gray
    Write-Host ''
    [void](Read-Host '  按回车退出')
    exit 1
}

Set-Location -LiteralPath $repoRoot
$repoName = Split-Path -Leaf $repoRoot
$script:Interactive = ($Action -eq 'menu')

# --------------------------------------------------------------- 非交互调用
if (-not $script:Interactive) {
    switch ($Action) {
        'push'   { Do-Push }
        'pull'   { Do-Pull }
        'status' { Do-Status }
    }
    exit 0
}

# --------------------------------------------------------------- 交互菜单
while ($true) {
    $state = Get-GitState

    Show-Title "$repoName  ·  git 助手"
    Show-Text "仓库：$repoRoot" 'DarkGray'

    if ($state.Upstream) {
        Show-Text "分支：$($state.Branch)   领先 $($state.Ahead) / 落后 $($state.Behind)" 'DarkGray'
    }
    else {
        Show-Text "分支：$($state.Branch)   （无关联远程分支）" 'DarkGray'
    }

    if ($state.Changed -gt 0) {
        Show-Note "改动：$($state.Changed) 个文件待提交"
    }
    else {
        Show-Text '改动：无' 'DarkGray'
    }

    Write-Host ''
    Show-Text '[1] 提交并上传    (git add / commit / push)' 'White'
    Show-Text '[2] 收取更新      (git fetch / pull)' 'White'
    Show-Text '[3] 查看状态' 'White'
    Show-Text '[0] 退出' 'White'
    Write-Host ''

    $choice = "$(Read-Host '  请选择')".Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) { continue }

    switch ($choice) {
        '1'     { Do-Push;   Pause-Menu }
        '2'     { Do-Pull;   Pause-Menu }
        '3'     { Do-Status; Pause-Menu }
        '0'     { return }
        default { Show-Note '无效的选项，请重新选择。' }
    }
}
