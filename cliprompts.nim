# SPDX-FileCopyrightText: 2026 Kirill Ildyuko
#
# SPDX-License-Identifier: GPL-2.0-or-later

## cliprompts: Interactive Terminal Prompts
## =========================================
##
## :Version: |nimbleversion|
##
## Interactive prompts for terminal applications: selection, filtered search,
## string and number input, enum selection, date parsing — all with correct
## visual cleanup on any terminal width.
##
## Why cliprompts
## --------------
##
## - **Ergonomic**: Single import gives you selection, search, text, numbers,
##   enums, and dates.
## - **Typed and validated**: the values returned typed and user is re-prompted on
##   errors.
## - **Width-aware rendering**: Correctly handles terminals narrower than the
##   displayed options. No stale characters left on screen after confirmation.
## - **No dependencies** beyond the standard library.
## - **Testable**: State, rendering, and input are pure functions. The
##   mock backend records all writes and feeds queued input for deterministic
##   tests without a TTY.
##
## Quick start
## -----------
##
## Import and call any prompt function:
##
runnableExamples("-r:off"):
  import std/strutils
  # Single selection
  let pick = promptSelection("Pick a colour", @["red", "green", "blue"])
  doAssert 0'i16 in pick or 1'i16 in pick or 2'i16 in pick
  # Multi selection
  let picks = promptSelection("Pick colours", @["red", "green", "blue"], multi = true)
  # Search-filtered selection
  let idx = promptSearch("Find a city",
    @["Amsterdam", "Berlin", "Cairo", "Dublin", "Edinburgh"], maxShown = 3)
  # Search with mutable query storage
  var query = "ber"
  let chosen = promptSearchMut("Find or type a city",
    @["Amsterdam", "Berlin", "Cairo"], query, allowAny = true)
  # Plain string
  let name = promptString("Your name", default = "World")
  # Yes/no prompt
  let proceed = promptBool("Continue?", default = true)
  # Number input
  let age = promptInt("Your age", default = 18)
  # Enum selection with explicit type parameter
  type Color = enum Red, Green, Blue
  let col = promptEnum[Color]("Favorite color", sortAlpha = true)
  # Partial enum selection
  let opt = promptEnum[Color]("Pick an accent", {Red, Blue}, sortAlpha = true)

## Notes on return values
## ----------------------
##
## - `promptSelection` always returns a `set[int16]` of selected indices.
##   Single-select prompts therefore return a singleton set.
## - `promptSearch` and `promptSearchMut` return the selected option index.
##   `promptSearchMut` additionally updates the caller-provided query buffer:
##   after a match it becomes the chosen display text; with `allowAny = true`
##   and no match it remains the raw typed query.
## - Search matching is case-insensitive and token-based: whitespace splits
##   the query into tokens and every token must appear as a substring in the
##   option text.
##
## Cancellation and Cleanup
## ------------------------
##
## While a cliprompts prompt is active, `Ctrl+C` is captured as prompt
## cancellation rather than passed through as a process-level interrupt.
## If the user cancels an active prompt with `Esc` or `Ctrl+C`, cliprompts
## clears the interactive frame, restores visible terminal state, and raises
## `IOError` to the caller.
##
## That guarantee applies only while control stays inside the prompt loop. If
## the host program terminates outside that flow, for example via `quit`, an
## unhandled exception, or an application-defined `Ctrl+C`/signal handler,
## use `restoreTerminalState`_ in your shutdown path:
##
## .. code-block:: nim
##
##   import cliprompts
##
##   try:
##     discard promptBool("Continue?")
##   finally:
##     restoreTerminalState()
##
## `restoreTerminalState()`_ is a best-effort application-level fallback.
## Normal prompt completion and prompt-local cancellation already restore
## terminal state internally, and cliprompts does not install a process-global
## `Ctrl+C` hook for you.
##
## Implementation notes
## --------------------
##
## Architecture follows the classic "state → view" pattern with a backend
## abstraction layer. Terminal I/O is isolated behind `TerminalBackend`, allowing
## `MockTerminal` for tests and real `RealTerminal` for production. The modular
## design keeps rendering logic separate from I/O and state management.
##

import src/[backend, prompts, types]
import std/[times, options]

var defaultBackend = newRealTerminal(stderr)

proc displayMessageLine*(msgType: MsgType, message: string) =
  prompts.displayMessageLine(defaultBackend, msgType, message)

proc success*(message: string) =
  ## Displays a success message with styled prefix.
  displayMessageLine(SuccessMsg, message)

proc error*(message: string) =
  ## Displays an error message with styled prefix.
  displayMessageLine(ErrorMsg, message)

