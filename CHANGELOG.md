# Changelog

## 1.0.0 — 2026-10-31

First standalone release (previously developed as a module of a larger Eggdrop script package).

- Personality engine: mood, circadian energy and sleep, social need and boredom, per-channel reinforcement learning, utility-based decisions with an explainable log.
- Memory: relationships by handle or host, aggregated channel topics, taught facts with attribution, opt-outs, anniversaries and milestones, opinions.
- Six phrase packs (English master, Spanish, French, Italian, Portuguese, German) with per-line language detection and replies in each speaker's language.
- Own runtime (`lib/rt.tcl`): validated INI configuration, atomic checksummed storage, rate limits, permissions, a single timer, error-isolating binds with a circuit breaker, the `soul` command in channels, by `/msg` and on the partyline.
- Tools: pack validator, simulated-day demo, example-config generator. 50 tests in an Eggdrop simulator.
