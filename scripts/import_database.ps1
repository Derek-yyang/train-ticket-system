param(
    [Parameter(Mandatory = $true)]
    [string]$MySqlUser,
    [string]$MySqlExecutable = "mysql",
    [string]$HostName = "127.0.0.1",
    [int]$Port = 3306
)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$databaseDir = Join-Path $projectRoot "database"
if (-not (Get-Command $MySqlExecutable -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $MySqlExecutable)) {
    throw "未找到 mysql.exe。请将其加入 PATH，或通过 -MySqlExecutable 指定绝对路径。"
}

foreach ($scriptName in @("schema.sql", "routines.sql", "seed.sql")) {
    $scriptPath = Join-Path $databaseDir $scriptName
    Write-Host "正在导入 $scriptName ..."
    Get-Content -Raw -LiteralPath $scriptPath | & $MySqlExecutable --host=$HostName --port=$Port --user=$MySqlUser --password --default-character-set=utf8mb4
    if ($LASTEXITCODE -ne 0) { throw "$scriptName 导入失败。" }
}

Write-Host "数据库 train_ticket_db 导入完成。"
