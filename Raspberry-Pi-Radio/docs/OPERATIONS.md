# Operacion y recuperacion

## Entrar por SSH desde este PC

La tarjeta preparada instala la clave dedicada de Windows. Con la Pi encendida
y conectada por Ethernet al mismo router:

```powershell
ssh greylock-radio
```

El alias usa `radio@greylock-radio.local` y la clave
`%USERPROFILE%\.ssh\greylock_radio_ed25519`. La primera conexion pedira aceptar
la huella del equipo. Si el nombre `.local` aun no aparece durante el primer
arranque, busca la direccion `greylock-radio` en el router.

La Pi tambien conserva la IP fija secundaria `192.168.137.2`. Para conectarla
directamente al PC se necesita un puerto Ethernet o adaptador USB-Ethernet. En
PowerShell como administrador ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File tools\configure-direct-ethernet.ps1
ssh greylock-radio-direct
```

El PC usa `192.168.137.1` y la Pi `192.168.137.2`. Esta conexion directa permite
SSH sin router ni Wi-Fi, pero no proporciona Internet para instalar paquetes.

## Actualizar sin volver a grabar la tarjeta

Desde la carpeta `Raspberry-Pi-Radio` en este PC:

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy-to-pi.ps1
```

El despliegue copia el programa por SSH, ejecuta de nuevo los instaladores y
conserva la configuracion y todo el audio de `/srv/greylock-radio/media`.

## Estado

```bash
systemctl status greylock-radio --no-pager
systemctl status greylock-radio-kiosk --no-pager
journalctl -u greylock-radio -n 100 --no-pager
journalctl -u greylock-radio-kiosk -n 100 --no-pager
```

## Reiniciar

```bash
sudo systemctl restart greylock-radio
sudo systemctl restart greylock-radio-kiosk
```

## Copia de seguridad

```bash
sudo /opt/greylock-radio/scripts/backup.sh /home/radio
```

La copia contiene la configuracion y el audio. Copiala fuera de la tarjeta con
SFTP o SCP.

## Si el primer arranque no termina

Monta la particion `bootfs` en otro ordenador y abre
`greylock-firstboot.log`. Normalmente el problema sera falta de Internet o un
repositorio temporalmente inaccesible. Conecta Ethernet y vuelve a encender; el
script esta preparado para poder repetirse.

## Rutas

```text
/opt/greylock-radio/                 programa
/etc/greylock-radio/config.json      configuracion
/srv/greylock-radio/media/music      musica
/srv/greylock-radio/media/announcements avisos
/var/lib/greylock-radio              datos de Chromium
```
