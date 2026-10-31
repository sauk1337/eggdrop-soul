# Contributing · Contribuir

## English

- Run `tclsh tests/all.tcl` and `tclsh tools/soulpack.tcl` before sending a change; both must pass.
- **Sources stay pure ASCII.** Eggdrop reads scripts in the system encoding, so write non-ASCII characters in `.tcl` files as `\uXXXX`. `python tools/ascii_escape.py --check $(find . -name '*.tcl' -o -name '*.test')` checks it; without `--check` it rewrites the files.
- **Packs are UTF-8 data**, never code. English (`packs/en.pack`) is the master: a new symbol or intent goes there first, then into every other pack.
- Never evaluate user text (`eval`, `subst`, `uplevel` on input) and never split it with Tcl list commands: use `::soul::rt::words` / `::soul::rt::rest`.
- New options are declared with `::soul::rt::config::declare`; regenerate the example with `tclsh tools/example.tcl` (a test checks it is up to date).
- Translations by native speakers are especially welcome.

## Español

- Ejecuta `tclsh tests/all.tcl` y `tclsh tools/soulpack.tcl` antes de enviar un cambio; los dos tienen que pasar.
- **El código fuente es ASCII puro.** Eggdrop lee los scripts con la codificación del sistema, así que en los `.tcl` los caracteres no ASCII se escriben como `\uXXXX`. Para comprobarlo: `python tools/ascii_escape.py --check $(find . -name '*.tcl' -o -name '*.test')`. Sin `--check`, la herramienta reescribe los ficheros.
- **Los paquetes son datos en UTF-8**, nunca código. El inglés (`packs/en.pack`) es el maestro: un símbolo o una intención nuevos van primero ahí y después a los demás paquetes.
- Nunca evalúes texto de usuarios (`eval`, `subst` o `uplevel` sobre la entrada) ni lo partas con comandos de listas de Tcl: usa `::soul::rt::words` / `::soul::rt::rest`.
- Las opciones nuevas se declaran con `::soul::rt::config::declare`. Después regenera el ejemplo con `tclsh tools/example.tcl`; una prueba comprueba que está al día.
- Se agradecen especialmente las revisiones de traducciones por hablantes nativos.
