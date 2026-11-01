# soul: referencia de comandos

[English](COMMANDS.md) · **Español**

Todos los comandos son subcomandos de `soul` y se pueden usar de tres formas:

| Dónde | Cómo |
|---|---|
| En un canal | `!soul <comando>` (el `!` es la opción `prefix`) |
| Por privado | `/msg <bot> soul <comando>` |
| En la partyline | `.soul <comando>` |

`ignoreme`, `talktome` y `shh` también funcionan en el canal. El resto solo contesta por privado o en la partyline, para que consultar el bot nunca llene el canal. `.soul` o `soul help` a secas lista los comandos que puedes usar.

Quién puede usar qué se decide en la sección `[permissions]` de `soul.conf`. Por defecto:

| Capacidad | Flags por defecto | Comandos |
|---|---|---|
| — | cualquiera | `ignoreme`, `talktome` |
| `soul.hush` | `o\|o` (op global o del canal) | `shh` |
| `soul.view` | `o` | `status`, `why`, `test`, `topics`, `rel`, `facts`, `learning`, `simlog` |
| `soul.facts` | `o` | `unlearn`, y olvidar en el canal un dato que enseñó otra persona |
| `soul.admin` | `m` | `forget`, `mood`, `say`, `reload` |
| `soul.teach` | cualquiera | enseñarle datos en el canal ("recuerda que…") |

Los ejemplos son salidas reales del simulador. El bot contesta en inglés a los comandos de administración; lo que dice en el canal va en el idioma de cada persona.

---

## Para todos

### `ignoreme`
Pedirle que te ignore: borra lo que recuerda de ti y no vuelve a hablarte ni a hablar de ti. Contesta con un aviso privado.

```
!soul ignoreme
-Meepo- Done: soul has forgotten you and will not talk to you or about you. Undo with: soul talktome
```

### `talktome`
Deshace `ignoreme`.

```
/msg Meepo soul talktome
-Meepo- soul may talk to you again.
```

---

## Hacerle callar

### `shh ?#canal? ?duración|off?`
Lo silencia en un canal. Sin duración usa `shush_time` (30 minutos), y el máximo son 7 días. `off` lo quita. Decirle "soul cállate" en el canal hace lo mismo, durante `shush_time`, y lo puede hacer cualquiera.

```
.soul shh #cafe 10m
soul will stay quiet in #cafe for 10m.
.soul shh #cafe off
soul may speak again in #cafe.
```

---

## Ver por dentro

### `status ?#canal?`
Su estado de ánimo, sus paquetes de frases y cuánto recuerda. Si le das un canal, también qué oye ahí y cómo se está comportando.

```
.soul status #cafe
Mind: valence +0.52  arousal +0.35  energy 0.66  social need 0.00  awake  (last cause: act.hug)
Grammar: de: 53 symbols, 255 phrases, 32 intent patterns; en: 53 symbols, 255 phrases, 31 intent patterns; ...
Memory: 2 people, 1 facts, 0 opted out
#cafe: languages heard: en=6.0 (speaks en), vibe +0.19
#cafe: active=1 mode=social lang=en simulate=0 boredom=0.00 pressure=5.92 quiet=0 silence=15s
```

- **valence**: lo bien que se siente (de −1 a +1). **arousal**: lo activo que está (de −1 a +1). **energy**: de 0 a 1; si está baja de noche, se duerme. **social need**: crece cuando nadie le habla.
- **vibe**: el ánimo del canal. **boredom**: aburrimiento, que crece con el silencio. **pressure**: cuántas frases ha dicho él hace poco (si es alta, se contiene). **silence**: segundos desde que habló alguien.

### `why <#canal>`
Sus últimas decisiones en un canal, también las veces que eligió callarse. Cada línea muestra qué la provocó, cada opción que se planteó con su puntuación, la probabilidad de hablar, la tirada de dados y el resultado.

