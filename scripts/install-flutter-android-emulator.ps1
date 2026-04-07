# Instala Flutter (stable) + Android SDK mínimo (sin Android Studio) + JDK 17.
# Ejecutar en PowerShell:  powershell -ExecutionPolicy Bypass -File .\scripts\install-flutter-android-emulator.ps1
# Requiere: winget (Windows 10/11), espacio en disco (~2-4 GB) y virtualización para el emulador.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$FlutterRoot = Join-Path $env:USERPROFILE 'dev\flutter'
$SdKRoot = Join-Path $env:USERPROFILE 'Android\sdk'
$TempDir = Join-Path $env:TEMP 'ludoteca-android-setup'

function Add-UserPathEntry {
    param([string]$NewPath)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrEmpty($userPath)) {
        $paths = @()
    } else {
        $paths = $userPath -split ';' | Where-Object { $_ -ne '' }
    }
    if ($paths -notcontains $NewPath) {
        $paths += $NewPath
        [Environment]::SetEnvironmentVariable('Path', ($paths -join ';'), 'User')
        Write-Host "PATH usuario: añadido $NewPath"
    } else {
        Write-Host "PATH usuario: ya incluye $NewPath"
    }
}

Write-Host '== 1/5 JDK 17 (Microsoft OpenJDK) =='
winget install -e --id Microsoft.OpenJDK.17 `
    --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

Write-Host '== 2/5 Flutter (stable, Windows x64) =='
New-Item -ItemType Directory -Force -Path (Split-Path $FlutterRoot) | Out-Null
$releases = Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
$stableHash = $releases.current_release.stable
$rel = $releases.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
if (-not $rel) { throw 'No se pudo resolver la version estable de Flutter desde releases_windows.json' }
$flutterZipUrl = "$($releases.base_url)/$($rel.archive)"
Write-Host "Descargando Flutter $($rel.version) ..."
$zipPath = Join-Path $env:TEMP "flutter_windows_$($rel.hash).zip"
Invoke-WebRequest -Uri $flutterZipUrl -OutFile $zipPath
if (Test-Path $FlutterRoot) {
    Remove-Item -Recurse -Force $FlutterRoot
}
Expand-Archive -Path $zipPath -DestinationPath (Split-Path $FlutterRoot) -Force
# El zip crea carpeta flutter dentro del destino
$expanded = Join-Path (Split-Path $FlutterRoot) 'flutter'
if (Test-Path $expanded) {
    if ($expanded -ne $FlutterRoot) {
        Move-Item -Path $expanded -Destination $FlutterRoot -Force
    }
}
Add-UserPathEntry (Join-Path $FlutterRoot 'bin')

Write-Host '== 3/5 Android command-line tools =='
New-Item -ItemType Directory -Force -Path $SdKRoot | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
# URL oficial (si falla, actualiza la revision en developer.android.com → command line tools only)
$cmdlineZipUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
$cmdZip = Join-Path $TempDir 'cmdline-tools.zip'
Write-Host "Descargando $cmdlineZipUrl"
Invoke-WebRequest -Uri $cmdlineZipUrl -OutFile $cmdZip
$extractCmd = Join-Path $TempDir 'cmdline-extract'
if (Test-Path $extractCmd) { Remove-Item -Recurse -Force $extractCmd }
Expand-Archive -Path $cmdZip -DestinationPath $extractCmd -Force
$latestDir = Join-Path $SdKRoot 'cmdline-tools\latest'
$cmdlineParent = Join-Path $SdKRoot 'cmdline-tools'
New-Item -ItemType Directory -Force -Path $cmdlineParent | Out-Null

# proto.jar y otros suelen quedar bloqueados por java.exe (sdkmanager, Gradle, Android Studio)
Write-Host 'Liberando bloqueos en cmdline-tools (cierra Android Studio si está abierto)...'
Get-Process -Name 'java', 'javaw' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Cerrando $($_.ProcessName) (PID $($_.Id))"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

if (Test-Path -LiteralPath $latestDir) {
    $removed = $false
    for ($i = 0; $i -lt 6; $i++) {
        try {
            Remove-Item -LiteralPath $latestDir -Recurse -Force -ErrorAction Stop
            $removed = $true
            break
        } catch {
            Write-Host "  Reintento $($i + 1)/6 al borrar 'latest': $($_.Exception.Message)"
            Get-Process -Name 'java', 'javaw' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    }
    if (-not $removed) {
        throw @"
No se pudo borrar la carpeta:
  $latestDir
Algún proceso sigue usando archivos dentro (p. ej. proto.jar).

Haz esto y vuelve a ejecutar el script:
  1) Cierra Android Studio, emulador y terminales donde hayas usado sdkmanager/flutter.
  2) PowerShell:  Get-Process java* | Stop-Process -Force
  3) Si sigue igual, reinicia Windows y borra manualmente la carpeta 'latest' antes de reintentar.
"@
    }
}

# El zip contiene una carpeta "cmdline-tools" con bin/lib...
$inner = Join-Path $extractCmd 'cmdline-tools'
if (-not (Test-Path $inner)) { throw 'Estructura inesperada en commandlinetools zip' }
Move-Item -Path $inner -Destination $latestDir -Force

[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $SdKRoot, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdKRoot, 'User')
$env:ANDROID_SDK_ROOT = $SdKRoot
$env:ANDROID_HOME = $SdKRoot

Add-UserPathEntry (Join-Path $SdKRoot 'platform-tools')
Add-UserPathEntry (Join-Path $SdKRoot 'emulator')
Add-UserPathEntry (Join-Path $SdKRoot 'cmdline-tools\latest\bin')

$sdkmanager = Join-Path $SdKRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkmanager)) { throw "No se encuentra sdkmanager en $sdkmanager" }

$jdkHome = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'jdk-*' } |
    Sort-Object Name -Descending |
    Select-Object -First 1
if ($jdkHome) {
    $env:JAVA_HOME = $jdkHome.FullName
    Write-Host "JAVA_HOME (sesion): $($env:JAVA_HOME)"
}

Write-Host '== 4/5 Paquetes SDK (platform-tools, emulator, API 35) =='
$packages = @(
    'platform-tools',
    'emulator',
    'platforms;android-35',
    'system-images;android-35;google_apis;x86_64'
)
# sdkmanager puede devolver codigo distinto de 0 aun con exito parcial; no usamos Stop aqui
$ErrorActionPreference = 'Continue'
& $sdkmanager --sdk_root=$SdKRoot @packages
$ErrorActionPreference = 'Stop'

Write-Host 'Aceptando licencias Android (stdin via cmd; puede tardar 1-2 min)...'
$yesPath = Join-Path $TempDir 'license-yes.txt'
# Varias lineas "y" — sdkmanager muestra varios acuerdos seguidos
[System.IO.File]::WriteAllLines($yesPath, (1..200 | ForEach-Object { 'y' }))
# En Windows, el .bat + Java suele leer bien la entrada redirigida desde cmd
$null = cmd.exe /c "type `"$yesPath`" | `"$sdkmanager`" --sdk_root=`"$SdKRoot`" --licenses"

Write-Host '== 5/5 AVD ludoteca_Pixel_API_35 =='
$avdmanager = Join-Path $SdKRoot 'cmdline-tools\latest\bin\avdmanager.bat'
$avdName = 'ludoteca_Pixel_API_35'
$listOut = & $avdmanager list avd 2>&1 | Out-String
if ($listOut -notmatch [regex]::Escape($avdName)) {
    & $avdmanager create avd -n $avdName -k 'system-images;android-35;google_apis;x86_64' -d 'pixel_6' --force
}

Write-Host @'

Listo. CIERRA y vuelve a abrir PowerShell (o VS Code / Cursor) para que PATH y ANDROID_SDK_ROOT se apliquen.

Comprueba:
  flutter doctor
  "%USERPROFILE%\Android\sdk\emulator\emulator.exe" -avd ludoteca_Pixel_API_35

Luego en tu proyecto:
  cd mobile
  flutter pub get
  flutter run

'@
