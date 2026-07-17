# Operacion y recuperacion

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
