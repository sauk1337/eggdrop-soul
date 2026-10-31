# soul: guía

[English](GUIDE.md) · **Español**

## Cómo funciona

```
evento IRC ──> percepción ──> memoria (relación, temas) ──> mente (ánimo, impulsos)
                  │                                              │
                  └──> comportamiento: candidatos ──> utilidad ──> tirada ──┴──> expresión ──> IRC
                                         ▲                                          │
                                         └────── refuerzo (reacciones) ◄────────────┘
latido (1/min) ──> energía circadiana, aburrimiento, soledad ──> comportamientos espontáneos
```

| Fichero | Función |
|---|---|
| `soul.tcl` | Punto de entrada: carga los ficheros de abajo, lee `soul.conf` y arranca y se detiene limpiamente en cada `.rehash`. |
| `lib/rt.tcl` | El pequeño runtime: configuración validada, ficheros de datos atómicos con checksum, límites de frecuencia, permisos, un único temporizador de 1 segundo, binds que aíslan los errores con un circuit breaker, y el comando `soul`. |
| `lib/rng.tcl` | Generador xorshift32 propio y con semilla: reproducible en las pruebas y sin tocar el `rand()` compartido de Tcl. |
| `lib/mind.tcl` | **Ánimo**: un punto en el espacio afectivo (valencia y activación, de −1 a 1) que vuelve poco a poco a una base marcada por los rasgos. **Energía**: sigue una curva circadiana en la zona horaria configurada, baja al hablar y se recupera durmiendo o con café. **Sueño**: se duerme en su franja de sueño; si le tocan murmura, y al tercer toque se despierta molesto. **Impulsos**: necesidad social (global) y aburrimiento (por canal). **Aprendizaje**: un peso de 0,2 a 3,0 por canal para cada comportamiento. |
| `lib/memory.tcl` | **Relaciones**: confianza y aprecio por persona, según su handle de Eggdrop o su host (nunca por nick), que se desvanecen con el tiempo. **Temas**: recuentos agregados de palabras por canal con una vida media de 6 h, nunca frases. **Datos**: solo los que se le enseñan explícitamente, con su autor. **Exclusiones** de quien ha pedido que le ignore. |
| `lib/perceive.tcl` | Si se dirigen a él (prefijo `soul: …`, mención, acción, privado), el **idioma** de la frase, la intención, el sentimiento (léxicos, emoticonos, negación simple), las risas y las preguntas. |
| `lib/behave.tcl` | Los 38 comportamientos, su puntuación de utilidad, la elección ponderada y el registro de decisiones. |
| `lib/express.tcl` | Retardo de escritura, estilo según el ánimo, erratas con autocorrección, acciones `/me`, mensajes en varias líneas y envío seguro. |
| `lib/grammar.tcl` | Paquetes de frases y el generador recursivo. |
| `lib/engine.tcl` | Eventos, decisiones y comandos que lo unen todo. |

### Idioma

Cada paquete lista en `[detect]` palabras cortas y muy frecuentes de su idioma (the, and…; que, pero…; und, nicht…) y en `[detect.chars]` caracteres típicos (ñ ¿ ¡, ã õ, ß ä ö ü…). Cada frase se puntúa contra todos los idiomas instalados. Las frases cortas o ambiguas ("ok", "lol") se quedan sin decidir en lugar de adivinarlas. Las intenciones se prueban primero en el idioma detectado, así que una coincidencia cuenta como prueba extra.

El idioma de la respuesta se elige en este orden:

1. el de la frase, si está claro o ha coincidido una intención;
2. el que esa persona suele hablar (una memoria por persona que se desvanece);
3. el que se habla últimamente en el canal (recuentos por canal que se desvanecen);
4. `lang`.

Los comentarios espontáneos usan el idioma del canal. `langs` limita los idiomas que puede usar y `autolang = no` lo fija en `lang`. Con las frases de muestra (`tests/fixtures/soul-langs.txt`) la detección acierta 29 de 30 y no se equivoca en ninguna.

### Ambiente del canal, aniversarios y opiniones

- **Contagio emocional**: el ánimo del canal es una media, que se desvanece con el tiempo, de lo que expresa la gente. El ánimo del bot se acerca a él, y más cuanto más amable es. A un canal triste lo consuela (como mucho cada 2 horas) y a uno alegre y lleno de risas se suma (como mucho cada hora).
- **Aniversarios e hitos**: recuerda cuándo conoció a cada persona y cuándo llegó a cada canal. Celebra el aniversario una vez al año y marca los hitos de 100, 500, 1000… interacciones.
- **Opiniones**: gustos estables, derivados del tema y de su semilla, de modo que el mismo bot siempre prefiere lo mismo. Cambian según lo que muestra el canal al hablar de cada tema. Pregúntale "¿qué opinas de X?" o "¿te gusta X?", o deja que la dé él sobre un tema del momento. Solo se guardan puntuaciones por palabra.

