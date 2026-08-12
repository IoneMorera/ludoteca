# Compilar Ludoteca para iOS

## Requisitos minimos del Mac

| Requisito | Minimo | Recomendado |
|-----------|--------|-------------|
| macOS | 13 (Ventura) | 14 (Sonoma) o superior |
| RAM | 8 GB | 16 GB |
| Espacio libre en disco | 20 GB | 30 GB |
| Procesador | Intel (2018+) o Apple Silicon (M1/M2/M3) | Apple Silicon |

### Como comprobar tu Mac

1. Haz clic en el menu Apple () > **Acerca de este Mac**
2. Anota la **version de macOS**, el **chip/procesador** y la **RAM**
3. Comprueba el espacio libre: () > **Ajustes del Sistema** > **General** > **Almacenamiento**

---

## Escenario A: Mac con macOS 13 (Ventura) o superior

Este es el camino ideal. Sigue los pasos de instalacion directamente.

---

## Escenario B: Mac con macOS 12 (Monterey) que NO se puede actualizar

### Opcion B1: Forzar la actualizacion con OpenCore Legacy Patcher

Algunos Macs antiguos que Apple ya no soporta oficialmente pueden actualizarse usando
**OpenCore Legacy Patcher** (OCLP):

1. Ve a https://dortania.github.io/OpenCore-Legacy-Patcher/
2. Comprueba si tu modelo de Mac esta en la lista de compatibilidad
3. Si lo esta, sigue la guia para instalar macOS Ventura/Sonoma
4. Una vez actualizado, sigue el **Escenario A**

> OCLP es un proyecto de codigo abierto muy usado y estable, pero haz una copia de seguridad
> de tu Mac antes de intentarlo.

### Opcion B2: Usar Xcode 14 en Monterey (con limitaciones)

Si no puedes actualizar, Xcode 14 (la ultima version compatible con Monterey) permite
compilar para iOS pero con estas limitaciones:

- Solo SDK de iOS 16 (no 17 ni 18)
- Necesitas una version de Flutter compatible (3.10.x o similar)
- La app funcionara en iPhones con iOS 16+

Pasos:
1. Descarga **Xcode 14.3.1** desde https://developer.apple.com/download/all/ (necesitas Apple ID)
2. Instala Flutter **3.10.6** en lugar de la ultima version
3. Sigue los pasos de instalacion normales (ver mas abajo)

### Opcion B3: Compilar en la nube (sin depender del Mac)

La opcion mas limpia si tu Mac es muy antiguo. Ver la seccion **"Compilar en la nube"** al final
de este documento.

---

## Instalacion del entorno de desarrollo

### Paso 1: Instalar Xcode

1. Abre la **App Store** en tu Mac
2. Busca **"Xcode"** e instala (pesa ~12 GB, tardara un rato)
3. Una vez instalado, abre Xcode una vez
4. Acepta la licencia cuando te lo pida
5. Abre Terminal y ejecuta:

```bash
sudo xcode-select --install
```

6. Verifica la instalacion:

```bash
xcodebuild -version
```

Deberia mostrar algo como: `Xcode 15.x` o `Xcode 16.x`

### Paso 2: Instalar Flutter SDK

```bash
# Descargar Flutter (Apple Silicon / M1+)
cd ~
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.29.2-stable.zip
unzip flutter_macos_arm64_3.29.2-stable.zip

# Si tu Mac es Intel, usa esta URL en su lugar:
# curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.29.2-stable.zip
# unzip flutter_macos_3.29.2-stable.zip

# Anadir Flutter al PATH
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Verificar
flutter --version
```

> Nota: Las URLs de descarga pueden cambiar. Consulta la version actual en
> https://docs.flutter.dev/get-started/install/macos

### Paso 3: Instalar CocoaPods

CocoaPods es el gestor de dependencias de iOS (equivalente a composer o npm):

```bash
sudo gem install cocoapods
```

Si da error de permisos o version de Ruby:
```bash
brew install cocoapods
```

