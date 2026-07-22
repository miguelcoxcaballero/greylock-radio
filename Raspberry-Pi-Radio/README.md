# Greylock Raspberry Pi Radio

Sistema de radio local para una Raspberry Pi 3B+ con pantalla tactil TFT de
3,5 pulgadas. Reproduce musica automaticamente por carpetas, intercala avisos
grabados y permite hablar en directo con un microfono conectado a la Pi.

## Lo que incluye

- Panel HTML local, usable desde la pantalla de la Pi o desde otro equipo de la red.
- Rotacion automatica: toma una cancion de cada carpeta por turno.
- Orden aleatorio dentro de cada carpeta, sin repetir hasta agotar su contenido.
- Avisos grabados manuales, automaticos cada N canciones y programables por hora.
- Modo de microfono en directo que interrumpe la musica y la reanuda al terminar.
- Inicio automatico mediante `systemd`.
- Instalador de pantalla completa para Chromium y la TFT GPIO.
- Copias de seguridad, diagnostico de audio y pruebas sin dependencias de Python.

## Hardware previsto

- Raspberry Pi 3B+ y microSD de 16 GB o mas.
- Pantalla SuziePi TFT SPI de 3,5 pulgadas, 480x320, con ILI9486 y tactil ADS7846.
- Adaptador de sonido USB con entrada de microfono y salida de linea.
- Microfono compatible y amplificador, mezclador o sistema PA.
- Fuente estable de 5 V / 2,5 A para la Pi 3B+.

La salida de la Pi no debe alimentar directamente altavoces pasivos. Conecta la
salida de linea del adaptador USB a un amplificador o al sistema de megafonia.

## Puesta en marcha

La tarjeta preparada por este proyecto usa Raspberry Pi OS Lite de 32 bits. Al
insertarla y encender la Pi:

1. Dejala al alcance de la misma Wi-Fi usada al preparar la tarjeta o conecta Ethernet al router.
2. Espera entre 10 y 25 minutos. Instalara audio, navegador y servicios, y se reiniciara.
3. El panel se abrira automaticamente en la TFT.
4. Desde otro dispositivo de la misma red abre `http://greylock-radio.local:8080`.
5. Desde el PC preparado entra por SSH con `ssh greylock-radio`.

El primer arranque no carga la TFT. Esto permite recuperar la Pi por Ethernet
o Wi-Fi aunque el controlador de pantalla falle. La TFT se activa
automaticamente al terminar la instalacion y aparece despues del reinicio.

Para preparar otra tarjeta manualmente, consulta [docs/INSTALL.md](docs/INSTALL.md).

## Carpetas de audio

Tras instalar, copia los archivos a:

```text
/srv/greylock-radio/media/music/
  Morning/
  Activity/
  Evening/
/srv/greylock-radio/media/announcements/
```

Pulsa **Rescan** en la web despues de copiar o borrar archivos. Se aceptan MP3,
WAV, OGG, FLAC, M4A, AAC y OPUS. Los detalles estan en
[docs/MEDIA-AND-SCHEDULES.md](docs/MEDIA-AND-SCHEDULES.md).

## Operacion y seguridad

El panel no tiene contrasena: esta pensado para una red local de confianza. No
expongas el puerto 8080 directamente a Internet. El microfono en directo es el
que esta conectado fisicamente a la Raspberry Pi; el navegador no transmite el
microfono del telefono.

Consulta [docs/AUDIO.md](docs/AUDIO.md) para elegir dispositivos y
[docs/OPERATIONS.md](docs/OPERATIONS.md) para registros, copias y recuperacion.
Las actualizaciones posteriores se pueden enviar por SSH con
`tools/deploy-to-pi.ps1`; no requieren volver a grabar la microSD.