### Cómo decide qué hacer

Cada comportamiento candidato recibe una utilidad:

```
U = base × peso_aprendido(canal, comportamiento) × modificadores
```

Los modificadores son sus **rasgos** (extraversión, amabilidad, humor), la **energía**, el **modo** del canal (`quiet`, `social`, `chatty`), la **relación** (amigo, conocido, desconocido, enemigo), lo **animado** que está el canal y la **presión de habla**: un recuento de sus propias frases recientes, que se desvanece, para que nunca acapare la conversación. Las respuestas directas apenas se penalizan; los comentarios espontáneos, mucho.

Habla con probabilidad `min(0.97, U máxima)` y elige entre los candidatos en proporción a U². Las respuestas funcionales (datos, "cállate", que le despierten) siempre se dan.

Los comportamientos espontáneos (charla, temas, datos, soledad) se multiplican por el impulso que hay detrás. Solo ocurren tras `idle_after` de silencio, nunca en un canal sin actividad humana en las últimas 6 horas y nunca más de dos veces seguidas sin que nadie conteste.

### Aprendizaje

Cada vez que habla se abre una ventana de 90 segundos para ver cómo reacciona el canal:

- **Premio**: risas, gracias, piropos o respuestas cálidas sin otro propósito.
- **Castigo**: "cállate", insultos o un kick.
- **Pequeño coste**: el silencio después de un comentario *espontáneo*.

Los mensajes funcionales ("recuerda que la build está rota") nunca cuentan como valoración, aunque tengan palabras negativas. `soul learning #canal` muestra el resultado.

### Explicabilidad

`soul why #canal` lista las últimas decisiones, también las de quedarse callado, con la puntuación de cada candidato, la probabilidad y la tirada:

```
10:02:00 prefix by laura: reply.ask: reply.ask=0.95 | P=0.95 roll=0.46 -> reply.ask
10:51:00 idle 1272s: spont.lonely=0.32, spont.idle=0.10 | P=0.32 roll=0.83 -> silence
```

## Configuración

`soul.conf` es un fichero INI normal. **Nunca se ejecuta**: una opción desconocida o un valor incorrecto se avisa en el log con su número de línea y se mantiene el valor por defecto.

```ini
[soul]
names = soul
timezone = Europe/Madrid
humor = 70

[channel #micanal]
active = yes
lang = es
mode = chatty

[permissions]
soul.admin = n

[ratelimit]
soul.talk = 6/5m
```

Las opciones marcadas *por canal* también pueden ir en una sección `[channel #nombre]`, donde sustituyen al valor global. Todas las opciones, con su valor por defecto, están en [`soul.conf.example`](../soul.conf.example).

| Opción | Por defecto | |
|---|---|---|
| `enabled` | yes | Funcionar o no |
| `active` *(por canal)* | no | Vivir en este canal |
| `mode` *(por canal)* | social | `quiet` solo responde; `social` además reacciona y saca conversación; `chatty` lo hace todavía más |
| `lang` / `autolang` / `langs` *(por canal)* | en / yes / todos | Idioma por defecto; responder en el idioma de quien habla; idiomas permitidos |
| `simulate` *(por canal)* | no | Apuntar en el log lo que diría en lugar de hablar |
| `names` | soul | Otros nombres a los que responde, además de su nick |
| `timezone`, `sleep_start`, `sleep_end` | Europe/Madrid, 3, 9 | Ritmo diario (si inicio y fin coinciden, nunca duerme) |
| `extraversion`, `agreeableness`, `humor`, `verbosity` | 60, 65, 60, 50 | Temperamento, de 0 a 100 |
| `typos` | yes | Alguna errata de vez en cuando, con autocorrección |
| `topics`, `learn_facts` *(por canal)*, `facts_max` | yes, yes, 500 | Charla sobre los temas del canal; datos enseñados |
| `idle_after`, `shush_time` *(por canal)* | 20m, 30m | Silencio antes de sacar conversación; cuánto dura un "cállate" |
| `ignore_nicks` | Q L S D | Nicks a los que nunca contesta |
| `private_chat`, `away` | no, no | Charlar por privado; ponerse AWAY mientras duerme |
| `prefix`, `max_pub_lines`, `log_level`, `seed` | !, 4, info, 0 | Prefijo del comando, máximo de líneas, detalle del log, semilla aleatoria |

