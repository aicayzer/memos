#!/bin/zsh
# Opens the app on a sample store, so a screenshot shows made-up memos rather than anyone's own. The
# sample sits inside the app's container, which is the one place the sandbox lets it read; it is written
# afresh each time, with dates relative to now so the side pane's sections all show, and removed once the
# app quits. The next ordinary launch reads the real store again.
#
#   scripts/screenshots.sh [path/to/Memos.app]
set -euo pipefail

fail() { print -u2 -- "screenshots: $*"; exit 1 }

app="${1:-/Applications/Memos.app}"
[[ -d "$app" ]] || fail "no app at $app"
id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
support="$HOME/Library/Containers/$id/Data/Library/Application Support"
[[ -d "$support" ]] || fail "the app has not run yet; open it once first"
sample="$support/sample.json"

python3 - "$sample" <<'PY'
import json, sys, uuid
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)

def memo(markdown, ago, favorite=False, made=None):
    updated = now - ago
    created = updated - (made or timedelta(hours=1))
    stamp = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.") + f"{d.microsecond // 1000:03d}Z"
    return {
        "id": str(uuid.uuid4()).upper(),
        "markdown": markdown,
        "favorite": favorite,
        "createdAt": stamp(created),
        "updatedAt": stamp(updated),
    }

memos = [
    memo("""# Lisbon, first week of May

Four nights, flying out on the Tuesday.

## Before we go

- [x] Book the flights
- [x] Apartment in Alfama
- [ ] Travel insurance
- [ ] Tell the bank

## Days

1. **Alfama** and the castle, dinner somewhere small
2. Tram 28 early, then *Belém* for the custard tarts
3. Sintra by train, back for sunset at a miradouro
4. Nothing planned

> Pack light. Last time the cobbles won.
""", timedelta(minutes=25), made=timedelta(days=3)),
    memo("""# Weekly plan

- [x] Send the revised proposal
- [x] Book the dentist
- [ ] Draft the talk outline
- [ ] Call Sam about the garden
- [ ] Renew the passport before it is a problem
""", timedelta(hours=3), made=timedelta(days=1)),
    memo("""# Reading list

- *The Overstory*, Richard Powers
- *Piranesi*, Susanna Clarke
- *A Field Guide to Getting Lost*, Rebecca Solnit
- *The Warmth of Other Suns*, Isabel Wilkerson
- *Klara and the Sun*, Kazuo Ishiguro
""", timedelta(days=1, hours=2), favorite=True, made=timedelta(days=40)),
    memo("""# Groceries

- Sourdough starter flour
- Lemons
- Olive oil, the good one
- Eggs
- Parmesan
- Basil
""", timedelta(days=1, hours=6)),
    memo("""# Sourdough

1. Feed the starter the night before
2. Mix at 78% hydration, rest an hour
3. Four stretch-and-folds, half an hour apart
4. Shape, then the fridge overnight
5. Bake at 250°C covered, 230°C uncovered

> The crumb wants patience more than skill.
""", timedelta(days=4)),
    memo("""# Rotate a list

```python
def rotate(items, by):
    by %= len(items)
    return items[by:] + items[:by]
```

Handles a negative `by` too, since `%` follows the divisor's sign.
""", timedelta(days=6)),
    memo("""# Ideas

- A tiny app that only does one thing well
- Learn to sharpen knives properly
- Long walk along the whole canal, one Saturday
- Write up the sourdough method for Dad
""", timedelta(days=16), made=timedelta(days=30)),
    memo("""# Kitchen

## Decided

- Oak worktop, oiled not varnished
- The tap with the pull-out spray

## Still open

- Tiles: plain white or the green ones?
- Whether the island fits once the door swings
""", timedelta(days=41), made=timedelta(days=10)),
    memo("""# Shakshuka

Serves two, twenty minutes.

- Onion, a red pepper, garlic
- Tin of tomatoes, cumin, smoked paprika
- Four eggs, feta, coriander

Soften the onion and pepper, add the spices, then the tomatoes. Simmer until thick, make wells, crack in the eggs, lid on for five minutes. Feta and coriander over the top; bread underneath.
""", timedelta(days=58)),
    memo("""# Quotes

> The best time to plant a tree was twenty years ago. The second best time is now.

> Simplicity is the ultimate sophistication.

> Everything should be made as simple as possible, but not simpler.
""", timedelta(days=95), favorite=True, made=timedelta(days=200)),
]

with open(sys.argv[1], "w") as file:
    json.dump({"memos": memos}, file, indent=2, sort_keys=True)
    file.write("\n")
PY

osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 || true
while pgrep -qf "$app/Contents/MacOS/"; do sleep 0.3; done
open -a "$app" --env "MEMOS_STORE=$sample"
print -- "screenshots: Memos is showing the sample; quit it when done"
sleep 3
while pgrep -qf "$app/Contents/MacOS/"; do sleep 1; done
rm -f "$sample" "$sample.lock"
print -- "screenshots: sample removed"
