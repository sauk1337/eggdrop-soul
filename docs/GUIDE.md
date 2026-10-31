# soul — guide

**English** · [Español](GUIA.md)

## How it works

```
IRC event ──> perceive ──> memory (relationship, topics) ──> mind (mood, drives)
                 │                                              │
                 └──> behave: candidates ──> utility ──> roll ──┴──> express ──> IRC
                                     ▲                                   │
                                     └──── reinforcement (reactions) ◄───┘
heartbeat (1/min) ──> circadian energy, boredom, loneliness ──> spontaneous behaviours
```

| File | Role |
|---|---|
| `soul.tcl` | Entry point: loads the files below, reads `soul.conf`, starts and stops cleanly on `.rehash`. |
| `lib/rt.tcl` | The small runtime: validated configuration, atomic checksummed data files, rate limits, permissions, a single 1-second timer, error-isolating binds with a circuit breaker, and the `soul` command. |
| `lib/rng.tcl` | Private, seedable xorshift32 generator: reproducible in tests, never touches Tcl's shared `rand()`. |
| `lib/mind.tcl` | **Mood** as a point in affect space (valence and arousal, −1..1), relaxing towards a baseline set by the traits. **Energy** follows a circadian curve in the configured time zone, is drained by talking and restored by sleep or coffee. **Sleep**: it falls asleep during the sleep window, mumbles if poked and wakes up, annoyed, after three pokes. **Drives**: social need (global) and boredom (per channel). **Learning**: per-channel weights 0.2–3.0 for every behaviour. |
| `lib/memory.tcl` | **Relationships**: familiarity and affinity per person, keyed by Eggdrop handle or host (never by nick), fading over time. **Topics**: aggregated word counts per channel with a 6 h half-life, never sentences. **Facts**: only taught explicitly, with attribution. **Opt-outs**. |
| `lib/perceive.tcl` | Whether it is addressed (prefix `soul: …`, mention, action, private), the **language** of the line, the intent, the sentiment (lexicons, emoticons, simple negation), laughter and questions. |
| `lib/behave.tcl` | The 38 behaviours, utility scoring, weighted choice and the decision log. |
| `lib/express.tcl` | Typing delay, mood-dependent style, typos with self-correction, `/me` actions, multi-line messages, safe delivery. |
| `lib/grammar.tcl` | Phrase packs and the recursive generator. |
| `lib/engine.tcl` | Events, decisions and commands that tie it all together. |

### Language

Every pack lists short, very frequent words of its language in `[detect]` (the, and…; que, pero…; und, nicht…) and typical characters in `[detect.chars]` (ñ ¿ ¡, ã õ, ß ä ö ü…). Each line is scored against every installed language. Short or ambiguous lines ("ok", "lol") are left undecided rather than guessed. Intent patterns are tried in the detected language first, so a match is extra evidence.

The language of an answer is chosen in this order:

1. the language of the line, if it is clear or an intent matched;
2. the language that person usually speaks (a fading per-person memory);
3. the language the channel speaks lately (fading per-channel counts);
4. `lang`.

Unprompted remarks use the channel's language. `langs` restricts which languages it may use; `autolang = no` pins it to `lang`. On the bundled samples (`tests/fixtures/soul-langs.txt`) detection gets 29 of 30 lines right, with no wrong guesses.

### Channel mood, anniversaries, opinions

- **Emotional contagion**: the channel's mood is a fading average of what people express. The bot's own mood drifts towards it, more so the kinder it is. A gloomy channel gets comforted (at most every 2 hours); a happy, laughing one gets cheered along (at most every hour).
- **Anniversaries and milestones**: it remembers when it met each person and when it first came to each channel, celebrates the yearly anniversary once, and marks 100, 500, 1000… interactions.
- **Opinions**: stable tastes derived from the subject and its seed, so the same bot always likes the same things; they shift with the sentiment the channel shows about them. Ask "what do you think about X?" / "do you like X?", or let it volunteer one about a current topic. Only per-word scores are stored.

### Choosing what to do

Each candidate behaviour gets a utility:

```
U = base × learned_weight(channel, behaviour) × modifiers
```

The modifiers are its **traits** (extraversion, agreeableness, humour), **energy**, the channel **mode** (`quiet`, `social`, `chatty`), the **relationship** (friend, known, stranger, foe), how **busy** the channel is, and **talk pressure**: a fading count of its own recent lines, so it never dominates. Direct replies are barely penalised; unprompted remarks strongly.

It speaks with probability `min(0.97, max U)` and picks among the candidates proportionally to U². Functional answers (facts, "shut up", being woken) are always given.

Spontaneous behaviours (small talk, topics, facts, loneliness) are scaled by the drive behind them. They only happen after `idle_after` of silence, never in a channel without human activity in the last 6 hours, and never more than twice in a row without anyone answering.

### Learning

After it speaks, a 90-second feedback window opens:

- **Reward**: laughter, thanks, compliments, or warm replies without another purpose.
- **Punishment**: "shut up", insults or being kicked.
- **Small cost**: silence after an *unprompted* remark.

Functional messages ("remember that the build is broken") never count as judgements, even with negative words in them. `soul learning #chan` shows the result.

### Explainability

`soul why #chan` lists the latest decisions, including the silent ones, with every candidate's score, the probability and the roll:

```
10:02:00 prefix by laura: reply.ask: reply.ask=0.95 | P=0.95 roll=0.46 -> reply.ask
10:51:00 idle 1272s: spont.lonely=0.32, spont.idle=0.10 | P=0.32 roll=0.83 -> silence
```