Límites de frecuencia: `soul.talk` (8 frases cada 5 min por canal), `soul.user` (4 respuestas por minuto a una misma persona) y `soul.cmd` (6 comandos cada 30 s por persona).

## Paquetes de frases

Los paquetes están en `packs/*.pack`. Los tuyos van en `<soul-data>/soul-packs/*.pack`: amplían o añaden frases y no se pierden al actualizar. El formato está documentado al principio de `lib/grammar.tcl`:

```
@lang es
[greet.reply]
- hola {nick} <smile>
- ¡{nick}! ¡cuánto tiempo! ~rel=friend ~mood=pos
- (hola|buenas|ey) {nick}, (¿qué tal?|¿qué cuentas?)
- *bosteza* buenos días... ~time=morning ~energy=low
- abraza a {nick} ~action
- nos vemos || cuídate ~w=0.5
- {years} {years|año|años} juntos, {nick}!
```

- **Variables**: `{nick} {chan} {botnick} {randnick} {topic} {time} {fact_key} {fact} {fact_by} {kicker} {subject} {years} {count}`. Se salta la alternativa cuya variable está vacía. Plurales: `{var|singular|plural}` elige la palabra según el valor de la variable (`{years} {years|año|años}`).
- **Etiquetas**: `~w=` (peso), `~mood=`, `~energy=`, `~arousal=`, `~rel=`, `~time=`, `~action`.
- **Intenciones**: expresiones regulares por idioma en `[intent.NOMBRE]`. Las funcionales capturan grupos: `teach` = 2, `ask` = 1, `forget` = 1, `opinion` = 1.
- **Detección**: `[detect]` (palabras funcionales en minúscula y sin tildes) y, si se quiere, `[detect.chars]`.
- **El inglés es el maestro.** `tclsh tools/soulpack.tcl` comprueba que cada idioma tenga los mismos símbolos e intenciones, los grupos de captura correctos y solo variables conocidas.

`.soul reload` carga los paquetes modificados sin reiniciar.

### Añadir un idioma

1. Copia `packs/en.pack` como `packs/xx.pack` y pon `@lang xx`.
2. Traduce las frases y escribe expresiones de intención nativas, léxicos, palabras vacías y palabras de `[detect]` (en minúscula y sin tildes).
3. Añade `xx` a los valores de `lang` y `langs` en `lib/engine.tcl`.
4. Añade frases de muestra a `tests/fixtures/soul-langs.txt`.
5. Ejecuta `tclsh tools/soulpack.tcl` y `tclsh tests/all.tcl`.

## Seguridad y privacidad

- **Apagado por defecto** en todos los canales. `simulate` apunta en el log en lugar de hablar.
- **Ignora** a los usuarios de Eggdrop con el flag `b` (bots), a los nicks de `ignore_nicks` (por defecto Q, L, S y D de QuakeNet) y a quien ha pedido que le ignore.
- **Protección contra bucles**: como mucho 4 respuestas por minuto a una misma persona, y un límite de frases por canal.
- **Obedece "cállate"** durante `shush_time`.
- **No guarda el texto de los mensajes.** Los temas son recuentos de palabras que se desvanecen y las relaciones son números. Los datos solo existen si alguien los enseña, y se rechazan los enlaces, la publicidad y las invitaciones a canales.
- **Lo que envía** se parte en líneas seguras (un CR/LF nunca puede empezar otro comando IRC) y se elimina `\001`, así que nadie puede hacerle mandar un CTCP.
- **Nada se ejecuta**: ni la configuración, ni los paquetes, ni lo que dice la gente.
- **El chat privado** está desactivado por defecto. Si se activa, nunca mira las líneas destinadas a los comandos `/msg` de Eggdrop (`pass`, `ident`…).
- **Un fallo no tumba el bot**: los errores de sus funciones se capturan y quedan en el log. Si hay demasiados en cinco minutos, soul se apaga solo hasta el siguiente `.rehash`.
- Los ficheros de datos (`soul-data/*.db`) se escriben de forma atómica y con checksum. Si uno se daña, se aparta y soul empieza con la memoria vacía en lugar de fallar.

## Límites

- No es un modelo de lenguaje: entiende lo que cubren sus patrones de intención y responde con las frases de sus paquetes.
- El francés, el italiano, el portugués y el alemán se escribieron con cuidado, pero convendría que los revisara un hablante nativo; los juegos de palabras no siempre se traducen.
- Probado con un simulador de la API de Eggdrop (`tests/`), todavía no en una red real.