proc restoreTerminalState*() =
  ## Best-effort fallback cleanup for application shutdown paths.
  ##
  ## This is intended for top-level `finally` blocks, `std/exitprocs`, or
  ## similar host-application cleanup. Normal prompt execution already restores
  ## terminal state internally.
  backend.restoreTerminalState(defaultBackend)

proc promptSelection*[T](question: string, options: openArray[T],
                        multi: bool = false, defaults: set[int16] = {}): set[int16] =
  ## Displays a list of options and waits for user selection.
  ##
  ## - `question`: Prompt text displayed above the options.
  ## - `options`: Sequence of items to choose from. Any type with `$` defined.
  ## - `multi`: If true, allows multiple selections (space to toggle).
  ## - `defaults`: Pre-selected indices for multi-select mode.
  ##
  ## Returns a set of selected indices. For single selection this is still a
  ## set, usually with exactly one member.
  ##
  runnableExamples():
    import src/backend
    let mock = newMockTerminal(width = 80)
    setBackend(mock)
    mock.queueInput("\27[B\r") # Down, Enter
    let selected = promptSelection("Pick", @["red", "green", "blue"])
    doAssert selected == {1'i16}
  prompts.promptSelection(defaultBackend, question, options, multi, defaults)

proc promptSearchMut*[T](question: string; options: openArray[T];
                     query: var string; maxShown: int = 10; allowAny: bool = false): int =
  ## Performs incremental search within `options`.
  ##
  ## - `question`: Prompt text.
  ## - `options`: Items to search through.
  ## - `query`: Mutable string that stores the current search query.
  ## - `maxShown`: Maximum number of results to display.
  ## - `allowAny`: If true, accepts Enter even with no matching results.
  ##
  ## Matching is case-insensitive and uses whitespace-separated query tokens.
  ## Every token must occur somewhere in the option text, so matching is an
  ## AND of substrings rather than prefix-only or fuzzy matching.
  ##
  ## Returns index of selected item, or `-1` when `allowAny = true` and the
  ## typed query does not match any option.
  ##
  ## On return, `query` is updated to the accepted text:
  ##
  ## - selected option text when a match was confirmed
  ## - raw typed query when `allowAny = true` accepted a non-match
  ##
  runnableExamples():
    import src/backend
    let mock = newMockTerminal(width = 80)
    setBackend(mock)
    var query = ""
    mock.queueInput("ca\r")
    let idx = promptSearchMut("City", @["Amsterdam", "Cairo", "Dublin"], query)
    doAssert idx == 1
    doAssert query == "Cairo"

  runnableExamples():
    import src/backend
    let mock = newMockTerminal(width = 80)
    setBackend(mock)
    var query = ""
    mock.queueInput("custom\r")
    let idx = promptSearchMut("Tag", @["nim", "terminal"], query, allowAny = true)
    doAssert idx == -1
    doAssert query == "custom"
  prompts.promptSearch(defaultBackend, question, options, query, maxShown, allowAny)

proc promptSearch*[T](question: string; options: openArray[T];
                     initialQuery: string = ""; maxShown: int = 10): int =
  ## Search prompt with optional initial query.
  ##
  ## Simplified variant with immutable initial query.
  ## Matching is case-insensitive and token-based: each whitespace-separated
  ## token in the query must occur somewhere in the option text.
  ## Returns the selected option index.
  var query = initialQuery
  prompts.promptSearch(defaultBackend, question, options, query, maxShown)

proc promptString*(question: string; default: string = ""): string =
  ## Prompts for a plain string input.
  ##
  ## - `question`: Prompt text.
  ## - `default`: Default value shown as placeholder.
  ##
  ## Returns the entered string, or default if user pressed Enter without typing.
  let defOpt = if default == "": none(string) else: some(default)
  prompts.promptTyped(defaultBackend, question, defOpt)

proc promptBool*(question: string; default: bool): bool =
  ## Prompts for a yes/no answer.
  ##
  ## Accepts the registered shortcut keys case-insensitively: `y` for yes and
  ## `n` for no. Pressing Enter accepts `default`. Esc or Ctrl+C cancels the
  ## prompt by raising `IOError`.
  ##
  runnableExamples():
    import src/backend
    let mock = newMockTerminal(width = 80)
    setBackend(mock)
    mock.queueInput("Y\r")
    doAssert promptBool("Continue?", default = false)
  prompts.promptBool(defaultBackend, question, some(default))

proc promptBool*(question: string): bool =
  ## Prompts for a yes/no answer without a default.
  ##
  ## Accepts `y`/`n` case-insensitively. Enter on empty input is rejected and
  ## re-prompts until a valid answer is entered. Esc or Ctrl+C raises `IOError`.
  prompts.promptBool(defaultBackend, question, none(bool))

proc promptNumber*[T: SomeNumber | range](question: string; default: T): T =
  ## Prompts for a number with a default value.
  ##
  ## Validates input and re-prompts on invalid entries.
  prompts.promptTyped(defaultBackend, question, some(default))

proc promptNumber*[T: SomeNumber | range](question: string): T =
  ## Prompts for a number without a default.
  ##
  ## Returns zero on empty input if T is a number, otherwise prompts until valid.
  prompts.promptTyped(defaultBackend, question, none(T))

proc promptInt*(question: string, default: int = 0): int =
  ## Convenience proc for integer input with default.
  prompts.promptTyped(defaultBackend, question, some(default))

proc promptInt*(question: string): int =
  ## Convenience proc for integer input without default.
  prompts.promptTyped(defaultBackend, question, none(int))

proc promptFloat*(question: string, default: float = 0.0): float =
  ## Convenience proc for float input with default.
  prompts.promptTyped(defaultBackend, question, some(default))

proc promptFloat*(question: string): float =
  ## Convenience proc for float input without default.
  prompts.promptTyped(defaultBackend, question, none(float))

proc promptEnum*[T: enum](question: string; default: T = T.low, sortAlpha: bool = false): T =
  ## Prompts to select a value from an enum type.
  ##
  ## - `question`: Prompt text.
  ## - `default`: Pre-selected value (defaults to enum's low value).
  ## - `sortAlpha`: If true, displays options alphabetically by `$` name.
  ##
  ## `sortAlpha` changes display order only. The initial selection is still
  ## `default`, or `T.low` if you omit it.
  ##
  ## Raises `ValueError` at runtime if the enum type has no selectable values.
  prompts.promptEnum(defaultBackend, question, {T.low..T.high}, default, sortAlpha)

proc promptEnum*[T: enum](question: string; options: set[T]; default: T = T.low, sortAlpha: bool = false): T =
  ## Prompts to select from a subset of enum values.
  ##
  ## `sortAlpha` changes display order only. If `default` is in `options`, it
  ## is initially selected. Otherwise the prompt falls back to an arbitrary
  ## member of `options`.
  ##
  ## Raises `ValueError` at runtime if `options` is empty.
  prompts.promptEnum(defaultBackend, question, options, default, sortAlpha)

proc promptEnumSet*[T: enum](question: string; defaults: set[T] = {}, sortAlpha: bool = false): set[T] =
  ## Prompts to select multiple enum values.
  ##
  ## Returns a set of selected enum values. `sortAlpha` changes only the
  ## displayed order; `defaults` still refer to enum values, not sorted indices.
  ##
  ## Raises `ValueError` at runtime if any value in `defaults` is not
  ## selectable.
  prompts.promptEnumSet(defaultBackend, question, {T.low..T.high}, defaults, sortAlpha)

proc promptEnumSet*[T: enum](question: string; options: set[T]; defaults: set[T] = {}, sortAlpha: bool = false): set[T] =
  ## Prompts to select from a subset of enum values (multi-select).
  ##
  ## Raises `ValueError` at runtime if `options` is empty, or if any value in
  ## `defaults` is not contained in `options`.
  prompts.promptEnumSet(defaultBackend, question, options, defaults, sortAlpha)

proc promptStrings*(question: string, default: openArray[string] = []): seq[string] =
  ## Prompts for multiple string entries, terminated by empty line.
  ##
  ## - `question`: Prompt text.
  ## - `default`: Pre-populated list of strings.
  ##
  ## User presses Enter on empty line to finish.
  prompts.promptStrings(defaultBackend, question, default)

proc promptDate*(question: string; format: TimeFormat; default: string = "";
  ): DateTime =
  ## Prompts for a date/time string parsed by the given format.
  ##
  ## - `question`: Prompt text.
  ## - `format`: Nim `TimeFormat` for parsing the input.
  ## - `default`: Pre-filled date string.
  ##
  ## .. warning:: Raises `TimeParseError` if default is non-empty and unparseable.
  let defOpt = if default == "": none(DateTime) else: some(parse(default, format))
  prompts.promptDate(defaultBackend, question, format, defOpt)

proc setBackend*(backend: TerminalBackend) =
  ## Switches the internal backend for testing.
  ##
  ## Use with `MockTerminal` to run deterministic tests without a real TTY:
  ##
  runnableExamples():
    import src/backend, std/strutils
    let mock = newMockTerminal(width = 80)
    setBackend(mock)
    mock.queueInput("abc\r")
    discard promptString("Name")
    doAssert mock.lines[0].contains("Name")

  defaultBackend = backend
