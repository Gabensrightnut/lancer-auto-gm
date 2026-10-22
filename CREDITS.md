# Credits

## People (MakeHuman / MPFB2)

Human bodies and faces use open-source MakeHuman assets, the one approved exception to
"models made in house" (user decision, see DESIGN.md). Only the assets below are used, and
each one's license was checked. They are built into `assets/people/human_male.glb` and
`human_female.glb` by `tools/blender/people_mh.py`. The gear, rig animations and game code are
our own.

| What | From | License |
|---|---|---|
| Base mesh, body/face shape targets (macro details, head shapes, expression units) | MPFB 2.0.18 for Blender (extensions.blender.org, sha256 c075b3e9...2a2dad) | CC0 (MakeHuman assets); the MPFB add-on code is GPL-3.0-or-later and is only used as a build tool, not shipped |
| "game_engine" skeleton and skin weights | MPFB 2.0.18 | CC0 |
| Skins (young_caucasian_male, young_caucasian_female), eyes (low-poly), eyebrows (eyebrow001, eyebrow010), eyelashes (eyelashes01), teeth (teeth_base) | makehuman_system_assets_cc0.zip (files.makehumancommunity.org) | CC0, every asset in the pack |
| Hair: short01-04, long01, ponytail01, braid01, bob01, afro01 | makehuman_system_assets_cc0.zip | CC0 |

MakeHuman: http://www.makehumancommunity.org. Thanks to the MakeHuman community for releasing
these assets to the public domain.

Not used: briaai/RMBG-1.4 (non-commercial license). The image-to-3D tools (TripoSR, TripoSG)
make reference blockouts in /local only; nothing they output is in the repo or the game.
