# SPDX-License-Identifier: GPL-2.0-or-later

import std/[sets, strutils, times, unicode, sequtils, options]
import types
{.experimental: "views".}

type
  SelectionState*[T] = object
    options*: seq[T]
    current*: int
    selected*: set[int16]
    multi*: bool
    maxShown*: int
    windowStart*: int

  SearchState*[T] = object
    options*: seq[T]
    query*: string
    current*: int
    maxShown*: int
    windowStart*: int
    cachedFiltered: seq[int]
    cacheValid: bool
    optionsLowered: seq[string]

  ValidationKind* = enum
    vrOk, vrErr

  ValidationResult*[T] = object
    case kind*: ValidationKind
    of vrOk:
      value*: T        ## accepted value
    of vrErr:
      error*: string   ## non-empty when ok == false

  ValidationState*[T] = object
    default*: Option[T]
    input*: string
    lastValidationResult*: ValidationResult[T]

  StringsState* = object
    items*: seq[string]
    input*: string

template ok*[T](v: ValidationResult[T]): bool =
  v.kind == vrOk

proc registerSuggestedAnswers*(labels: openArray[string]): seq[SuggestedAnswer] =
  var used: set[char]
  for label in labels:
    if label.len == 0:
      raise newException(ValueError, "Suggested answers cannot contain empty labels")
    var assigned = false
    for ch in label:
      let key = ch.toLowerAscii()
      if key notin Letters + Digits:
        continue
      if key notin used:
        used.incl key
        result.add SuggestedAnswer(label: label, key: key)
        assigned = true
        break
    if not assigned:
      raise newException(ValueError,
        "Could not assign a unique shortcut key for suggested answer: " & label)

proc validateSuggested*(input: string; answers: openArray[SuggestedAnswer];
                        defaultKey: Option[char] = none(char)): ValidationResult[char] =
  if input.len == 0:
    if defaultKey.isSome:
      return ValidationResult[char](kind: vrOk, value: defaultKey.unsafeGet())
    return ValidationResult[char](kind: vrErr, error: "No input and no default provided.")

  if input.len != 1:
    return ValidationResult[char](kind: vrErr, error: "Please enter one of the suggested answers.")

  let key = input[0].toLowerAscii()
  for answer in answers:
    if answer.key == key:
      return ValidationResult[char](kind: vrOk, value: key)

  ValidationResult[char](kind: vrErr, error: "Please enter one of the suggested answers.")

# Selection state operations
proc initSelection*[T](options: openArray[T], multi: bool = false,
                      defaults: set[int16] = {},
                      maxShown: int = 0): SelectionState[T] =
  result.options = @options
  result.multi = multi
  result.selected = defaults
  result.maxShown = maxShown
  result.windowStart = 0
  if defaults.card > 0:
    for i in defaults:
      result.current = ord(i)
      break
  else:
    result.current = 0

proc effectiveMaxShown*(maxShown, total: int): int =
  if maxShown <= 0 or maxShown >= total: total else: maxShown

proc ensureVisible*(windowStart: var int, current: int, maxShown: int, total: int) =
  if total <= 0: return
  let shown = effectiveMaxShown(maxShown, total)
  if shown >= total:
    windowStart = 0
    return
  if current < windowStart:
    windowStart = current
  elif current >= windowStart + shown:
    windowStart = current - shown + 1
  let maxStart = max(0, total - shown)
  if windowStart > maxStart:
    windowStart = maxStart

proc moveCursorBy(current, windowStart: var int; maxShown, total, delta: int) =
  if total <= 0:
    return
  current = (total + current + delta) mod total
  ensureVisible(windowStart, current, maxShown, total)

proc moveCursorTo(current, windowStart: var int; maxShown, total, index: int) =
  if total <= 0:
    return
  current = index
  ensureVisible(windowStart, current, maxShown, total)

proc moveCursor(current, windowStart: var int; maxShown, total: int; move: MoveCmd) =
  case move.kind
  of mkRelative:
    moveCursorBy(current, windowStart, maxShown, total, move.delta)
  of mkHome:
    moveCursorTo(current, windowStart, maxShown, total, 0)
  of mkEnd:
    moveCursorTo(current, windowStart, maxShown, total, total - 1)

proc move*[T](state: var SelectionState[T], cmd: MoveCmd) =
  moveCursor(state.current, state.windowStart, state.maxShown, state.options.len, cmd)

proc toggle*[T](state: var SelectionState[T]) =
  if not state.multi: return
  let idx = state.current.int16
  if idx in state.selected:
    state.selected.excl(idx)
  else:
    state.selected.incl(idx)

proc confirm*[T](state: var SelectionState[T]) =
  if not state.multi:
    state.selected = {state.current.int16}

# Search state operations
proc initSearch*[T](options: openArray[T], maxShown: int = 10,
                   initialQuery: string = ""): SearchState[T] =
  SearchState[T](
    optionsLowered: options.mapIt(unicode.toLower($it)),
    options: @options,
    maxShown: maxShown,
    query: initialQuery,
    current: 0,
    windowStart: 0,
    cachedFiltered: @[],
    cacheValid: false,
  )