> Si no tienes Homebrew instalado:
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```

### Paso 4: Verificar todo con Flutter Doctor

```bash
flutter doctor
```

Deberia mostrar checks verdes para:
```
[✓] Flutter (Channel stable, 3.x.x)
[✓] Android toolchain - (si tienes Android SDK, opcional)
[✓] Xcode - develop for iOS and macOS
[✓] Chrome - develop for the web
[✓] CocoaPods - (version x.x.x)
```

Lo importante es que **Xcode** y **CocoaPods** aparezcan con check verde.

---

## Copiar el proyecto al Mac

### Opcion A: Git (recomendado)

```bash
git clone https://github.com/TU_USUARIO/ludoteca.git
cd ludoteca/mobile
```

### Opcion B: USB o transferencia directa

1. Copia la carpeta del proyecto a una memoria USB
2. Conéctala al Mac y copia a donde prefieras (ej: `~/Proyectos/ludoteca`)
3. Abre Terminal:

```bash
cd ~/Proyectos/ludoteca/mobile
```

---

## Compilar y probar

### Instalar dependencias

```bash
cd mobile
flutter pub get
cd ios
pod install
cd ..
```

> Si `pod install` da error, prueba:
> ```bash
> cd ios
> pod deintegrate
> pod install --repo-update
> cd ..
> ```

### Probar en el simulador de iOS (gratis, sin cuenta Apple Developer)

```bash
# Ver simuladores disponibles
flutter devices

# Ejecutar en un simulador
flutter run -d "iPhone 16"
```

> Si no aparecen simuladores, abrelos desde Xcode:
> **Xcode > Settings > Platforms > + > iOS xx** (descarga un simulador)

### Probar en un iPhone fisico (gratis, caduca cada 7 dias)

1. Conecta tu iPhone al Mac con un cable USB/Lightning
2. En el iPhone, ve a **Ajustes > Privacidad y seguridad > Modo de desarrollador** y activalo
3. Abre el proyecto en Xcode:

```bash
open ios/Runner.xcworkspace
```

4. En Xcode:
   - En el panel izquierdo, haz clic en **Runner** (icono azul)
   - Ve a la pestana **Signing & Capabilities**
   - En **Team**, selecciona tu **Apple ID personal** (anadelo si no aparece)
   - Xcode mostrara un "provisioning profile" automatico
5. Selecciona tu iPhone como destino (arriba del todo en Xcode)
6. Pulsa el boton **Play** (triangulo) para compilar e instalar

> La primera vez te pedira que confies en el desarrollador en el iPhone:
> **Ajustes > General > Gestion de dispositivos VPN > tu Apple ID > Confiar**

> IMPORTANTE: Sin cuenta Apple Developer de pago, la app caduca cada 7 dias.
> Tendras que volver a instalarla desde Xcode.

### Compilar IPA para distribucion (requiere Apple Developer Account - 99 USD/ano)

```bash
flutter build ipa --release
```

Esto genera un fichero `.ipa` en `build/ios/ipa/`. Para subirlo a la App Store:

1. Abre **Transporter** (app gratuita de Apple, descargala de la App Store del Mac)
2. Arrastra el fichero `.ipa` a Transporter
3. Transporter lo sube a App Store Connect
4. Ve a https://appstoreconnect.apple.com para completar la ficha y enviar a revision

---

## Compilar en la nube (sin Mac fisico a diario)

Objetivo: cada dia (o cada push) generar un `.ipa` firmado en un Mac virtual
y instalarlo en el iPhone con **TestFlight** o **firma ad hoc**.

```
Windows / Linux (tu PC)
        |
        |  git push  o  "Start build"
        v
  Codemagic / GitHub Actions (macOS en la nube)
        |
        |  flutter build ipa + firma
        v
     .ipa firmado
        |
   +----+----+
   |         |
TestFlight   Ad hoc
   |         |
