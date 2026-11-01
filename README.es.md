<div align="center">

# 🌱 soul

### Una personalidad con vida propia para Eggdrop

*Charla, se ríe, aprende, duerme, guarda rencores y responde a cada uno en su idioma.*

[![Eggdrop](https://img.shields.io/badge/Eggdrop-1.8.4%2B-blue)](https://www.eggheads.org/)
[![Tcl](https://img.shields.io/badge/Tcl-8.6-orange)](https://www.tcl-lang.org/)
[![Idiomas](https://img.shields.io/badge/idiomas-en%20%C2%B7%20es%20%C2%B7%20fr%20%C2%B7%20it%20%C2%B7%20pt%20%C2%B7%20de-brightgreen)](#-idiomas)
[![Pruebas](https://img.shields.io/badge/pruebas-51%20OK-success)](#-desarrollo)
[![Licencia](https://img.shields.io/badge/licencia-MIT-lightgrey)](LICENSE)

[English](README.md) · **Español**

</div>

---

`soul` convierte un bot Eggdrop en **un habitual más del canal**. Contesta cuando le hablan, se ríe con los demás, devuelve los abrazos, aprende lo que le enseñan, saca los temas de los que se ha hablado, se aburre, se siente solo y le entra sueño, se despierta de mal humor, guarda rencores que se le acaban pasando y aprende **en cada canal** qué chistes y costumbres suyas gustan de verdad.

Un solo script, sin dependencias y seguro por diseño. Inspirado en la idea de [bMotion](https://github.com/jamesoff/bmotion), pero escrito desde cero: no comparte código ni datos.

## 📑 Índice

- [Míralo en acción](#-míralo-en-acción)
- [Funcionalidades](#-funcionalidades)
- [Instalación](#-instalación)
- [Cómo hablarle](#%EF%B8%8F-cómo-hablarle)
- [Comandos](#%EF%B8%8F-comandos)
- [Configuración](#%EF%B8%8F-configuración)
- [Idiomas](#-idiomas)
- [Seguridad y privacidad](#%EF%B8%8F-seguridad-y-privacidad)
- [Desarrollo](#-desarrollo)

## 👀 Míralo en acción

Salida real de `tclsh tools/souldemo.tcl es 2`, un día simulado que no necesita red:

```
10:00 <laura> hola Meepo
10:00 <Meepo> buenos días laura :)
10:00 <laura> Meepo: como estas?
10:00 <Meepo> bien, aquí andamos
10:00 <marc> Meepo: recuerda que la cafetera es un desastre
10:00 <Meepo> vale, ya sé que la cafetera es un desastre
10:02 <laura> Meepo: que es la cafetera?
10:02 <Meepo> un desastre. o eso dice marc
10:02 <marc> Meepo: cuentame un chiste
10:02 <Meepo> me compré un diccionario de sinónimos...
10:02 <Meepo> es terrible, y además es terrible
10:03  * laura abraza a Meepo
10:19 <Meepo> llevo un rato pensando en despliegue
10:49 <marc> Meepo eres un inutil
10:49 <Meepo> mira quién habla
10:49  * marc abofetea a Meepo
10:49  * Meepo devuelve el golpe a marc con una trucha
10:49 <laura> Meepo: callate
10:49 <Meepo> ok... *suspira*
11:20 <Meepo> dato curioso sobre despliegue: no tengo ninugno, pero me apetecía decirlo
11:20 <Meepo> *ninguno
16:29 <laura> Meepo: toma un cafe
16:29 <Meepo> ¡café! gracias laura ^^
16:45 <Meepo> nadie me habla uf...
```

Al día siguiente, cada uno en su idioma:

```
09:30 <joao> olá Meepo, tudo bem com você?
09:30 <Meepo> e aí joao, tudo bem?
09:30 <klaus> hallo Meepo, wie geht es dir?
09:30 <Meepo> gut, und dir, klaus?
09:31 <chloe> salut Meepo, ça va ?
09:31 <Meepo> bien, et toi chloe ?
```

## ✨ Funcionalidades

### 🧠 Vida interior
- **Ánimo** en dos dimensiones: lo bien que se siente y lo activo que está. Lo que pasa en el canal lo mueve, y poco a poco vuelve a su temperamento.
- **Energía** que sigue la hora del día en tu zona horaria. Hablar le cansa; el café y dormir le recuperan.
- **Duerme** de noche: si le tocan murmura *zzz*, y al tercer toque se despierta molesto. Al levantarse da los buenos días.
- **Aburrimiento y soledad**: tras un buen rato de silencio saca conversación, comenta un tema o un dato, o pregunta si hay alguien.

### 💬 Entiende a la gente
- **Intenciones en seis idiomas**: saludos, despedidas, *¿cómo estás?*, chistes, gracias, piropos, insultos, cariño, café, *cállate*, preguntas y opiniones.
- **Acciones `/me`**: abrazos, bofetadas, toques, comida, caricias y besos tienen cada uno su reacción.
- **Sentimiento y risas**: léxicos, emoticonos y negación simple, así que *no está mal* no cuenta como algo malo.
- **Saber cuándo le hablan**: `soul: ...`, una mención al final de la frase, una acción o un privado.

### 📚 Aprende y recuerda
- **Datos**: `soul: recuerda que X es Y`, y luego `soul, ¿qué es X?` responde *"Y. o eso dice marc"*. Cada dato guarda quién lo enseñó. Rechaza enlaces, publicidad e invitaciones a canales.
- **Personas**: confianza y aprecio por cada uno según su handle de Eggdrop o su host, nunca por el nick, así que cambiarse el nick no le engaña. A los amigos los saluda con más cariño y a quien le insulta le hace el vacío un rato. Todo se desvanece con el tiempo.
- **Temas del canal**: las palabras a las que vuelve una y otra vez el canal, sin guardar ninguna frase. Las usa para sacar conversación.
- **Aniversarios e hitos**: *"hace 1 año que nos conocimos"*, y celebraciones a las 100, 500 y 1000 interacciones.

### 🎭 Carácter propio
- **Opiniones**: gustos estables (el mismo bot siempre prefiere lo mismo) que cambian según lo que siente el canal sobre cada tema. Pregúntale *"¿qué opinas de los lunes?"*.
- **Contagio emocional**: consuela a un canal triste y se suma cuando todos se ríen.
- **Aprende con premio y castigo**: las risas, las gracias y las respuestas cálidas premian lo que acaba de hacer, y un *cállate*, un insulto o un kick lo castigan. Cada canal acaba con su propia versión del bot.
- **Toque humano**: tarda en escribir, cambia de estilo según su ánimo, comete alguna errata y la corrige al momento, hace acciones `/me` y responde en varias líneas.

### 🔍 Explicable
- `soul why #canal` enseña sus últimas decisiones, también las veces que eligió callarse, con la puntuación de cada opción y la tirada de dados.
- `soul test #canal <texto>` simula una frase: qué idioma detecta, qué intención, qué sentimiento y qué se plantearía decir.

### 🧩 Fácil de personalizar
- **Todo el texto está en paquetes de frases** (`packs/*.pack`) con una pequeña gramática: alternativas, pesos, condiciones de ánimo, energía, hora del día y relación, y plurales.
- Añade tus frases en `soul-data/soul-packs/` (no se pierden al actualizar), o un idioma entero, sin tocar el código.
- Un **validador** compara cada paquete con el maestro en inglés.

## 📦 Instalación

**Requisitos:** Eggdrop **1.8.4 o posterior** (hecho para 1.9 y 1.10) con Tcl **8.6**. Nada más.

```sh
cd ~/eggdrop/scripts
git clone https://github.com/sauk1337/eggdrop-soul.git soul
cp soul/soul.conf.example soul/soul.conf
```

Añade esta línea al final de `eggdrop.conf`:

```tcl
source scripts/soul/soul.tcl
```

Actívalo en un canal editando `scripts/soul/soul.conf`:

```ini
[soul]
# otros nombres a los que responde, además de su nick
names = soul
timezone = Europe/Madrid

[channel #micanal]
active = yes
lang = es
```

Haz `.rehash` en la partyline y en el log aparecerá:

```
soul 1.0.1 loaded: 6 languages, active in 1 channel(s)
```

> 💡 **Consejo:** empieza con `simulate = yes` en la sección del canal. Así escribe en su log lo que *diría* (`.soul simlog`) sin hablar, y puedes conocerlo antes de soltarlo.

Opcional, en `eggdrop.conf` antes de la línea `source`:

```tcl
set soul_config  "scripts/soul/soul.conf"   ;# por defecto: soul.conf junto a soul.tcl
set soul_datadir "soul-data"                ;# por defecto: soul-data en la carpeta del bot
```

## 🗣️ Cómo hablarle

Usa su nick o uno de sus `names`. Contesta en el idioma en que le escribas.

| Le dices | Hace |
|---|---|
| `hola soul` · `buenas soul` | Te saluda (con más cariño si sois amigos) |
| `soul: ¿cómo estás?` | Te cuenta cómo se siente según su ánimo, su energía y la hora |
| `soul ¿quién eres?` | Se presenta |
| `soul cuéntame un chiste` | Te cuenta un chiste |
| `soul ¿qué opinas de la pizza?` · `soul ¿te gustan los lunes?` | Te da su opinión, y la mantiene |
| `soul: recuerda que el té es vida` | Aprende un dato |
| `soul, ¿qué es el té?` | Te lo recuerda y te dice quién se lo enseñó |
| `soul: olvida lo del té` | Lo olvida (si se lo enseñaste tú o eres op) |
| `gracias soul` · `eres un crack soul` | Te da las gracias y le caes un poco mejor |
| `soul eres un inútil` | Se ofende y te lo recuerda un tiempo |
| `soul toma un café` · `soul despierta` | Se anima, y se despierta si estaba dormido |
| `soul cállate` | Se calla 30 minutos |
| `adiós soul` | Se despide |
| `/me abraza a soul` · `/me acaricia a soul` · `/me toca a soul` | Reacciona a la acción |
| `/me le da una colleja a soul` | Te la devuelve |

También en inglés (`hi soul`, `soul tell me a joke`, `soul: remember that...`), francés, italiano, portugués y alemán.

## 🛠️ Comandos

En el canal se escribe `!soul`. Todo funciona también por `/msg <bot> soul <comando>` y en la partyline como `.soul <comando>`. Los comandos de consulta y de administración solo contestan por privado o en la partyline, para no llenar el canal.

| Comando | Quién | Qué hace |
|---|---|---|
| `ignoreme` | cualquiera | Olvida todo lo tuyo y no vuelve a hablarte |
| `talktome` | cualquiera | Deshace `ignoreme` |
| `shh ?#canal? ?tiempo\|off?` | ops | Lo silencia en un canal (30 min por defecto, hasta 7 días); `off` lo quita |
| `status ?#canal?` | ops | Ánimo, energía, sueño, tamaño de la memoria, idiomas oídos y estado del canal |
| `why <#canal>` | ops | Sus últimas decisiones con puntuaciones |
| `test <#canal> <texto>` | ops | Qué entendería de una frase, sin enviar nada |
| `topics <#canal>` | ops | De qué se habla en el canal |
| `rel <nick>` | ops | Su relación con alguien |
| `facts ?palabra?` | ops | Los datos que le han enseñado |
| `learning <#canal>` | ops | Lo que ha aprendido que funciona en ese canal |
| `simlog` | ops | Lo que dijo en modo simulación |
| `unlearn <clave>` | ops | Borra un dato |
| `forget <nick\|máscara>` | masters | Borra todo lo que recuerda de alguien |
| `mood <valence\|arousal\|energy\|social> <valor>` | masters | Ajusta un valor interno |
| `say <#canal> <símbolo>` | masters | Le hace decir una frase de sus paquetes |
| `reload` | masters | Recarga los paquetes de frases |

*ops* = flag `o` de Eggdrop (global, o del canal en el caso de `shh`); *masters* = flag `m`. Todo esto se puede cambiar en `[permissions]`.

**Todos los comandos, con salidas reales de ejemplo:** [docs/COMANDOS.md](docs/COMANDOS.md)

<details>
<summary>Ejemplo: <code>.soul status #cafe</code> y <code>.soul why #cafe</code></summary>

```
Mind: valence +0.52  arousal +0.35  energy 0.66  social need 0.00  awake  (last cause: act.hug)
Memory: 2 people, 1 facts, 0 opted out
#cafe: languages heard: en=6.0 (speaks en), vibe +0.19
#cafe: active=1 mode=social lang=en simulate=0 boredom=0.00 pressure=5.92 quiet=0 silence=15s

11:00:00 mention by laura: reply.greet: reply.greet=0.90 | P=0.90 roll=0.09 -> reply.greet
11:00:15 prefix by marc: reply.teach: reply.teach=0.97 | P=1.00 roll=0.36 -> reply.teach
11:01:30 mention by marc: reply.joke: reply.joke=0.66 | P=0.66 roll=0.36 -> reply.joke
11:01:45 ambient amb.laugh: amb.laugh=0.00 | P=0.00 roll=0.67 -> silence
11:02:00 action by laura: act.hug: act.hug=0.63 | P=0.63 roll=0.54 -> act.hug
```
</details>

## ⚙️ Configuración

`soul.conf` es un fichero INI normal y **nunca se ejecuta**. Si hay un error, se avisa en el log con su número de línea y se mantiene el valor por defecto. Las opciones por canal van en una sección `[channel #nombre]`.

| Opción | Por defecto | |
|---|---|---|
| `active` 🔹 | `no` | Vivir en este canal |
| `mode` 🔹 | `social` | `quiet`: solo responde · `social`: además reacciona y saca conversación · `chatty`: todavía más |
| `lang` 🔹 | `en` | Idioma por defecto |
| `autolang` / `langs` 🔹 | `yes` / todos | Contestar en el idioma de quien habla · idiomas que puede usar |
| `simulate` 🔹 | `no` | Apuntar en el log en lugar de hablar |
| `names` | `soul` | Otros nombres a los que responde |
| `timezone` · `sleep_start` · `sleep_end` | `Europe/Madrid` · `3` · `9` | Su ritmo diario (si inicio y fin coinciden, nunca duerme) |
| `extraversion` · `agreeableness` · `humor` · `verbosity` | `60` · `65` · `60` · `50` | Temperamento, de 0 a 100 |
| `typos` | `yes` | Alguna errata, corregida |
| `learn_facts` 🔹 · `facts_max` | `yes` · `500` | Datos enseñados |
| `idle_after` 🔹 · `shush_time` 🔹 | `20m` · `30m` | Silencio antes de sacar conversación · cuánto dura un *cállate* |
| `ignore_nicks` | `Q L S D` | Nicks a los que nunca contesta (servicios, bots) |
| `private_chat` · `away` | `no` · `no` | Charlar por privado · ponerse AWAY mientras duerme |

🔹 = se puede poner por canal. Lista completa: [soul.conf.example](soul.conf.example) · cómo funciona todo: [docs/GUIA.md](docs/GUIA.md).

## 🌍 Idiomas

| | Idioma | Paquete |
|---|---|---|
| 🇬🇧 | English | `en.pack` (maestro) |
| 🇪🇸 | Español | `es.pack` |
| 🇫🇷 | Français | `fr.pack` |
| 🇮🇹 | Italiano | `it.pack` |
| 🇵🇹 | Português | `pt.pack` |
| 🇩🇪 | Deutsch | `de.pack` |

Cada frase se compara con los seis idiomas y la respuesta va en el de la frase. Si la frase es demasiado corta para saberlo, usa el idioma que suele hablar esa persona, luego el del canal y por último `lang`. Con las frases de muestra acierta 29 de 30 y nunca adivina mal. Cómo añadir un idioma está en la [guía](docs/GUIA.md#añadir-un-idioma).

## 🛡️ Seguridad y privacidad

- **Apagado en todas partes** hasta que lo actives en un canal.
- **Nunca habla con** bots (`+b`), servicios de la red ni con quien haya usado `ignoreme`.
- **Protección contra bucles:** como mucho 4 respuestas por minuto a la misma persona y un límite de frases por canal.
- **Obedece el *cállate*.**
- **No guarda el texto de los mensajes:** los temas son recuentos de palabras que se desvanecen y las relaciones son números.
- **Nunca ejecuta nada:** ni la configuración, ni los paquetes, ni lo que dice la gente. Lo que envía no puede inyectar comandos IRC ni CTCP.
- **Un fallo no tumba tu bot:** los errores se contienen y se registran. Si hay demasiados en cinco minutos, se apaga solo.
- **Los ficheros de datos** se escriben de forma atómica y con checksum. Si uno se daña, se aparta y empieza con la memoria vacía.

## 🧪 Desarrollo

```sh
tclsh tests/all.tcl                # 51 pruebas en un simulador de Eggdrop, sin red
tclsh tools/soulpack.tcl           # valida los paquetes de frases
tclsh tools/souldemo.tcl es 2      # un día simulado (prueba también: en 1, fr 3)
tclsh tools/example.tcl            # regenera soul.conf.example
```

El código fuente es ASCII puro, porque Eggdrop lee los scripts con la codificación del sistema. Los paquetes son datos en UTF-8. Ver [CONTRIBUTING.md](CONTRIBUTING.md). Se agradece mucho que hablantes nativos revisen los paquetes de francés, italiano, portugués y alemán.

**Estado:** versión 1.0.1, probada con un simulador de la API de Eggdrop. Los avisos desde redes reales son bienvenidos en las *issues*.

## 📄 Licencia

[MIT](LICENSE) © 2026 sauk1337