## Configuration

`soul.conf` is a plain INI file. It is **never executed**: an unknown option or a bad value is reported in the log with its line number, and the default is kept.

```ini
[soul]
names = soul
timezone = Europe/Madrid
humor = 70

[channel #mychannel]
active = yes
lang = es
mode = chatty

[permissions]
soul.admin = n

[ratelimit]
soul.talk = 6/5m
```

Options marked *per channel* can also go in a `[channel #name]` section, where they override the global value. Every option is listed with its default in [`soul.conf.example`](../soul.conf.example).

| Option | Default | |
|---|---|---|
| `enabled` | yes | Run at all |
| `active` *(per channel)* | no | Live in this channel |
| `mode` *(per channel)* | social | `quiet` only answers; `social` also reacts and makes small talk; `chatty` more of it |
| `lang` / `autolang` / `langs` *(per channel)* | en / yes / all | Default language; answer in the speaker's language; allowed languages |
| `simulate` *(per channel)* | no | Log what it would say instead of speaking |
| `names` | soul | Other names it answers to, besides its nick |
| `timezone`, `sleep_start`, `sleep_end` | Europe/Madrid, 3, 9 | Daily rhythm (same start and end = never sleeps) |
| `extraversion`, `agreeableness`, `humor`, `verbosity` | 60, 65, 60, 50 | Temperament, 0–100 |
| `typos` | yes | Occasional typos with self-correction |
| `topics`, `learn_facts` *(per channel)*, `facts_max` | yes, yes, 500 | Small talk from channel topics; taught facts |
| `idle_after`, `shush_time` *(per channel)* | 20m, 30m | Silence before small talk; how long "shut up" lasts |
| `ignore_nicks` | Q L S D | Nicks never answered |
| `private_chat`, `away` | no, no | Chat in private; set AWAY while asleep |
| `prefix`, `max_pub_lines`, `log_level`, `seed` | !, 4, info, 0 | Command prefix, output cap, log detail, random seed |

Rate limits: `soul.talk` (8/5m lines per channel), `soul.user` (4/60s replies per person), `soul.cmd` (6/30s commands per person).

## Phrase packs

Packs live in `packs/*.pack`. Your own go in `<soul-data>/soul-packs/*.pack`: they extend or add phrases and survive updates. The format is documented at the top of `lib/grammar.tcl`:

```
@lang en
[greet.reply]
- hi {nick} <smile>
- {nick}! long time no see! ~rel=friend ~mood=pos
- (hi|hello|hey there) {nick}, (how's it going|what's new)?
- *yawns* morning... ~time=morning ~energy=low
- hugs {nick} ~action
- see you || take care ~w=0.5
- {years} {years|year|years} together, {nick}!
```

- **Variables**: `{nick} {chan} {botnick} {randnick} {topic} {time} {fact_key} {fact} {fact_by} {kicker} {subject} {years} {count}`. An alternative whose variable is empty is skipped. Plurals: `{var|singular|plural}` picks the word by the variable's value (`{years} {years|year|years}`).
- **Tags**: `~w=` (weight), `~mood=`, `~energy=`, `~arousal=`, `~rel=`, `~time=`, `~action`.
- **Intents** are regular expressions per language in `[intent.NAME]`. Functional intents capture groups: `teach` = 2, `ask` = 1, `forget` = 1, `opinion` = 1.
- **Detection**: `[detect]` (lowercase, accent-free function words) and optionally `[detect.chars]`.
- **English is the master.** `tclsh tools/soulpack.tcl` checks that every language has the same symbols and intents, the right capture groups and only known variables.

`.soul reload` loads changed packs without restarting.

### Adding a language

1. Copy `packs/en.pack` to `packs/xx.pack` and set `@lang xx`.
2. Translate the phrases; write native intent regexes, lexicons, stopwords and `[detect]` words (lowercase, no accents).
3. Add `xx` to the values of `lang` and `langs` in `lib/engine.tcl`.
4. Add sample lines to `tests/fixtures/soul-langs.txt`.
5. Run `tclsh tools/soulpack.tcl` and `tclsh tests/all.tcl`.

## Safety and privacy

- **Off by default** in every channel. `simulate` logs instead of speaking.
- **Ignores** Eggdrop users flagged `b` (bots), the nicks in `ignore_nicks` (QuakeNet's Q, L, S and D by default) and people who opted out.
- **Loop protection**: at most 4 replies a minute per person and a per-channel talk budget.
- **"Shut up" is obeyed** for `shush_time`.
- **No message text is stored.** Topics are fading word counts, relationships are numbers. Facts exist only when someone teaches them, and links, adverts and channel invitations are refused.
- **Output** is split into safe lines (a CR/LF can never start a new IRC command) and `\001` is stripped, so nobody can make it send a CTCP.
- **Nothing is evaluated**: not the configuration, not the packs, not what people say.
- **Private chat** is off by default. When on, it never looks at lines meant for Eggdrop's own `/msg` commands (`pass`, `ident`…).
- **A bug cannot take the bot down**: errors in its handlers are caught and logged, and if there are too many in five minutes soul switches itself off until the next `.rehash`.
- Data files (`soul-data/*.db`) are written atomically with a checksum; a damaged file is moved aside and soul starts with a fresh memory instead of crashing.

## Limits

- It is not a language model: it understands what its intent patterns cover and answers from its packs.
- French, Italian, Portuguese and German were written with care but deserve review by native speakers; puns do not always carry over.
- Tested in a simulator of the Eggdrop API (`tests/`), not yet on a live network.
