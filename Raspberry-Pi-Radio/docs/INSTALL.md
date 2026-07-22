# Instalacion en Raspberry Pi 3B+

## Sistema base

Usa **Raspberry Pi OS Legacy Lite, 32-bit (Bookworm)**. La version Lite elimina
el escritorio que no necesitamos y la arquitectura de 32 bits consume menos
memoria en una Pi 3B+ de 1 GB. El instalador del proyecto agrega solamente X,
Openbox y Chromium para mostrar el panel.

Pagina oficial del sistema:
https://www.raspberrypi.com/software/operating-systems/

## Preparar una tarjeta desde Windows

El aprovisionador incluido borra una microSD, graba la imagen, conserva el
overlay `tft35a`, copia la aplicacion, instala la clave SSH del PC y deja
preparado el primer arranque. La
imagen usada para esta unidad es:

```text
2026-06-18-raspios-bookworm-armhf-lite.img.xz
SHA-256: 8a044f4c55feb9b0626ab2060a2eef15c3f57327dd610a0a4cac02cdb959166e
```

Ejecuta PowerShell como administrador y comprueba siempre el numero de disco:

```powershell
powershell -ExecutionPolicy Bypass -File tools\prepare-sd.ps1 `
  -ImagePath downloads\2026-06-18-raspios-bookworm-armhf-lite.img.xz `
  -DiskNumber 2 -DriveLetter E -Force
```

El script solo admite unidades USB de 8 a 64 GB y verifica el hash antes de
borrar nada. Copia la Wi-Fi actual de Windows, configura Ethernet y guarda las
credenciales nuevas en el escritorio del usuario.
Espera encontrar la clave publica en
`%USERPROFILE%\.ssh\greylock_radio_ed25519.pub`.

## Preparacion manual

1. Graba Raspberry Pi OS Legacy Lite 32-bit con Raspberry Pi Imager.
2. En la personalizacion usa:
   - Hostname: `greylock-radio`
   - Zona horaria: `America/New_York`
   - Usuario: el que vaya a administrar la Pi
   - SSH: activado
   - Wi-Fi: la red disponible en el lugar de uso
3. Arranca la Pi y entra por SSH.
4. Copia esta carpeta a la Pi.
5. Ejecuta:

```bash
cd Raspberry-Pi-Radio
sudo bash scripts/install.sh
sudo bash scripts/install-kiosk.sh
sudo reboot
```

El instalador puede ejecutarse de nuevo para actualizar el programa. Conserva
`/etc/greylock-radio/config.json` y todo lo que haya en
`/srv/greylock-radio/media`.

## TFT GPIO de esta unidad

La tarjeta original identifico la pantalla como:

```text
Producto: SuziePi/GoodTFT LCD35
Controlador de video: ILI9486
Controlador tactil: ADS7846
Overlay: tft35a (LCD-show)
Resolucion: 480x320
Rotacion: 90 grados
Framebuffer de X: /dev/fb1
```

El aprovisionador instala `hardware/tft35a.dtbo`, activa SPI e I2C, configura
Xorg para el framebuffer secundario y aplica la calibracion tactil oficial.
No uses esta configuracion con otro modelo de pantalla sin cambiar el overlay.

Si la tarjeta ya esta grabada, se puede reparar sin formatearla:

```powershell
powershell -ExecutionPolicy Bypass -File tools\repair-boot-sd.ps1 -DriveLetter E
```

## Primer arranque

El primer arranque instala paquetes desde los repositorios de Raspberry Pi OS.
Usa la misma Wi-Fi con la que se preparo la tarjeta o conecta Ethernet al router.
La TFT permanece blanca durante esta fase porque su overlay se activa solamente
cuando la instalacion termina.
No cortes la corriente. El proceso
guarda su progreso en `/boot/firmware/greylock-firstboot.log`, elimina la
configuracion temporal de arranque y se reinicia cuando termina.

Si la TFT no abre el panel despues de 25 minutos, entra con
`ssh greylock-radio` o conecta HDMI y consulta [OPERATIONS.md](OPERATIONS.md).
