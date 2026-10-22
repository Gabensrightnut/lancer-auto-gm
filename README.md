# Lancer Auto-GM

A fan-made 3D tactics game for the LANCER tabletop RPG, built in Godot 4. Play missions and
full campaigns online with friends, with a procedural Game Master that follows the book's rules.

Work in progress. See [DESIGN.md](DESIGN.md) for what it will do and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized.

## Running

Requires Godot 4.7.

```bash
godot --path .
```

Tests:

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

## Credits and licenses

- LANCER is © Massif Press. This is an unofficial fan project, not affiliated with or endorsed
  by Massif Press.
- `data/lancer-data/` is Massif Press's official game data, GPL-3.0-or-later. See
  [data/lancer-data/SOURCE.md](data/lancer-data/SOURCE.md).
- Built with [Godot Engine](https://godotengine.org) (MIT license).
- All models, art and code outside `data/lancer-data/` are original to this project and
  licensed GPL-3.0-or-later (see [LICENSE](LICENSE)).