iPhone     iPhone (UDID registrado)
```

### Lo que SI y NO necesitas

| Necesitas | No necesitas |
|-----------|--------------|
| Cuenta **Apple Developer** de pago (99 USD/ano) | Mac fisico a diario |
| App creada en App Store Connect | Xcode instalado en tu PC |
| Certificados + perfiles de firma (una vez) | Cable USB cada vez (con TestFlight) |
| Repo Git (GitHub/GitLab/Bitbucket) | Compilar localmente |

> Sin Apple Developer de pago **no** puedes firmar un `.ipa` instalable de forma
> estable. La firma gratis de 7 dias solo funciona desde Xcode con un Mac y el iPhone
> conectado.

### Paso previo (una sola vez): certificados y perfiles

Hazlo desde cualquier navegador en https://developer.apple.com/account
(si no tienes Mac, puedes generar claves con OpenSSL en Windows, o dejar que
Codemagic las cree por ti — recomendado).

#### Conceptos rapidos

| Pieza | Para que sirve |
|-------|----------------|
| **Certificate** (.p12) | Firma digital de Apple (quien eres) |
| **App ID** | Identificador de la app (`com.tuempresa.ludoteca`) |
| **Provisioning Profile** | Une certificado + App ID + dispositivos (ad hoc) o App Store |
| **Bundle ID** | Debe coincidir con `PRODUCT_BUNDLE_IDENTIFIER` en iOS |

#### Camino A — Codemagic gestiona todo (mas facil)

1. En Codemagic: **Teams > Personal account > Code signing identities > iOS**
2. Conecta tu Apple Developer con **App Store Connect API key** (ver mas abajo)
3. Activa **Automatic code signing**
4. Codemagic crea/renueva certificados y perfiles por ti

#### Camino B — Manual (sirve para GitHub Actions o Codemagic)

1. En Apple Developer > **Certificates**:
   - Crea **Apple Distribution** (para TestFlight / App Store / ad hoc)
   - Descarga el `.cer` y exporta a `.p12` (desde Keychain en un Mac, o con
     OpenSSL si generaste la CSR a mano)
2. En **Identifiers**: crea el App ID con el Bundle ID de Ludoteca
3. En **Profiles**:
   - **App Store Connect** → para TestFlight / App Store
   - **Ad Hoc** → para instalar sin TestFlight (hay que registrar el UDID del iPhone)
4. Guarda el `.p12` + password + `.mobileprovision` como secretos del CI

#### App Store Connect API key (recomendada)

Sirve para que el CI suba el IPA a TestFlight sin tu Apple ID/password.

1. https://appstoreconnect.apple.com > **Users and Access** > **Integrations** > **App Store Connect API**
2. Crea una key con rol **Admin** o **App Manager**
3. Descarga el `.p8` (solo una vez) y anota:
   - **Key ID**
   - **Issuer ID**
4. Guarda Key ID, Issuer ID y el contenido del `.p8` como secretos

#### Registrar el iPhone (solo si usas ad hoc)

1. En el iPhone: **Ajustes > General > Informacion > Identificador** (UDID),
   o conéctalo una vez a un Mac / usa https://udid.tech
2. En Apple Developer > **Devices** > añade el UDID
3. Regenera el perfil **Ad Hoc** incluyendo ese dispositivo

---

### Opcion 1: Codemagic (recomendada para Flutter)

Especializado en Flutter. Plan gratis: **500 min/mes** en macOS M2
(suficiente para ~15–30 builds de esta app).

#### Alta y conexion del repo

1. https://codemagic.io — entra con GitHub/GitLab
2. **Add application** > elige el repo `ludoteca`
3. Project type: **Flutter**
4. Project path: `mobile` (importante: el Flutter no esta en la raiz)

#### Workflow basico con firma + TestFlight

Crea `mobile/codemagic.yaml` (o configuralo en la UI; el yaml es reproducible):

```yaml
workflows:
  ios-release:
    name: iOS Release
    max_build_duration: 60
    instance_type: mac_mini_m2
    integrations:
      app_store_connect: Ludoteca  # nombre de la integracion API key en Codemagic
    environment:
      flutter: 3.29.2
      xcode: latest
      cocoapods: default
      vars:
        BUNDLE_ID: "com.tuempresa.ludoteca"  # cambia por el Bundle ID real
      ios_signing:
        distribution_type: app_store
        bundle_identifier: $BUNDLE_ID
    scripts:
      - name: Get Flutter packages
        script: |
          cd mobile
          flutter pub get
      - name: Install pods
        script: |
          cd mobile/ios
          pod install
      - name: Set up code signing
        script: xcode-project use-profiles
      - name: Build IPA
        script: |
          cd mobile
          flutter build ipa --release \
            --export-options-plist=/Users/builder/export_options.plist
    artifacts:
      - mobile/build/ios/ipa/*.ipa
      - mobile/build/ios/iphoneos/*.app
    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: true
        # submit_to_app_store: false
```

#### Flujo diario con Codemagic

1. Haces cambios en Windows y `git push`
2. En Codemagic: **Start new build** (o dispara automatico en push a `main`)
3. En ~10–20 min tienes el `.ipa` y, si configuraste publishing, ya esta en TestFlight
4. En el iPhone abres **TestFlight**, actualizas Ludoteca e instalas

#### Ad hoc en Codemagic

Cambia en el yaml:

```yaml
ios_signing:
  distribution_type: ad_hoc
  bundle_identifier: $BUNDLE_ID
```

Y en `publishing` quita App Store Connect; descarga el `.ipa` desde **Artifacts**
e instalalo con:

- **Apple Configurator** / Finder (desde un Mac puntual), o
- Un servicio tipo Diawi / Installonair (enlace HTTPS al `.ipa`), o
- Escaneo QR si Codemagic te da enlace de instalacion

> Ad hoc: cada iPhone nuevo = registrar UDID + regenerar perfil + rebuild.

---

### Opcion 2: GitHub Actions (runner macOS)

Si el repo ya esta en GitHub. Los runners `macos-latest` / `macos-14` tienen Xcode.

**Cuota**: repos privados → 2000 min/mes, pero macOS cuenta **x10**
(≈ **200 min reales**). Un build iOS suele gastar 10–20 min facturados como 100–200.
Para uso diario intenso, Codemagic suele salir mejor en el plan free.

#### Secretos a crear en el repo

GitHub > Settings > Secrets and variables > Actions:

| Secreto | Contenido |
|---------|-----------|
| `BUILD_CERTIFICATE_BASE64` | `.p12` en base64 |
| `P12_PASSWORD` | Password del `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` en base64 |
| `KEYCHAIN_PASSWORD` | Password inventada para el keychain temporal |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Contenido del `.p8` en base64 |

En PowerShell (Windows), para convertir a base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificado.p12")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("perfil.mobileprovision")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXX.p8")) | Set-Clipboard
```

#### Workflow completo: IPA firmado + TestFlight

Crea `.github/workflows/build-ios.yml`:

```yaml
name: Build iOS IPA

on:
  workflow_dispatch:  # manual desde la pestaña Actions
  # push:
  #   branches: [main]
  #   paths: ['mobile/**']

jobs:
  build:
    runs-on: macos-14
    defaults:
      run:
        working-directory: mobile

    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.2'
          channel: stable
          cache: true

      - name: Install Apple certificate and provisioning profile
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          BUILD_PROVISION_PROFILE_BASE64: ${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db

          echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH
          echo -n "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode -o $PP_PATH

          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          security import $CERTIFICATE_PATH -P "$P12_PASSWORD" -A \
            -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" \
            $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH

          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          # El UUID del perfil se usa como nombre de fichero
          PP_UUID=$(security cms -D -i $PP_PATH | plutil -extract UUID raw -)
          cp $PP_PATH ~/Library/MobileDevice/Provisioning\ Profiles/$PP_UUID.mobileprovision
        working-directory: .

      - name: Flutter pub get + pods
        run: |
          flutter pub get
          cd ios && pod install

      - name: Build IPA
        run: |
          flutter build ipa --release \
            --export-options-plist=ios/ExportOptions.plist

      - name: Upload IPA artifact
        uses: actions/upload-artifact@v4
        with:
          name: ludoteca-ipa
          path: mobile/build/ios/ipa/*.ipa
          if-no-files-found: error

      - name: Upload to TestFlight
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_BASE64: ${{ secrets.APP_STORE_CONNECT_API_KEY_BASE64 }}
        run: |
          mkdir -p private_keys
          echo -n "$APP_STORE_CONNECT_API_KEY_BASE64" | base64 --decode \
            > private_keys/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8
          xcrun altool --upload-app --type ios \
            -f build/ios/ipa/*.ipa \
            --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
            --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
```

#### `ExportOptions.plist` (en `mobile/ios/`)

Para **TestFlight / App Store**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>uploadSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>TU_TEAM_ID</string>
</dict>
</plist>
```

Para **ad hoc**, cambia el method:

```xml
  <key>method</key>
  <string>ad-hoc</string>
```

Y usa el provisioning profile **Ad Hoc** en los secretos.

> `TU_TEAM_ID` esta en https://developer.apple.com/account > Membership details.

#### Build sin firmar (solo CI / artefacto, NO instalable en iPhone)

Util para comprobar que el proyecto compila, pero **no** sirve para el dia a dia en dispositivo:

```yaml
- name: Build iOS (sin firma)
  working-directory: mobile
  run: flutter build ios --release --no-codesign
```

---

### Como instalar el `.ipa` en el iPhone

#### Via TestFlight (recomendado para uso diario)

Ventajas: no hace falta cable, UDID, ni regenerar perfiles al cambiar de iPhone.
Hasta **100 testers externos** (con review corta) o internos del equipo.

1. En App Store Connect crea la app (Bundle ID = el de Ludoteca)
2. El CI sube el `.ipa` (Codemagic publishing o `xcrun altool` / `fastlane pilot`)
3. Espera el procesamiento (~5–30 min): estado **Ready to Test**
4. En el iPhone instala la app **TestFlight** (App Store)
5. Acepta la invitacion (email o link publico interno)
6. Instala / actualiza Ludoteca desde TestFlight

Flujo diario tipico:

```
codigo → push → CI build (~15 min) → TestFlight procesa → actualizas en el iPhone
```

#### Via firma ad hoc

Ventajas: no pasa por revision de TestFlight; el `.ipa` se instala directo.
Limites: max **100 dispositivos** registrados/año; cada dispositivo nuevo requiere
añadir UDID y **regenerar** el perfil.

Formas de instalar el `.ipa` ad hoc:

1. **Enlace HTTPS** (Diawi, Installonair, o el propio Codemagic): abres el link
   en Safari del iPhone y aceptas instalar
2. **Apple Configurator 2** o Finder en un Mac prestado (una vez)
3. **Xcode** > Devices and Simulators > arrastrar el `.ipa` (si tienes Mac puntual)

> No puedes instalar un `.ipa` ad hoc / TestFlight arrastrandolo como un APK de Android
> desde el explorador de Windows. Hace falta Safari (enlace firmado) o un Mac/herramienta.

---

### Comparativa rapida

| | Codemagic | GitHub Actions macOS |
|--|-----------|----------------------|
| Facilidad Flutter | Muy alta | Media |
| Firma automatica | Excelente (API key) | Manual con secretos |
| Subida a TestFlight | 1 clic / yaml | `altool` o fastlane |
| Minutos free | 500 macOS reales | ~200 macOS efectivos (privado) |
| Recomendado si... | Quieres olvidarte del Mac | Ya vives en GitHub Actions |

### Checklist "sin Mac a diario"

1. [ ] Apple Developer Program activo (99 USD/ano)
2. [ ] App creada en App Store Connect con el Bundle ID correcto
3. [ ] App Store Connect API key creada
4. [ ] Codemagic **o** GitHub Actions con firma configurada
5. [ ] Primer build verde → `.ipa` generado
6. [ ] Build publicado en TestFlight (o perfil ad hoc + UDID)
7. [ ] TestFlight instalado en el iPhone y Ludoteca visible
8. [ ] A partir de ahi: solo `git push` / "Start build" desde Windows

---

## Resumen de costes

| Que quieres hacer | Coste | Necesitas Mac |
|-------------------|-------|---------------|
| Probar en simulador iOS | Gratis | Si |
| Probar en iPhone propio (7 dias) | Gratis | Si (cable + Xcode) |
| Compilar `.ipa` en la nube a diario | Gratis / plan CI | No |
| Instalar via TestFlight o ad hoc | Incluido en Apple Developer | No (solo iPhone) |
| Publicar en App Store | 99 USD/ano (Apple Developer) | No (CI + App Store Connect) |

---

## Permisos iOS necesarios (Info.plist)

El fichero `mobile/ios/Runner/Info.plist` necesita descripciones de permisos
para que Apple permita el uso de camara, galeria, etc.

Estos permisos ya estan configurados en el proyecto:

```xml
<key>NSCameraUsageDescription</key>
<string>Ludoteca necesita acceso a la camara para escanear codigos de barras y reconocer juegos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Ludoteca necesita acceso a la galeria para seleccionar fotos de juegos</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Ludoteca necesita guardar fotos en tu galeria</string>
```

> No hace falta anadirlos manualmente, ya se incluyeron en `Info.plist`.
