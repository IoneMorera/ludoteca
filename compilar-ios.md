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

## Compilar en la nube (alternativa sin Mac potente)

Si tu Mac es muy antiguo o no puedes instalar el entorno, puedes compilar en la nube
usando un servicio CI/CD que tenga maquinas macOS.

### Opcion 1: Codemagic (recomendada para Flutter)

Codemagic esta especializado en Flutter y es la opcion mas sencilla.

**Plan gratuito**: 500 minutos/mes en maquinas macOS (suficiente para varias compilaciones).

1. Ve a https://codemagic.io y crea una cuenta (puedes usar GitHub/GitLab)
2. Conecta tu repositorio Git
3. Codemagic detecta automaticamente que es un proyecto Flutter
4. Configura el workflow:
   - **Platform**: iOS
   - **Build mode**: Release
   - **Xcode version**: Latest
5. Si quieres distribuir en la App Store, necesitaras subir:
   - Tu certificado de distribucion (.p12)
   - Tu provisioning profile
   - Estos se generan desde https://developer.apple.com/account (requiere cuenta de pago)
6. Pulsa **Start build**
7. Cuando termine, descarga el fichero `.ipa` desde Codemagic

> Para pruebas personales (sin App Store), puedes compilar en modo debug
> y descargar el .app para instalarlo manualmente via Xcode.

### Opcion 2: GitHub Actions

Si tu proyecto esta en GitHub, puedes configurar un workflow que compile en macOS.

1. Crea el fichero `.github/workflows/build-ios.yml` en tu repositorio:

```yaml
name: Build iOS

on:
  workflow_dispatch:  # Se ejecuta manualmente desde GitHub

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.2'
          channel: stable

      - name: Install dependencies
        working-directory: mobile
        run: |
          flutter pub get
          cd ios && pod install

      - name: Build iOS (sin firma)
        working-directory: mobile
        run: flutter build ios --release --no-codesign

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: ios-build
          path: mobile/build/ios/iphoneos/Runner.app
```

2. Ve a tu repositorio en GitHub > **Actions** > **Build iOS** > **Run workflow**
3. Cuando termine (~10-15 minutos), descarga el artefacto

> NOTA: El `--no-codesign` genera un build sin firmar. Para instalar en un dispositivo
> real o subir a la App Store, necesitas configurar los certificados de firma en el workflow.
> Esto requiere una cuenta Apple Developer de pago.

**Minutos gratuitos de GitHub Actions:**
- Repositorios publicos: ilimitado
- Repositorios privados: 2000 minutos/mes (los runners macOS consumen 10x, asi que son ~200 minutos reales)

---

## Resumen de costes

| Que quieres hacer | Coste | Necesitas Mac |
|-------------------|-------|---------------|
| Probar en simulador iOS | Gratis | Si |
| Probar en iPhone propio (7 dias) | Gratis | Si |
| Compilar en la nube (Codemagic/GitHub) | Gratis | No |
| Publicar en App Store | 99 USD/ano (Apple Developer) | Si (o nube) |

---

## Permisos iOS necesarios (Info.plist)

El fichero `mobile/ios/Runner/Info.plist` necesita estas descripciones de permisos
para que Apple permita el uso de camara, galeria, etc. Si no estan, hay que anadirlas:

```xml
<key>NSCameraUsageDescription</key>
<string>Ludoteca necesita acceso a la camara para escanear codigos de barras y reconocer juegos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Ludoteca necesita acceso a la galeria para seleccionar fotos de juegos</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Ludoteca necesita guardar fotos en tu galeria</string>
```

> Estos permisos se verificaran cuando compile el proyecto en el Mac. Si ya estan
> configurados por los plugins de Flutter, no hace falta anadirlos manualmente.
