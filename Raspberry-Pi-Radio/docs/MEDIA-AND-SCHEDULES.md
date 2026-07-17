# Musica y avisos

## Rotacion por carpetas

Cada subcarpeta de `music` es una categoria. Por ejemplo:

```text
music/
  01-morning/
    wake-up.mp3
    breakfast.mp3
  02-general/
    song-a.flac
    song-b.mp3
  03-evening/
    taps.ogg
```

La radio elige una cancion de `01-morning`, luego una de `02-general`, luego una
de `03-evening` y vuelve a empezar. Dentro de cada carpeta baraja las canciones.

## Avisos grabados

Copia todos los avisos a `media/announcements`. En la web puedes reproducir uno
inmediatamente. El aviso interrumpe la cancion actual y la rotacion continua con
la siguiente cancion cuando termina.

`announcement_every_songs` controla los avisos automaticos:

- `0`: no intercala avisos automaticamente.
- `4`: reproduce un aviso aleatorio despues de cada cuatro canciones completas.

## Avisos programados

Edita `/etc/greylock-radio/config.json`. Los dias usan 0 para lunes y 6 para
domingo:

```json
"scheduled_announcements": [
  {
    "file": "announcements/lunch-in-five.mp3",
    "time": "11:55",
    "days": [0, 1, 2, 3, 4, 5, 6],
    "enabled": true
  },
  {
    "file": "announcements/sunday-service.mp3",
    "time": "09:15",
    "days": [6],
    "enabled": true
  }
]
```

Guarda y ejecuta `sudo systemctl restart greylock-radio`. Las horas usan la zona
`America/New_York` configurada en la Pi.
