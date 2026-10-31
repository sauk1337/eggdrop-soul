# soul — a personality with a life of its own, for Eggdrop

**English** · [Español](README.es.md)

`soul` turns an Eggdrop bot into a regular of the channel. It chats when spoken to, laughs along, hugs back, learns what it is taught, brings up what people have been talking about, gets bored, lonely and sleepy, wakes up grumpy, holds fading grudges, and learns **in each channel** which of its jokes and habits people actually enjoy.

It answers **each person in the language they speak**: English, Spanish, French, Italian, Portuguese and German, even when several are mixed in the same channel.

Inspired by the idea behind [bMotion](https://github.com/jamesoff/bmotion), but a new design written from scratch: no shared code or data.

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
*(real output of `tclsh tools/souldemo.tcl es 2`)*

## Features

| | |
|---|---|
| 🧠 **Inner life** | Mood (valence and arousal) that drifts back to its temperament; energy that follows a daily rhythm in your time zone; it **sleeps** at night, mumbles if poked and wakes up annoyed; boredom and loneliness push it to start conversations. |
| 🌍 **Multilingual** | Detects the language of every line and answers in it, remembering what each person and each channel usually speak. Short ambiguous lines ("ok", "lol") are not guessed. 29 of 30 sample lines right, none wrong. |
| 💬 **Understands intents** | Greetings, goodbyes, "how are you", jokes, thanks, compliments, insults, coffee, "shut up", questions, opinions, and `/me` actions (hug, slap, poke, feed, pet, kiss), in all six languages. |
| 📚 **Learns facts** | `bot: remember that X is Y` → `bot, what is X?` → "Y. or so says marc". Facts keep their author and refuse links, adverts and channel invitations. |
| ❤️ **Remembers people** | Familiarity and affinity per person, keyed by Eggdrop handle or host (not by nick, so they can't be stolen), fading with time. Friends get warmer greetings; people who insult it get the cold shoulder for a while. |
| 🎭 **Has opinions** | Stable tastes (the same bot always likes the same things) that shift with how the channel feels about them: "what do you think about Mondays?". |
| 🌦️ **Feels the room** | Catches the channel's mood: comforts a gloomy channel, joins in when everyone is laughing. Celebrates anniversaries and milestones with regulars. |
| 📈 **Learns what works** | After it speaks, laughter, thanks and warm replies reward that behaviour; "shut up", insults and kicks punish it. Each channel ends up with its own personality. |
| 🔍 **Explainable** | `soul why #chan` shows every recent decision, including the times it stayed silent, with each candidate's score and the dice roll. `soul test` is a dry run. |
| ✍️ **Human touch** | Typing delays, mood-dependent style, occasional typos with self-correction, `/me` actions, multi-line answers. |
| 🧩 **Editable phrase packs** | All text lives in plain `packs/*.pack` files with a small grammar (choices, weights, conditions on mood, energy, time of day and relationship, plurals). Add your own phrases or a new language without touching code; a validator checks every pack against the English master. |
| 🛡️ **Safe by design** | Off until you enable it per channel; never talks to bots (`+b`), services or people who opted out; loop protection and talk budgets; obeys "shut up"; stores **no message text**; nothing it reads is ever evaluated; output cannot inject IRC commands. |

## Requirements

- Eggdrop **1.8.4 or newer** (developed for 1.9 / 1.10) with Tcl **8.6**.
- No other dependencies.

## Installation

```sh
cd ~/eggdrop/scripts
git clone https://github.com/sauk1337/eggdrop-soul.git soul
cp soul/soul.conf.example soul/soul.conf
```

Add to the end of `eggdrop.conf`:

```tcl
source scripts/soul/soul.tcl
```

Enable it in a channel in `scripts/soul/soul.conf`:

```ini
[soul]
# other names it answers to, besides its nick
names = soul
timezone = Europe/Madrid

[channel #mychannel]
active = yes
# default language when it cannot tell
lang = en
```

Then `.rehash` on the partyline. The log shows:
`soul 1.0.0 loaded: 6 languages, active in 1 channel(s)`.

> Tip: start with `simulate = yes` in the channel section. It will log what it *would* say (`.soul simlog`) without speaking.

Optional, in `eggdrop.conf` before the `source` line:

```tcl
set soul_config  "scripts/soul/soul.conf"   ;# default: soul.conf next to soul.tcl
set soul_datadir "soul-data"                ;# default: soul-data in the bot's directory
```

## Talking to it

```
hi soul                              soul: how are you?
soul tell me a joke                  soul what do you think about pizza?
soul: remember that tea is life      soul, what is tea?
soul: forget tea                     soul shut up
/me hugs soul                        /me slaps soul around a bit with a large trout
```

And the same in Spanish, French, Italian, Portuguese or German.

## Commands

In a channel `!soul <sub>`, by `/msg <bot> soul <sub>`, or on the partyline `.soul <sub>`:

| Command | Who | |
|---|---|---|
| `ignoreme` / `talktome` | anyone | Opt out (it forgets you and never talks to you), and back in |
| `shh ?#chan? ?time\|off?` | `o` (global or channel) | Make it quiet for a while |
| `status ?#chan?` | `o` | Mood, energy, sleep, drives, languages |
| `why <#chan>` | `o` | Its latest decisions with scores |
| `test <#chan> <text>` | `o` | What it would perceive and consider |
| `topics <#chan>` · `rel <nick>` · `facts ?word?` · `learning <#chan>` · `simlog` | `o` | Look inside its memory |
| `unlearn <key>` | `o` | Delete a fact |
| `forget <nick\|mask>` | `m` | Delete what it remembers about someone |
| `mood <var> <value>` · `say <#chan> <symbol>` · `reload` | `m` | Steer it, make it speak, reload packs |

Permissions can be changed in the `[permissions]` section of `soul.conf`.

## Documentation

- [docs/GUIDE.md](docs/GUIDE.md): how it works, every option, phrase packs, adding a language.
- [soul.conf.example](soul.conf.example): every option with its default.

## Development

```sh
tclsh tests/all.tcl                # 50 tests in an Eggdrop simulator, no network
tclsh tools/soulpack.tcl           # validate the phrase packs
tclsh tools/souldemo.tcl en 1      # watch a simulated day (try: es 2, fr 3)
tclsh tools/example.tcl            # regenerate soul.conf.example
```

Sources are kept pure ASCII (non-ASCII characters as `\uXXXX`): Eggdrop reads scripts in the system encoding. Packs are UTF-8 data. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Status

Version 1.0.0. Tested in a simulator of the Eggdrop API, not yet on a live network: feedback and bug reports are welcome. Translations other than English and Spanish deserve a review by native speakers.

## License

[MIT](LICENSE) © 2026 sauk1337