proc updateQuery*[T](state: var SearchState[T], query: string) =
  state.query = query
  state.current = 0
  state.windowStart = 0
  state.cacheValid = false

proc addChar*[T](state: var SearchState[T], ch: char) =
  state.query.add(ch)
  state.current = 0
  state.windowStart = 0
  state.cacheValid = false

proc backspace*[T](state: var SearchState[T]) =
  if state.query.len > 0:
    state.query.setLen(state.query.len - 1)
    state.current = 0
    state.windowStart = 0
    state.cacheValid = false

proc getFiltered*[T](state: var SearchState[T]): seq[int] =
  ## Returns indices of options matching query tokens (case-insensitive AND search)
  if state.cacheValid:
    return state.cachedFiltered

  result = @[]

  let tokens =
    unicode.splitWhitespace(state.query).filterIt(it.len > 0)
    .mapIt( (let s = toLower(it); (initSkipTable(s), s)) )

  # Empty query => show all items
  if tokens.len == 0:
    for i in 0 ..< state.options.len:
      result.add(i)
    state.cachedFiltered = result
    state.cacheValid = true
    return

  for i, opt in state.optionsLowered:
    if tokens.allIt(find(it[0], opt, it[1]) != -1):
      result.add(i)

  state.cachedFiltered = result
  state.cacheValid = true

proc moveFiltered*[T](state: var SearchState[T], cmd: MoveCmd) =
  let filtered = state.getFiltered()
  moveCursor(state.current, state.windowStart, state.maxShown, filtered.len, cmd)

proc getVisibleFiltered*[T](state: var SearchState[T]): seq[int] =
  let filtered = state.getFiltered()
  if filtered.len == 0:
    return @[]
  ensureVisible(state.windowStart, state.current, state.maxShown, filtered.len)
  let shown = effectiveMaxShown(state.maxShown, filtered.len)
  if shown >= filtered.len:
    return filtered
  let endIdx = min(state.windowStart + shown, filtered.len)
  filtered[state.windowStart ..< endIdx]

proc getSelectedIndex*[T](state: SearchState[T]): int =
  assert state.cacheValid
  if state.cachedFiltered.len == 0 or state.cachedFiltered.len <= state.current:
    return -1
  state.cachedFiltered[state.current]

# Strings state operations
proc initStrings*(question: string, defaults: openArray[string] = []): StringsState =
  # Defaults are not pre-populated!
  result.items = @[]
  result.input = ""

proc addItem*(state: var StringsState) =
  if state.input.len > 0:
    state.items.add(state.input)
    state.input = ""

proc updateInput*(state: var StringsState, ch: char) =
  state.input.add(ch)

proc backspace*(state: var StringsState) =
  if state.input.len > 0:
    state.input.setLen(state.input.len - 1)

 # Validation state operations

proc initValidation*[T](prompt: string, default: Option[T]): ValidationState[T] =
  ValidationState[T](
    input: "",
    default: default,
    lastValidationResult: ValidationResult[T](kind: vrOk, value: default(T)))

proc updateInput*[T](state: var ValidationState[T], ch: char) =
  state.input.add(ch)

proc backspace*[T](state: var ValidationState[T]) =
  if state.input.len > 0:
    state.input.setLen(state.input.len - 1)

proc validate*(input: string, default: Option[string]): ValidationResult[string] =
  let finalVal = if input.len == 0 and default.isSome:
      default.unsafeGet()
    else: input
  ValidationResult[string](kind: vrOk, value: finalVal)

proc validate*[T: range | SomeNumber](input: string, default: Option[T]): ValidationResult[T] =
  ## Pure validation for numeric input. Returns the accepted value
  ## or an error message. Empty input resolves to default.
  if input.len == 0:
    if default.isSome:
      ValidationResult[T](kind: vrOk, value: unsafeGet(default))
    else:
      ValidationResult[T](kind: vrErr, error: "No input and no default provided.")
  else:
    try:
      let parsed = (
        when T is SomeFloat: parseFloat(input)
        else:
          when T is SomeInteger: parseInt(input)
          else: {.error: "Unsupported type " & $T.})
      if parsed in low(T)..high(T):
        ValidationResult[T](kind: vrOk, value: parsed)
      else:
        ValidationResult[T](kind: vrErr,
          error: "Input out of range. Valid range: " & $low(T) & ".." & $high(T) & ".")
    except ValueError as e:
      ValidationResult[T](kind: vrErr, error: e.msg)

proc validateDate*(input: string; format: TimeFormat; default: Option[DateTime]): ValidationResult[DateTime] =
  ## Pure validation for date input.  Empty input resolves to default if
  ## non-empty, otherwise errors.
  if input.len == 0:
    if default.isSome:
      ValidationResult[DateTime](kind: vrOk, value: unsafeGet(default))
    else:
      ValidationResult[DateTime](kind: vrErr, error: "No input and no default provided.")
  else:
    try:
      let dt = parse(input, format)
      ValidationResult[DateTime](kind: vrOk, value: dt)
    except ValueError as e:
      ValidationResult[DateTime](kind: vrErr, error: e.msg)
