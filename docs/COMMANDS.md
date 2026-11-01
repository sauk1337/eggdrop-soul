# soul — command reference

**English** · [Español](COMANDOS.md)

Every command is a subcommand of `soul`, and can be used three ways:

| Where | How |
|---|---|
| In a channel | `!soul <command>` (the `!` is the `prefix` option) |
| Private message | `/msg <bot> soul <command>` |
| Partyline | `.soul <command>` |

`ignoreme`, `talktome` and `shh` also work in a channel. The rest only answer in private or on the partyline, so inspecting the bot never clutters the channel. `.soul` or `soul help` alone lists the commands you are allowed to use.

Who may use what is set in `[permissions]` in `soul.conf`. The defaults:

| Capability | Default flags | Commands |
|---|---|---|
| — | anyone | `ignoreme`, `talktome` |
| `soul.hush` | `o\|o` (global op or op of the channel) | `shh` |
| `soul.view` | `o` | `status`, `why`, `test`, `topics`, `rel`, `facts`, `learning`, `simlog` |
| `soul.facts` | `o` | `unlearn`, and forgetting anybody's fact in the channel |
| `soul.admin` | `m` | `forget`, `mood`, `say`, `reload` |
| `soul.teach` | anyone | teaching facts in the channel ("remember that…") |

The examples below are real output from the simulator.

---

## For everyone

### `ignoreme`
Opt out. soul deletes what it remembers about you and never talks to you, or about you, again. It answers by private notice.

```
!soul ignoreme
-Meepo- Done: soul has forgotten you and will not talk to you or about you. Undo with: soul talktome
```

### `talktome`
Undo `ignoreme`.

```
/msg Meepo soul talktome
-Meepo- soul may talk to you again.
```

---

## Keeping it quiet

### `shh ?#channel? ?duration|off?`
Silence soul in a channel. Without a duration it uses `shush_time` (30 minutes). The maximum is 7 days. `off` lifts it. Saying "soul shut up" in the channel does the same for anyone, for `shush_time`.

```
.soul shh #cafe 10m
soul will stay quiet in #cafe for 10m.
.soul shh #cafe off
soul may speak again in #cafe.
```

---

## Looking inside

### `status ?#channel?`
Its state of mind, its phrase packs, how much it remembers and, for a channel, what it hears there and how it is behaving.

```
.soul status #cafe
Mind: valence +0.52  arousal +0.35  energy 0.66  social need 0.00  awake  (last cause: act.hug)
Grammar: de: 53 symbols, 255 phrases, 32 intent patterns; en: 53 symbols, 255 phrases, 31 intent patterns; ...
Memory: 2 people, 1 facts, 0 opted out
#cafe: languages heard: en=6.0 (speaks en), vibe +0.19
#cafe: active=1 mode=social lang=en simulate=0 boredom=0.00 pressure=5.92 quiet=0 silence=15s
```

- **valence**: how good it feels (−1 to +1). **arousal**: how excited (−1 to +1). **energy**: 0 to 1; it sleeps when low at night. **social need**: grows when nobody talks to it.
- **vibe**: the channel's mood. **boredom** builds up in silence. **pressure** counts its own recent lines (it holds back when high). **silence**: seconds since anyone spoke.

### `why <#channel>`
Its last decisions in a channel, including the times it chose to stay silent. Each line shows what triggered it, every option it considered with its score, the probability of speaking, the dice roll and the result.

```
.soul why #cafe
11:00:00 mention by laura: reply.greet: reply.greet=0.90 | P=0.90 roll=0.09 -> reply.greet
11:00:15 prefix by marc: reply.teach: reply.teach=0.97 | P=1.00 roll=0.36 -> reply.teach
11:00:30 prefix by laura: reply.ask: reply.ask=0.95 | P=1.00 roll=0.00 -> reply.ask
11:01:30 mention by marc: reply.joke: reply.joke=0.66 | P=0.66 roll=0.36 -> reply.joke
11:01:45 ambient amb.laugh: amb.laugh=0.00 | P=0.00 roll=0.67 -> silence
11:02:00 action by laura: act.hug: act.hug=0.63 | P=0.63 roll=0.54 -> act.hug
```

### `test <#channel> <text>`
A dry run: how it would read a line, without sending anything. It shows the language detected, whether the line is addressed to it, the intent and what it captured, the sentiment, and the behaviours that would compete.

```
.soul test #cafe Meepo: what do you think about mondays?
language=en (detected en, confidence 0.67) -> would answer in en
addressed=prefix intent=opinion groups=[mondays] sentiment=+0.00 laugh=0 question=1
candidates: reply.opinion=0.56
```

### `topics <#channel>`
The words the channel keeps coming back to. They are fading counts; no sentence is stored.

```
.soul topics #cafe
Topics in #cafe: deploy=3.0
```

### `rel <nick>`
Its relationship with someone: familiarity (0 to 1), affinity (−1 to +1), number of interactions and the class (friend, known, stranger, foe).

```
.soul rel laura
laura (*!*@l.example): familiarity 0.12, affinity +0.16, 9 interactions, class known
```

### `facts ?word?`
The facts it has been taught, with who taught them (at most 20; filter with a word).

```
.soul facts
build = broken again (marc)
```

### `learning <#channel>`
What it has learned works in that channel: behaviours whose weight moved away from 1.00. Above 1 it does them more; below 1, less.

```
.soul learning #cafe
Learned weights in #cafe (1.00 = neutral):
reply.joke       1.15
reply.greet      1.15
```

### `simlog`
The last 15 lines it would have said in channels with `simulate = yes`.

---

## Changing it

### `unlearn <key>`
Delete a fact. The person who taught it can also say "soul: forget X" in the channel.

```
.soul unlearn build
Fact 'build' deleted.
```

### `forget <nick|mask>`
Delete everything it remembers about someone: relationship, language, anniversary. Accepts a nick on a channel, an Eggdrop handle or a `nick!user@host` mask.

```
.soul forget marc
Forgot 1 record(s) for marc.
```

### `mood <valence|arousal|energy|social> <value>`
Set an inner value by hand: valence and arousal from −1 to 1; energy and social from 0 to 1. Energy above 0.3 wakes it up.

```
.soul mood valence 0.9
valence +0.90  arousal +0.00  energy 0.70  social need 0.30  awake  (last cause: just started)
```

### `say <#channel> <symbol>`
Make it perform a phrase from its packs in the channel's language. Without a valid symbol it lists them (`joke`, `greet.reply`, `idle.chatter`, `lonely`…).

```
.soul say #cafe joke
Queued <joke> for #cafe.
```

### `reload`
Reload the phrase packs (`packs/` and `soul-data/soul-packs/`) after editing them, and report any problems.

```
.soul reload
Packs reloaded: de: 53 symbols, 255 phrases, ...; Problems: 0
```

---

## Talking, not commands

Most of the time soul is not commanded but talked to. These work in every language it speaks:

| Say | Effect |
|---|---|
| `soul: remember that X is Y` | Learns a fact (`soul.teach`; `learn_facts` must be on in the channel) |
| `soul, what is X?` | Recalls it |
| `soul: forget X` | Forgets it, if you taught it or have `soul.facts` |
| `soul shut up` | Quiet for `shush_time` |
| `soul wake up` · `soul have a coffee` | Wakes it up or gives it energy |

See the [README](../README.md#-talking-to-it) for the full list.
