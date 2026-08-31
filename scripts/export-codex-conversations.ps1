param(
    [Parameter(Mandatory = $true)]
    [string]$SessionRoot,

    [Parameter(Mandatory = $true)]
    [string]$SessionIndex,

    [Parameter(Mandatory = $true)]
    [string]$WorkspacePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Convert-ToSafeFileName {
    param([string]$Value)

    $safe = $Value -replace '[\\/:*?"<>|]', '-'
    $safe = $safe -replace '\s+', '-'
    $safe = $safe.Trim('-', '.', ' ')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'untitled'
    }
    if ($safe.Length -gt 72) {
        return $safe.Substring(0, 72).TrimEnd('-')
    }
    return $safe
}

function Convert-ToPortableMarkdown {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $portable = $Text.Replace('C:\Dev_Project\Java\HippoBuddy\', '../')
    $portable = $portable.Replace('C:/Dev_Project/Java/HippoBuddy/', '../')
    $portable = $portable -replace 'ghp_[A-Za-z0-9]{20,}', 'ghp_REDACTED'
    $portable = $portable -replace 'github_pat_[A-Za-z0-9_]{20,}', 'github_pat_REDACTED'
    $portable = $portable -replace 'sk-[A-Za-z0-9_-]{20,}', 'sk-REDACTED'
    $portable = $portable -replace '(?i)Bearer\s+[A-Za-z0-9._~-]{24,}', 'Bearer REDACTED'
    $portable = $portable -replace '\b[A-Z0-9]{4}-[A-Z0-9]{4}\b', '[REDACTED-CODE]'
    return $portable.Trim()
}

function Should-SkipUserText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $true
    }

    $trimmed = $Text.TrimStart()
    return $trimmed.StartsWith('<recommended_plugins>') -or
        $trimmed.StartsWith('<environment_context>')
}

$titles = @{}
if (Test-Path -LiteralPath $SessionIndex) {
    Get-Content -LiteralPath $SessionIndex | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) {
            return
        }
        try {
            $entry = $_ | ConvertFrom-Json
            if ($entry.id -and $entry.thread_name) {
                $titles[[string]$entry.id] = [string]$entry.thread_name
            }
        } catch {
            # Ignore a malformed index row; the session file remains exportable.
        }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$exports = New-Object System.Collections.Generic.List[object]
$sessionFiles = Get-ChildItem -LiteralPath $SessionRoot -Recurse -Filter '*.jsonl' -File

foreach ($sessionFile in $sessionFiles) {
    $firstLine = Get-Content -LiteralPath $sessionFile.FullName -TotalCount 1
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        continue
    }

    try {
        $metaRecord = $firstLine | ConvertFrom-Json
    } catch {
        continue
    }

    if ($metaRecord.type -ne 'session_meta' -or $metaRecord.payload.cwd -ne $WorkspacePath) {
        continue
    }

    # Internal guardian/worker sessions are implementation logs, not user-owned
    # conversations shown in the Codex task list.
    if ($null -ne $metaRecord.payload.source -and
        $null -ne $metaRecord.payload.source.subagent) {
        continue
    }

    $threadId = [string]$metaRecord.payload.id
    if ([string]::IsNullOrWhiteSpace($threadId)) {
        $threadId = [System.IO.Path]::GetFileNameWithoutExtension($sessionFile.Name)
    }

    $title = $titles[$threadId]
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = "Codex 会话 $threadId"
    }

    $messages = New-Object System.Collections.Generic.List[object]
    Get-Content -LiteralPath $sessionFile.FullName | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) {
            return
        }

        try {
            $record = $_ | ConvertFrom-Json
        } catch {
            return
        }

        if ($record.type -ne 'response_item' -or $record.payload.type -ne 'message') {
            return
        }

        $role = [string]$record.payload.role
        if ($role -notin @('user', 'assistant')) {
            return
        }

        $textParts = @(
            $record.payload.content |
                Where-Object { $_.type -in @('input_text', 'output_text') -and $_.text } |
                ForEach-Object { [string]$_.text }
        )
        $text = ($textParts -join "`n").Trim()

        if ($role -eq 'user' -and (Should-SkipUserText -Text $text)) {
            return
        }
        if ([string]::IsNullOrWhiteSpace($text)) {
            return
        }

        $messages.Add([pscustomobject]@{
            Role  = $role
            Phase = [string]$record.payload.phase
            Text  = Convert-ToPortableMarkdown -Text $text
        })
    }

    if ($messages.Count -eq 0) {
        continue
    }

    $timestamp = [string]$metaRecord.payload.timestamp
    $datePrefix = 'undated'
    if (-not [string]::IsNullOrWhiteSpace($timestamp)) {
        try {
            $datePrefix = ([DateTimeOffset]::Parse($timestamp)).ToString('yyyy-MM-dd')
        } catch {
            # Keep the deterministic undated prefix.
        }
    }

    $shortId = if ($threadId.Length -ge 8) { $threadId.Substring(0, 8) } else { $threadId }
    $fileName = '{0}-{1}-{2}.md' -f $datePrefix, (Convert-ToSafeFileName -Value $title), $shortId
    $targetPath = Join-Path $OutputDirectory $fileName

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine("# $title")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("- 会话 ID：``$threadId``")
    [void]$builder.AppendLine("- 导出来源：Codex Desktop（仅保留对话内容）")
    [void]$builder.AppendLine()

    foreach ($message in $messages) {
        if ($message.Role -eq 'user') {
            $heading = '用户'
        } elseif ($message.Phase -eq 'final_answer') {
            $heading = 'Codex（最终回答）'
        } else {
            $heading = 'Codex（过程说明）'
        }

        [void]$builder.AppendLine("## $heading")
        [void]$builder.AppendLine()
        [void]$builder.AppendLine($message.Text)
        [void]$builder.AppendLine()
    }

    [System.IO.File]::WriteAllText($targetPath, $builder.ToString(), $utf8NoBom)
    $exports.Add([pscustomobject]@{
        Title    = $title
        ThreadId = $threadId
        FileName = $fileName
        Messages = $messages.Count
    })
}

$exports = @($exports | Sort-Object FileName)
$index = New-Object System.Text.StringBuilder
[void]$index.AppendLine('# HippoBuddy 相关 Codex 会话')
[void]$index.AppendLine()
[void]$index.AppendLine('这些 Markdown 文件从本机 Codex 会话记录机械导出。为降低隐私与安全风险，导出过程排除了系统提示、环境上下文、内部推理、命令、工具调用和工具输出。')
[void]$index.AppendLine()
[void]$index.AppendLine("共导出 **$($exports.Count)** 个会话。")
[void]$index.AppendLine()

foreach ($item in $exports) {
    $encodedName = $item.FileName.Replace(' ', '%20')
    [void]$index.AppendLine("- [$($item.Title)](./$encodedName) — $($item.Messages) 条对话消息")
}

[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'README.md'), $index.ToString(), $utf8NoBom)

[pscustomobject]@{
    ExportedSessions = $exports.Count
    ExportedMessages = ($exports | Measure-Object -Property Messages -Sum).Sum
    OutputDirectory  = $OutputDirectory
}
