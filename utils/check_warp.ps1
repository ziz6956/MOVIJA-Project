Clear-Host
# Принудительно ставим кодировку, чтобы не было проблем с символами
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== ISP DETECTOR ===" -ForegroundColor Cyan
Write-Host "Fetching data... " -NoNewline

# 1. Делаем запрос (curl.exe надежнее стандартных команд)
$raw = & curl.exe -4 -s --connect-timeout 3 "https://redirector.googlevideo.com/report_mapping"

if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Host "FAILED (No response)" -ForegroundColor Red
    exit
}

# 2. Берем только первую строку (защита от мусора)
$line = ($raw -split '[\r\n]+')[0]

# 3. Ищем IP адрес через Regex (используем одинарные кавычки для паттерна)
if ($line -match '([a-f0-9:.]+)\s*=>') {
    $ip = $Matches[1]
    Write-Host "OK" -ForegroundColor Green
    
    # 4. Спрашиваем у базы данных, чей это IP
    try {
        $apiUrl = "http://ip-api.com/json/" + $ip
        $info = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    } catch {
        $info = $null
    }

    if ($info) {
        Write-Host "--------------------------" -ForegroundColor Gray
        # Выводим данные через сложение строк, чтобы не было ошибок парсера
        Write-Host ("IP:       " + $ip)
        Write-Host ("Provider: " + $info.isp)
        Write-Host ("Country:  " + $info.country)
        Write-Host "--------------------------" -ForegroundColor Gray

        # Логика определения статуса
        if ($info.isp -match "Cloudflare" -or $info.org -match "Cloudflare") {
            Write-Host "STATUS: WARP ACTIVE (Success)" -ForegroundColor Green
        } elseif ($info.isp -match "Aeza" -or $info.org -match "Euro Fiber") {
            Write-Host "STATUS: DIRECT (Your VPS)" -ForegroundColor Red
        } else {
            Write-Host "STATUS: UNKNOWN ISP" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "FAILED (Format error)" -ForegroundColor Red
}

Write-Host ""
# Выводим сырую строку безопасно
Write-Host "Debug info:" -ForegroundColor Gray
Write-Host $line -ForegroundColor Gray
Pause