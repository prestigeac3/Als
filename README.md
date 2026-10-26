# ALS NetBattle

BN-inspired greybox vertical slice for **own creative / learning use** (original chip names; no Capcom assets).

## Prototype question

Is **panel movement + 30-chip folder / custom select / chip queue** fun with placeholder art?

## Run

Godot 4.3+: open `/workspace/als-netbattle` or:

```bash
godot --path /workspace/als-netbattle
```

## Controls

| Key | Action |
|-----|--------|
| 1–5 | Custom: toggle chip |
| Enter | Confirm custom → battle |
| WASD / arrows | Move on your panels |
| X / Z | Buster |
| Space | Fire next queued chip |
| C | Open custom (when gauge full) |

## Layout

- 6×3 panels: player owns left 3×3, enemy right 3×3 (PanelSteal can shift)
- Folder size 30 → draw 5 each custom → link same code (or `*`)
