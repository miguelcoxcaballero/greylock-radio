# Audio y microfono

## Conexion recomendada

Usa un adaptador de sonido USB que tenga **entrada de microfono** y **salida de
linea/auriculares**. Conecta la salida al amplificador o mezclador del campamento.
La Pi 3B+ no ofrece una entrada analogica de microfono.

Separa el microfono de los altavoces y empieza con volumen bajo para evitar
acoples. El modo directo conecta la entrada ALSA a la salida ALSA; no graba ni
sube la voz a Internet.

## Encontrar los dispositivos

En la Pi ejecuta:

```bash
sudo /opt/greylock-radio/scripts/diagnose-audio.sh
```

Los dispositivos de captura aparecen bajo `arecord -l` y los de salida bajo
`aplay -l`. Algunos nombres habituales son:

```text
default
plughw:CARD=Device,DEV=0
plughw:CARD=Headphones,DEV=0
```

Para la musica, `mpv --audio-device=help` muestra nombres como
`alsa/default` o `alsa/plughw:CARD=Device,DEV=0`.

Introduce esos valores en **Station settings**:

- `mpv output`: salida para musica y avisos grabados.
- `Live microphone input`: entrada del microfono para `arecord`.
- `Live speaker output`: salida para `aplay`.

## Prueba en directo

Antes de usar los altavoces principales, baja su volumen y ejecuta:

```bash
sudo /opt/greylock-radio/scripts/diagnose-audio.sh --test-live
```

Pulsa `Ctrl+C` para terminar. Si se oye entrecortado, usa dispositivos `plughw`
del mismo adaptador y conserva 48 kHz, mono. Tras cambiar el JSON directamente,
reinicia con `sudo systemctl restart greylock-radio`.
