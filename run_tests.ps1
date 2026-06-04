# ==========================
# CONFIGURAÇÕES
# ==========================

$HexalyExe = "hexaly.exe"
$ModelFile = ".\model.lsp"

$ConfigFile = ".\cfw.lsp"

$InstanceDir = ".\Instancias"
$OutputDir = ".\resultados_testes"
$CsvOutput = Join-Path $OutputDir "resumo_resultados.csv"

$InstancePattern = '(?i)(?:\.?[\\/])?Instancias[\\/][0-9]+_[0-9]+\.txt'

# ==========================
# FUNÇÕES AUXILIARES
# ==========================

function To-Number($value) {
    if ($null -eq $value -or $value -eq "") {
        return $null
    }

    $s = $value.ToString().Trim().Replace(",", ".")

    return [double]::Parse(
        $s,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-FirstNumber($text, $pattern) {
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) {
        return To-Number $match.Groups[1].Value
    }
    return $null
}

function Get-LastNumber($text, $pattern) {
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -gt 0) {
        return To-Number $matches[$matches.Count - 1].Groups[1].Value
    }
    return $null
}

function Format-Gap($upper, $lower) {
    if ($null -eq $upper -or $upper -eq "" -or $null -eq $lower -or $lower -eq "" -or $lower -eq 0) {
        return ""
    }

    $gap = (($upper - $lower) / $lower) * 100
    return ("{0:0.00}%" -f $gap).Replace(".", ",")
}

function Set-TextUtf8NoBom($Path, $Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Resolve-Path $Path), $Content, $encoding)
}

function Get-NConflictJobs($text) {
    $lines = $text -split "`r?`n"

    $count = 0

    foreach ($line in $lines) {
        if ($line -match '^CONFLITO_TXT;' -and $line -notmatch '^CONFLITO_TXT;mecanico_original') {
            $count++
        }
    }

    return $count
}

function Get-ExtraHoursInfo($text) {
    $match = [regex]::Match($text, 'HORA_EXTRA;(SIM|NAO);([0-9]+(?:[.,][0-9]+)?);minutos')

    if ($match.Success) {
        return @{
            HasExtra = $match.Groups[1].Value
            Minutes  = To-Number $match.Groups[2].Value
        }
    }

    return @{
        HasExtra = ""
        Minutes  = $null
    }
}

# ==========================
# PREPARAÇÃO
# ==========================

if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (!(Test-Path $ConfigFile)) {
    throw "Arquivo de configuração não encontrado: $ConfigFile"
}

if (!(Test-Path $ModelFile)) {
    throw "Arquivo do modelo não encontrado: $ModelFile"
}

$OriginalConfigContent = Get-Content $ConfigFile -Raw

if (-not ([regex]::IsMatch($OriginalConfigContent, $InstancePattern))) {
    throw "Não encontrei nenhum caminho de instância no arquivo $ConfigFile usando o padrão: $InstancePattern. Ajuste a variável `$ConfigFile ou `$InstancePattern."
}

$Results = @()

$Instances = Get-ChildItem $InstanceDir -Filter "*.txt" |
    Sort-Object {
        if ($_.BaseName -match '^([0-9]+)_([0-9]+)$') {
            [int]$matches[1] * 1000 + [int]$matches[2]
        } else {
            $_.BaseName
        }
    }

# ==========================
# EXECUÇÃO DOS TESTES
# ==========================

try {
    foreach ($Instance in $Instances) {
        $InstName = $Instance.BaseName
        $RelInstancePath = "Instancias/$($Instance.Name)"
        $OutputFile = Join-Path $OutputDir "saida_$InstName.txt"

        Write-Host "Rodando instância $InstName..."

        # Atualiza temporariamente o caminho da instância no arquivo configurado
        $RegexObj = [regex]$InstancePattern
        $NewConfigContent = $RegexObj.Replace($OriginalConfigContent, $RelInstancePath, 1)

        Set-TextUtf8NoBom -Path $ConfigFile -Content $NewConfigContent

        # Executa Hexaly e mede tempo real externo
        $Elapsed = Measure-Command {
            & $HexalyExe $ModelFile 2>&1 | Tee-Object -FilePath $OutputFile | Out-Null
        }

        $Text = Get-Content $OutputFile -Raw

        # ==========================
        # EXTRAÇÃO DOS INDICADORES
        # ==========================

        $BoundScheduling = Get-FirstNumber $Text 'LOWER BOUND SCHEDULLING:\s*([0-9]+(?:[.,][0-9]+)?)'

        $NJobsConflict = Get-NConflictJobs $Text

        $Heuristic = if ($NJobsConflict -gt 0) { "Sim" } else { "Não" }

        $BoundHeuristic = Get-LastNumber $Text 'UPPER BOUND TOTAL AJUSTADO\s+([0-9]+(?:[.,][0-9]+)?)'

        if ($null -eq $BoundHeuristic) {
            $BoundHeuristic = $BoundScheduling
        }

        $BoundAfterLunch = Get-LastNumber $Text 'UPPER BOUND TOTAL RECALCULADO COM ALMOCO:\s*([0-9]+(?:[.,][0-9]+)?)'

        $GapHeurSched = Format-Gap $BoundHeuristic $BoundScheduling

        if ($null -ne $BoundAfterLunch) {
            $GapLunchSched = Format-Gap $BoundAfterLunch $BoundScheduling
        } else {
            $BoundAfterLunch = ""
            $GapLunchSched = ""
        }

        $ExtraInfo = Get-ExtraHoursInfo $Text

        $Results += [PSCustomObject]@{
            "Inst"                        = $InstName
            "Bound Schedulling"           = $BoundScheduling
            "Heuristic"                   = $Heuristic
            "N Jobs Conflict"             = $NJobsConflict
            "Bound Heuristic"             = $BoundHeuristic
            "Gap % Heur. / Sched."        = $GapHeurSched
            "Bound After Lunch"           = $BoundAfterLunch
            "Gap % Heur. Lunch / Sched."  = $GapLunchSched
            "Time (s)"                    = [math]::Round($Elapsed.TotalSeconds, 7)
            "Extra Hours"                 = $ExtraInfo.HasExtra
            "min Extra Hours"             = $ExtraInfo.Minutes
        }
    }
}
finally {
    # Restaura o arquivo original
    Set-TextUtf8NoBom -Path $ConfigFile -Content $OriginalConfigContent
}

# ==========================
# EXPORTAÇÃO FINAL
# ==========================

$Results | Export-Csv -Path $CsvOutput -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Host ""
Write-Host "Testes finalizados."
Write-Host "Resumo salvo em: $CsvOutput"
Write-Host "Saídas brutas salvas em: $OutputDir"