# cliprompts
[![License](https://img.shields.io/badge/license-GPLv2%2B-blue.svg)](LICENSE)

> Interactive terminal prompts for Nim.

Cliprompts provides a set of interactive prompts for terminal applications:
selection, filtered search, and plain string input — all with correct visual
cleanup on any terminal width.

- **Typed and validated**: the values returned typed and user is re-prompted on errors.
- **Width-aware rendering**: Correctly handles terminals narrower than the displayed options. No stale characters left on screen after confirmation.
- **No dependencies** beyond the standard library.
- **Testable**: State, rendering, and input are pure functions. The mock backend records all writes and feeds queued input for deterministic tests without a TTY.

[![asciicast](https://asciinema.org/a/5bqFI0JC4plvfPwP.svg)](https://asciinema.org/a/5bqFI0JC4plvfPwP)

## Documentation
The documentation is located in the `docs` directory and is available at
[indiscipline.github.io/cliprompts](https://indiscipline.github.io/cliprompts).

## Installation

```bash
atlas use cliprompts
```

```bash
nimble install cliprompts
```

## Usage

```nim
import cliprompts

# Single selection returns selected indices.
let pick = promptSelection("Pick a colour", @["red", "green", "blue"])
if 1'i16 in pick:
  echo "green"

# Multi selection returns a set of checked indices.
let picks = promptSelection("Pick colours", @["red", "green", "blue"], multi = true)

# Search-filtered selection
let idx = promptSearch("Find a city",
  @["Amsterdam", "Berlin", "Cairo", "Dublin", "Edinburgh"],
  maxShown = 3)

# Search with a mutable query buffer. If `allowAny = true` and no item matches,
# the typed query is preserved and the returned index is `-1`.
var query = "ber"
let chosen = promptSearchMut("Find or type a city",
  @["Amsterdam", "Berlin", "Cairo"],
  query,
  allowAny = true)

# Plain string
let name = promptString("Your name", default = "World")

# Enum selection
type Color = enum Red, Green, Blue
let col = promptEnum[Color]("Favorite color", sortAlpha = true)

# Partial enum selection from a subset
let opt = promptEnum[Color]("Pick an accent", {Red, Blue}, sortAlpha = true)
```

`promptEnum(..., sortAlpha = true)` sorts by the enum case names shown to the
user. The initial selection still follows the `default` value you pass; if you
omit it, `T.low` is preselected even when that is not the first alphabetical
entry.

Search matching is case-insensitive and token-based: the query is split on
whitespace and every token must occur somewhere in the option text. In other
words, it is an AND of substrings, not a prefix match and not fuzzy ranking.
`"new yo"` matches `"New York"`, while `"new la"` does not.

## Testing

```bash
nimble test
```

## Requirements

* Nim 2.0 or later
* Terminal with ANSI escape-code support (Linux, macOS, Windows) or `cmd.exe`

## Tool-use disclosure

> LLM-based tools were extensively used in development. All code passed through tight human-loop inspection, though it's nowhere as "artisanal" as my previous libraries. Most tests and doc-comments were generated.

## License

cliprompts is licensed under GNU General Public License version 2.0 or later.
See [`LICENSE`](LICENSE) for full details.
