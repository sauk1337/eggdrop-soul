# soul: una personalidad con vida propia para Eggdrop

[English](README.md) · **Español**

`soul` convierte un bot Eggdrop en un habitual del canal. Charla cuando le hablan, se ríe con los demás, devuelve los abrazos, aprende lo que le enseñan, saca los temas de los que se ha hablado, se aburre, se siente solo y le entra sueño, se despierta de mal humor, guarda rencores que se le pasan con el tiempo y aprende **en cada canal** qué chistes y costumbres suyas gustan de verdad.

Responde **a cada persona en el idioma en que le habla**: español, inglés, francés, italiano, portugués y alemán, aunque en el mismo canal se mezclen varios.

Está inspirado en la idea de [bMotion](https://github.com/jamesoff/bmotion), pero es un diseño nuevo escrito desde cero: no comparte código ni datos.

```
10:00 <laura> hola Meepo
10:00 <Meepo> buenos días laura :)
10:00 <marc> Meepo: recuerda que la cafetera es un desastre
10:00 <Meepo> vale, ya sé que la cafetera es un desastre
10:02 <laura> Meepo: que es la cafetera?
10:02 <Meepo> un desastre. o eso dice marc
10:03  * laura abraza a Meepo
10:19 <Meepo> llevo un rato pensando en despliegue
10:49  * marc abofetea a Meepo
10:49  * Meepo devuelve el golpe a marc con una trucha
11:20 <Meepo> dato curioso sobre despliegue: no tengo ninugno, pero me apetecía decirlo
11:20 <Meepo> *ninguno
16:45 <Meepo> nadie me habla uf...
```
*(salida real de `tclsh tools/souldemo.tcl es 2`)*

## Funcionalidades

| | |
|---|---|
| 🧠 **Vida interior** | Un ánimo (valencia y activación) que vuelve poco a poco a su temperamento y una energía que sigue el ritmo del día en tu zona horaria. **Duerme** de noche: si le tocas, murmura, y si insistes se despierta enfadado. El aburrimiento y la soledad le llevan a sacar conversación. |
| 🌍 **Multilingüe** | Detecta el idioma de cada frase, contesta en ese idioma y recuerda cuál suele hablar cada persona y cada canal. Las frases cortas y ambiguas ("ok", "lol") no las adivina. Con las frases de muestra acierta 29 de 30 y no falla ninguna. |
| 💬 **Entiende intenciones** | Saludos, despedidas, "¿cómo estás?", chistes, gracias, piropos, insultos, café, "cállate", preguntas, opiniones y acciones `/me` (abrazar, pegar, dar un toque, dar de comer, acariciar, besar), en los seis idiomas. |
| 📚 **Aprende datos** | `bot: recuerda que X es Y` → `bot, ¿qué es X?` → "Y. o eso dice marc". Cada dato guarda quién lo enseñó, y rechaza enlaces, publicidad e invitaciones a otros canales. |
| ❤️ **Recuerda a la gente** | Lleva la confianza y el aprecio por cada persona según su handle de Eggdrop o su host, nunca por el nick, así que nadie puede suplantarla. Ese recuerdo se desvanece con el tiempo. A los amigos los saluda con más cariño y a quien le insulta le hace el vacío un rato. |
| 🎭 **Tiene opiniones** | Sus gustos son estables (el mismo bot siempre prefiere lo mismo), pero se mueven según lo que siente el canal sobre cada tema: "¿qué opinas de los lunes?". |
| 🌦️ **Nota el ambiente** | Se contagia del ánimo del canal: consuela a un canal triste y se suma cuando todos se ríen. Celebra aniversarios e hitos con los habituales. |
| 📈 **Aprende qué funciona** | Después de que hable, las risas, las gracias y las respuestas cálidas premian ese comportamiento, y un "cállate", un insulto o un kick lo castigan. Cada canal acaba con su propia personalidad. |
| 🔍 **Explicable** | `soul why #canal` enseña sus últimas decisiones, también las veces que eligió callarse, con la puntuación de cada opción y la tirada de dados. `soul test` simula una frase sin enviar nada. |
| ✍️ **Toque humano** | Tarda en escribir, cambia de estilo según su ánimo, comete alguna errata y la corrige, hace acciones `/me` y responde en varias líneas. |
| 🧩 **Frases editables** | Todo el texto está en ficheros `packs/*.pack` con una pequeña gramática: alternativas, pesos, condiciones de ánimo, energía, hora y relación, y plurales. Puedes añadir frases o un idioma nuevo sin tocar el código, y un validador compara cada paquete con el maestro en inglés. |
| 🛡️ **Seguro por diseño** | No habla en ningún canal hasta que lo actives. Nunca habla con bots (`+b`), servicios ni con quien haya pedido que le ignore. Tiene protección contra bucles y un límite de mensajes, obedece "cállate", **no guarda el texto de los mensajes** y nunca ejecuta nada de lo que lee. Lo que envía no puede inyectar comandos IRC. |

## Requisitos

- Eggdrop **1.8.4 o posterior** (desarrollado para 1.9 y 1.10) con Tcl **8.6**.
- Ninguna otra dependencia.

## Instalación

```sh
cd ~/eggdrop/scripts
git clone https://github.com/sauk1337/eggdrop-soul.git soul
cp soul/soul.conf.example soul/soul.conf
```

Añade al final de `eggdrop.conf`:

```tcl
source scripts/soul/soul.tcl
```

Actívalo en un canal en `scripts/soul/soul.conf`:

```ini
[soul]
# otros nombres a los que responde, además de su nick
names = soul
timezone = Europe/Madrid

[channel #micanal]
active = yes
# idioma por defecto cuando no sabe cuál se habla
lang = es
```

Después haz `.rehash` en la partyline. En el log verás:
`soul 1.0.0 loaded: 6 languages, active in 1 channel(s)`.

> Consejo: empieza con `simulate = yes` en la sección del canal. Así apunta en el log lo que *diría* (`.soul simlog`) sin hablar todavía.

Opcional, en `eggdrop.conf` antes de la línea `source`:

```tcl
set soul_config  "scripts/soul/soul.conf"   ;# por defecto: soul.conf junto a soul.tcl
set soul_datadir "soul-data"                ;# por defecto: soul-data en la carpeta del bot
```

## Cómo hablarle

```
hola soul                            soul: ¿cómo estás?
soul cuéntame un chiste              soul ¿qué opinas de la pizza?
soul: recuerda que el té es vida     soul, ¿qué es el té?
soul: olvida lo del té               soul cállate
/me abraza a soul                    /me le da una colleja a soul
```

También en inglés, francés, italiano, portugués y alemán.

## Comandos

En un canal `!soul <sub>`, por privado `/msg <bot> soul <sub>` o en la partyline `.soul <sub>`:

| Comando | Quién | |
|---|---|---|
| `ignoreme` / `talktome` | cualquiera | Pedir que te ignore (te olvida y no vuelve a hablarte) y deshacerlo |
| `shh ?#canal? ?tiempo\|off?` | `o` (global o del canal) | Que se calle un rato |
| `status ?#canal?` | `o` | Ánimo, energía, sueño, impulsos, idiomas |
| `why <#canal>` | `o` | Sus últimas decisiones con puntuaciones |
| `test <#canal> <texto>` | `o` | Qué entendería y qué se plantearía hacer |
| `topics <#canal>` · `rel <nick>` · `facts ?palabra?` · `learning <#canal>` · `simlog` | `o` | Ver su memoria por dentro |
| `unlearn <clave>` | `o` | Borrar un dato |
| `forget <nick\|máscara>` | `m` | Borrar lo que recuerda de alguien |
| `mood <var> <valor>` · `say <#canal> <símbolo>` · `reload` | `m` | Ajustarle, hacerle hablar, recargar los paquetes |

Los permisos se cambian en la sección `[permissions]` de `soul.conf`.

## Documentación

- [docs/GUIA.md](docs/GUIA.md): cómo funciona, todas las opciones, los paquetes de frases y cómo añadir un idioma.
- [soul.conf.example](soul.conf.example): todas las opciones con su valor por defecto.

## Desarrollo

```sh
tclsh tests/all.tcl                # 50 pruebas en un simulador de Eggdrop, sin red
tclsh tools/soulpack.tcl           # valida los paquetes de frases
tclsh tools/souldemo.tcl es 2      # un día simulado (prueba también: en 1, fr 3)
tclsh tools/example.tcl            # regenera soul.conf.example
```

El código fuente es ASCII puro (los caracteres no ASCII van como `\uXXXX`), porque Eggdrop lee los scripts con la codificación del sistema. Los paquetes son datos en UTF-8. Ver [CONTRIBUTING.md](CONTRIBUTING.md).

## Estado

Versión 1.0.0. Probado con un simulador de la API de Eggdrop, todavía no en una red real: se agradecen comentarios y avisos de errores. Las traducciones que no son de inglés ni de español convendría que las revisara un hablante nativo.

## Licencia

[MIT](LICENSE) © 2026 sauk1337