```
.soul why #cafe
11:00:00 mention by laura: reply.greet: reply.greet=0.90 | P=0.90 roll=0.09 -> reply.greet
11:00:15 prefix by marc: reply.teach: reply.teach=0.97 | P=1.00 roll=0.36 -> reply.teach
11:00:30 prefix by laura: reply.ask: reply.ask=0.95 | P=1.00 roll=0.00 -> reply.ask
11:01:30 mention by marc: reply.joke: reply.joke=0.66 | P=0.66 roll=0.36 -> reply.joke
11:01:45 ambient amb.laugh: amb.laugh=0.00 | P=0.00 roll=0.67 -> silence
11:02:00 action by laura: act.hug: act.hug=0.63 | P=0.63 roll=0.54 -> act.hug
```

### `test <#canal> <texto>`
Simula cómo leería una frase, sin enviar nada. Muestra el idioma detectado, si la frase va dirigida a él, la intención y lo que ha capturado, el sentimiento y los comportamientos que competirían.

```
.soul test #cafe Meepo: what do you think about mondays?
language=en (detected en, confidence 0.67) -> would answer in en
addressed=prefix intent=opinion groups=[mondays] sentiment=+0.00 laugh=0 question=1
candidates: reply.opinion=0.56
```

### `topics <#canal>`
Las palabras a las que vuelve el canal. Son recuentos que se desvanecen; no se guarda ninguna frase.

```
.soul topics #cafe
Topics in #cafe: deploy=3.0
```

### `rel <nick>`
Su relación con alguien: confianza (de 0 a 1), aprecio (de −1 a +1), número de interacciones y tipo (friend, known, stranger, foe: amigo, conocido, desconocido, enemigo).

```
.soul rel laura
laura (*!*@l.example): familiarity 0.12, affinity +0.16, 9 interactions, class known
```

### `facts ?palabra?`
Los datos que le han enseñado y quién los enseñó (como mucho 20; puedes filtrar con una palabra).

```
.soul facts
build = broken again (marc)
```

### `learning <#canal>`
Lo que ha aprendido que funciona en ese canal: los comportamientos cuyo peso se ha movido de 1.00. Por encima de 1 los hace más; por debajo, menos.

```
.soul learning #cafe
Learned weights in #cafe (1.00 = neutral):
reply.joke       1.15
reply.greet      1.15
```

### `simlog`
Las 15 últimas frases que habría dicho en los canales con `simulate = yes`.

---

## Cambiarlo

### `unlearn <clave>`
Borra un dato. Quien lo enseñó también puede decir "soul: olvida X" en el canal.

```
.soul unlearn build
Fact 'build' deleted.
```

### `forget <nick|máscara>`
Borra todo lo que recuerda de alguien: la relación, el idioma y el aniversario. Acepta un nick que esté en un canal, un handle de Eggdrop o una máscara `nick!user@host`.

```
.soul forget marc
Forgot 1 record(s) for marc.
```

### `mood <valence|arousal|energy|social> <valor>`
Ajusta a mano un valor interno: valence y arousal de −1 a 1, energy y social de 0 a 1. Una energía por encima de 0,3 lo despierta.

```
.soul mood valence 0.9
valence +0.90  arousal +0.00  energy 0.70  social need 0.30  awake  (last cause: just started)
```

### `say <#canal> <símbolo>`
Le hace decir una frase de sus paquetes en el idioma del canal. Si el símbolo no existe, te da la lista (`joke`, `greet.reply`, `idle.chatter`, `lonely`…).

```
.soul say #cafe joke
Queued <joke> for #cafe.
```

### `reload`
Recarga los paquetes de frases (`packs/` y `soul-data/soul-packs/`) después de editarlos, y avisa de los problemas que encuentre.

```
.soul reload
Packs reloaded: de: 53 symbols, 255 phrases, ...; Problems: 0
```

---

## Hablarle, no mandarle

Casi siempre a soul no se le dan órdenes: se le habla. Esto funciona en todos sus idiomas:

| Dile | Efecto |
|---|---|
| `soul: recuerda que X es Y` | Aprende un dato (`soul.teach`; `learn_facts` tiene que estar activo en el canal) |
| `soul, ¿qué es X?` | Te lo recuerda |
| `soul: olvida X` | Lo olvida, si se lo enseñaste tú o tienes `soul.facts` |
| `soul cállate` | Se calla durante `shush_time` |
| `soul despierta` · `soul toma un café` | Lo despierta o le da energía |

La lista completa está en el [README](../README.es.md#%EF%B8%8F-cómo-hablarle).
