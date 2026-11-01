<div align="center">

# 🌱 soul

### A personality with a life of its own, for Eggdrop

*It chats, laughs, learns, sleeps, holds grudges and answers everyone in their own language.*

[![Eggdrop](https://img.shields.io/badge/Eggdrop-1.8.4%2B-blue)](https://www.eggheads.org/)
[![Tcl](https://img.shields.io/badge/Tcl-8.6-orange)](https://www.tcl-lang.org/)
[![Languages](https://img.shields.io/badge/languages-en%20%C2%B7%20es%20%C2%B7%20fr%20%C2%B7%20it%20%C2%B7%20pt%20%C2%B7%20de-brightgreen)](#-languages)
[![Tests](https://img.shields.io/badge/tests-51%20passing-success)](#-development)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

**English** · [Español](README.es.md)

</div>

---

`soul` turns an Eggdrop bot into a **regular of the channel**. It answers when spoken to, laughs along, hugs back, learns what it is taught, brings up what people have been talking about, gets bored, lonely and sleepy, wakes up grumpy, holds grudges that fade, and learns **in each channel** which of its jokes and habits people actually enjoy.

One script, no dependencies, safe by design. Inspired by the idea behind [bMotion](https://github.com/jamesoff/bmotion), but written from scratch: no shared code or data.

## 📑 Contents

- [See it live](#-see-it-live)
- [Features](#-features)
- [Installation](#-installation)
- [Talking to it](#-talking-to-it)
- [Commands](#-commands)
- [Configuration](#%EF%B8%8F-configuration)
- [Languages](#-languages)
- [Safety and privacy](#%EF%B8%8F-safety-and-privacy)
- [Development](#-development)

## 👀 See it live

A real transcript from `tclsh tools/souldemo.tcl en 1` (a simulated day, no network needed):

```
10:00 <laura> hi Meepo
10:00 <Meepo> hey laura!
10:00 <marc> Meepo: remember that the coffee machine is broken again
10:00 <Meepo> memorised :)
10:02 <laura> Meepo: what is the coffee machine?
10:02 <Meepo> the coffee machine is broken again
10:02 <marc> Meepo: tell me a joke
10:02 <Meepo> i'm not lazy, i'm in power-saving mode
10:03 <laura> hahaha
10:03  * laura hugs Meepo
10:03  * Meepo melts into the hug
10:33 <Meepo> marc, how's it going?
10:49 <marc> Meepo you are useless
10:49 <Meepo> love you too, marc
10:49  * marc slaps Meepo
10:49 <Meepo> i didn't deserve that ugh...
11:20 <Meepo> nothing but deployment around here today :)
16:29 <laura> Meepo: have a coffee
16:29  * Meepo gulps it down
16:29 <Meepo> now we're talking!
16:46 <Meepo> hello? anyone here?
02:30 <marc> hi Meepo
02:30 <Meepo> zzz...
02:30 <marc> hi Meepo
02:30 <marc> hi Meepo
02:30 <Meepo> what?! who? oh, it's you, marc
08:06 <Meepo> good morning, #cafe ^^
```

The next afternoon, everyone in their own language:

```
09:30 <joao> olá Meepo, tudo bem com você?
09:30 <Meepo> e aí joao, tudo bem?
09:30 <klaus> hallo Meepo, wie geht es dir?
09:30 <Meepo> gut, und dir, klaus?
09:31 <chloe> salut Meepo, ça va ?
09:31 <Meepo> bien, et toi chloe ?
09:31 <laura> Meepo: what do you think about pizza?
09:31 <Meepo> honestly, i can't stand pizza
```

## ✨ Features

### 🧠 An inner life
- **Mood** in two dimensions (how good and how excited it feels). Events push it around, and it slowly returns to its temperament.
- **Energy** that follows the time of day in your time zone. Talking tires it; coffee and sleep restore it.
- **Sleep** at night: it mumbles *zzz* if poked and wakes up annoyed on the third poke. It says good morning when it wakes.
- **Boredom and loneliness**: after a long silence it starts a conversation, mentions a topic or a fact, or asks if anyone is there.

### 💬 It understands people
- **Intents in six languages**: greetings, goodbyes, *how are you*, jokes, thanks, compliments, insults, love, coffee, *shut up*, questions, opinions.
- **`/me` actions**: hugs, slaps, pokes, feeding, petting and kisses each get their own reaction.
- **Sentiment and laughter**: lexicons, emoticons and simple negation, so *not bad* is not bad.
- **Being addressed**: `soul: ...`, a mention at the end of a line, an action, or a private message.

### 📚 It learns and remembers
- **Facts**: `soul: remember that X is Y`, then `soul, what is X?` answers *"Y. or so says marc"*. Each fact keeps its author. Links, adverts and channel invitations are refused.
- **People**: familiarity and affinity for everyone it talks to, keyed by Eggdrop handle or host, never by nick, so a nick change cannot fool it. Friends get warmer greetings; whoever insults it gets the cold shoulder for a while. Both fade with time.
- **Channel topics**: which words a channel keeps coming back to, without storing any sentence. It uses them for small talk.
- **Anniversaries and milestones**: *"we met 1 year ago today"*, and celebrations at 100, 500 and 1000 interactions.

### 🎭 A character of its own
- **Opinions**: stable tastes, so the same bot always likes the same things. They shift with how the channel feels about each subject. Ask *"what do you think about Mondays?"*.
- **Emotional contagion**: it comforts a gloomy channel and joins in when everyone is laughing.
- **Learning by reinforcement**: laughter, thanks and warm replies reward what it just did; *shut up*, insults and kicks punish it. Each channel ends up with its own version of the bot.
- **A human touch**: typing delays, a style that changes with its mood, the occasional typo corrected a moment later, `/me` actions and multi-line answers.

### 🔍 Explainable
- `soul why #chan` shows each recent decision, including the times it chose to stay silent, with every option's score and the dice roll.
- `soul test #chan <text>` is a dry run: the language it detects, the intent, the sentiment and what it would consider saying.

### 🧩 Easy to customise
- **All text is in plain phrase packs** (`packs/*.pack`) with a small grammar: alternatives, weights, conditions on mood, energy, time of day and relationship, and plurals.
- Add your own phrases in `soul-data/soul-packs/` (they survive updates), or a whole new language, without touching code.
- A **validator** checks every pack against the English master.

## 📦 Installation

**Requirements:** Eggdrop **1.8.4 or newer** (built for 1.9 and 1.10) with Tcl **8.6**. Nothing else.

```sh
cd ~/eggdrop/scripts
git clone https://github.com/sauk1337/eggdrop-soul.git soul
cp soul/soul.conf.example soul/soul.conf
```

Add this line to the end of `eggdrop.conf`:

```tcl
source scripts/soul/soul.tcl
```

Switch it on in a channel by editing `scripts/soul/soul.conf`:

```ini
[soul]
# other names it answers to, besides its nick
names = soul
timezone = Europe/Madrid

[channel #mychannel]
active = yes
lang = en
```

`.rehash` on the partyline, and the log says:

```
soul 1.0.1 loaded: 6 languages, active in 1 channel(s)
```

> 💡 **Tip:** start with `simulate = yes` in the channel section. It writes what it *would* say to its log (`.soul simlog`) without speaking, so you can get to know it first.

Optional, in `eggdrop.conf` before the `source` line:

```tcl
set soul_config  "scripts/soul/soul.conf"   ;# default: soul.conf next to soul.tcl
set soul_datadir "soul-data"                ;# default: soul-data in the bot's directory
```

## 🗣️ Talking to it

Use its nick or one of its `names`. It answers in the language you write in.

| You say | It does |
|---|---|
| `hi soul` · `hello soul` | Greets you back (more warmly if you are a friend) |
| `soul: how are you?` | Tells you how it feels, depending on its mood, energy and the hour |
| `soul who are you?` | Introduces itself |
| `soul tell me a joke` | Tells a joke |
| `soul what do you think about pizza?` · `soul do you like Mondays?` | Gives its opinion, and keeps it |
| `soul: remember that tea is life` | Learns a fact |
| `soul, what is tea?` | Recalls it, with who taught it |
| `soul: forget tea` | Forgets it (if you taught it, or you are an op) |
| `thanks soul` · `you're the best soul` | Thanks you, and likes you a little more |
| `soul you're useless` | Takes offence and remembers it for a while |
| `soul have a coffee` · `soul wake up` | Perks up, and wakes up if it was asleep |
| `soul shut up` | Goes quiet for 30 minutes |
| `bye soul` | Says goodbye |
| `/me hugs soul` · `/me pets soul` · `/me pokes soul` | Reacts to the action |
| `/me slaps soul around a bit with a large trout` | Hits back |

Also in Spanish (`hola soul`, `soul cuéntame un chiste`, `soul: recuerda que...`), French, Italian, Portuguese and German.

## 🛠️ Commands

Channel commands start with `!soul`. Everything also works by `/msg <bot> soul <command>` and on the partyline as `.soul <command>`. Inspection and admin commands only answer in private or on the partyline, so they never clutter the channel.

| Command | Who | What it does |
|---|---|---|
| `ignoreme` | anyone | Forgets everything about you and never talks to you again |
| `talktome` | anyone | Undoes `ignoreme` |
| `shh ?#chan? ?time\|off?` | ops | Silences it in a channel (default 30 min, up to 7 days); `off` lifts it |
| `status ?#chan?` | ops | Mood, energy, sleep, memory size, languages heard and channel state |
| `why <#chan>` | ops | Its latest decisions with scores |
| `test <#chan> <text>` | ops | What it would understand from a line, without sending anything |
| `topics <#chan>` | ops | What the channel is talking about |
| `rel <nick>` | ops | Its relationship with someone |
| `facts ?word?` | ops | The facts it has been taught |
| `learning <#chan>` | ops | What it has learned works in that channel |
| `simlog` | ops | What it said in simulation mode |
| `unlearn <key>` | ops | Deletes a fact |
| `forget <nick\|mask>` | masters | Deletes everything it remembers about someone |
| `mood <valence\|arousal\|energy\|social> <value>` | masters | Sets an inner value |
| `say <#chan> <symbol>` | masters | Makes it say a phrase from its packs |
| `reload` | masters | Reloads the phrase packs |

*ops* = Eggdrop flag `o` (global, or for that channel with `shh`); *masters* = flag `m`. All of this can be changed in `[permissions]`.

**Every command, with real example output:** [docs/COMMANDS.md](docs/COMMANDS.md)

<details>
<summary>Example: <code>.soul status #cafe</code> and <code>.soul why #cafe</code></summary>

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

## ⚙️ Configuration

`soul.conf` is a plain INI file and is **never executed**. A mistake is reported in the log with its line number and the default is kept. Per-channel options go in a `[channel #name]` section.

| Option | Default | |
|---|---|---|
| `active` 🔹 | `no` | Live in this channel |
| `mode` 🔹 | `social` | `quiet`: only answers · `social`: also reacts and makes small talk · `chatty`: more of it |
| `lang` 🔹 | `en` | Default language |
| `autolang` / `langs` 🔹 | `yes` / all | Answer in the speaker's language · which languages it may use |
| `simulate` 🔹 | `no` | Log instead of speaking |
| `names` | `soul` | Other names it answers to |
| `timezone` · `sleep_start` · `sleep_end` | `Europe/Madrid` · `3` · `9` | Its daily rhythm (same start and end: never sleeps) |
| `extraversion` · `agreeableness` · `humor` · `verbosity` | `60` · `65` · `60` · `50` | Temperament, 0 to 100 |
| `typos` | `yes` | Occasional typos, corrected |
| `learn_facts` 🔹 · `facts_max` | `yes` · `500` | Taught facts |
| `idle_after` 🔹 · `shush_time` 🔹 | `20m` · `30m` | Silence before small talk · how long *shut up* lasts |
| `ignore_nicks` | `Q L S D` | Nicks it never answers (services, bots) |
| `private_chat` · `away` | `no` · `no` | Chat in private · set AWAY while asleep |

🔹 = can be set per channel. Full list: [soul.conf.example](soul.conf.example) · how it all works: [docs/GUIDE.md](docs/GUIDE.md).

## 🌍 Languages

| | Language | Pack |
|---|---|---|
| 🇬🇧 | English | `en.pack` (master) |
| 🇪🇸 | Español | `es.pack` |
| 🇫🇷 | Français | `fr.pack` |
| 🇮🇹 | Italiano | `it.pack` |
| 🇵🇹 | Português | `pt.pack` |
| 🇩🇪 | Deutsch | `de.pack` |

Each line is checked against all six. It answers in the language of the line. If the line is too short to tell, it uses the language that person usually speaks, then the channel's, then `lang`. On the bundled samples it gets 29 of 30 right and never guesses wrong. Adding a language is described in the [guide](docs/GUIDE.md#adding-a-language).

## 🛡️ Safety and privacy

- **Off everywhere** until you enable it in a channel.
- **Never talks to** bots (`+b`), network services or people who used `ignoreme`.
- **Loop protection:** at most 4 replies a minute to the same person, and a talk budget per channel.
- **Obeys *shut up*.**
- **Stores no message text:** topics are fading word counts and relationships are numbers.
- **Never evaluates anything:** not the configuration, not the packs, not what people say. Its output cannot inject IRC commands or CTCPs.
- **A bug cannot take your bot down:** errors are contained and logged, and after too many in five minutes it switches itself off.
- **Data files** are written atomically with a checksum. A damaged one is set aside and it starts with a fresh memory.

## 🧪 Development

```sh
tclsh tests/all.tcl                # 51 tests in an Eggdrop simulator, no network
tclsh tools/soulpack.tcl           # validate the phrase packs
tclsh tools/souldemo.tcl en 1      # watch a simulated day (try: es 2, fr 3)
tclsh tools/example.tcl            # regenerate soul.conf.example
```

Sources are pure ASCII (Eggdrop reads scripts in the system encoding). Packs are UTF-8 data. See [CONTRIBUTING.md](CONTRIBUTING.md). Reviews of the French, Italian, Portuguese and German packs by native speakers are very welcome.

**Status:** version 1.0.1, tested in a simulator of the Eggdrop API. Reports from live networks are welcome in the issues.

## 📄 License

[MIT](LICENSE) © 2026 sauk1337
