# SPDX-License-Identifier: GPL-2.0-or-later

import std/[sets, strutils, algorithm, sequtils, times, options]
import types, backend, state, render, framework, display

# Unified prompt framework

template runPrompt[S, R](
    backend: TerminalBackend,
    prompt: string,
    hint: string,
    initialState: S,
    renderProc: proc(state: var S): seq[string] {.nimcall.},
    handleProc: proc(state: var S, event: InputEvent): bool,
    answerProc: proc(state: S): R,
    displayProc: proc(state: S): string,
    textual: static bool = false,
  ): untyped =
  ## Unified prompt template that handles all prompt types
  ## - prompt: The prompt text to display
  ## - hint: Optional hint (empty string = no hint line)
  ## - initialState: Initial state for the prompt
  ## - renderProc: Procedure that renders UI from state
  ## - handleProc: Procedure that handles input events
  ## - answerProc: Procedure that extracts answer from state
  ## - displayProc: Procedure that extracts display text from state
  ## - textual: Whether to treat spaces as text input
  ## Returns: (answer, display text)

  # 1. Show prompt
  showStyled(backend, PromptMsg, prompt)

  # 2. Show hint if provided
  let hasHint = hint.len > 0
  if hasHint:
      showStyled(backend, HintMsg, hint)

  # 3. Run interactive loop
  let finalState = runInteractive(
    backend,
    initialState,
    renderProc,
    handleProc,
    textual
  )

  # 4. Extract answer and display text
  let answer = answerProc(finalState)
  let display = displayProc(finalState)

  # 5. Clear hint line if shown
  if hasHint:
    backend.clearLines(1)

  # 6. Show answer
  if display.len > 0:
    showStyled(backend, AnswerMsg, display)

  (answer, display)

proc handleSelectionEvent[T](state: var SelectionState[T], event: InputEvent): bool =
  case event.action
  of Move:
    state.move(event.move)
    true
  of Select:
    state.toggle()
    true
  of Confirm:
    state.confirm()
    false
  else:
    true

proc selectedDisplay[T](state: SelectionState[T]): string =
  for idx in state.selected:
    if result.len > 0:
      result.add ", "
    result.add $state.options[idx]

proc handleSearchEvent[T](state: var SearchState[T], event: InputEvent;
                          allowAny: bool): bool =
  case event.action
  of Move:
    state.moveFiltered(event.move)
    true
  of TypeChar:
    state.addChar(event.ch)
    true
  of Backspace:
    state.backspace()
    true
  of Confirm:
    not allowAny and state.getSelectedIndex() == -1
  else:
    true

proc searchDisplay[T](state: SearchState[T]): string =
  let idx = state.getSelectedIndex()
  if idx == -1: state.query else: $state.options[idx]

proc handleStringsEvent(state: var StringsState, event: InputEvent): bool =
  case event.action
  of TypeChar:
    state.updateInput(event.ch)
    true
  of Backspace:
    state.backspace()
    true
  of Confirm:
    if state.input.len == 0:
      false
    else:
      state.addItem()
      true
  else:
    true

proc resolvedItems(state: StringsState; defaults: seq[string]): seq[string] =
  if state.items.len == 0: defaults else: state.items

proc stringsDisplay(state: StringsState; defaults: seq[string]): string =
  "[" & resolvedItems(state, defaults).join(", ") & "]"

proc handleValidationEvent[T](state: var ValidationState[T], event: InputEvent;
                              validator: proc(input: string, default: Option[T]): ValidationResult[T]): bool =
  case event.action
  of TypeChar:
    state.updateInput(event.ch)
    true
  of Backspace:
    state.backspace()
    true
  of Confirm:
    state.lastValidationResult = validator(state.input, state.default)
    if state.lastValidationResult.ok:
      false
    else:
      state.input = ""
      true
  else:
    true

proc validationDisplay[T](state: ValidationState[T]): string =
  if state.input.len > 0:
    state.input
  elif state.default.isSome:
    $state.default.unsafeGet()
  else:
    raise newException(Defect, "No default but the empty value accepter!")

# PUBLIC API

proc displayMessageLine*(backend: TerminalBackend, msgType: MsgType, message: string) =
  showStyled(backend, msgType, message)

proc success*(backend: TerminalBackend, message: string) =
  showStyled(backend, SuccessMsg, message)

proc error*(backend: TerminalBackend, message: string) =
  showStyled(backend, ErrorMsg, message)

proc promptSelection*[T](
    backend: TerminalBackend,
    prompt: string,
    options: openArray[T],
    multi: bool = false,
    defaults: set[int16] = {},
    maxShown: int = 0
  ): set[int16] =
  ## Interactive selection from a list of options
  ## Returns set of selected indices
  if options.len == 0:
    showStyled(backend, HintMsg, "No options available")
    return {}

  let hint = if multi: "Arrows/Tab/Home/End: navigate | Space: toggle | Enter: confirm"
             else: "Arrows/Tab/Home/End: navigate | Enter: confirm"

  let (selected, _) = runPrompt(
    backend, prompt, hint,
    initSelection(options, multi, defaults, maxShown),
    renderSelection,
    handleSelectionEvent[T],
    proc(state: SelectionState[T]): set[int16] = state.selected,
    selectedDisplay[T]
  )
  selected

proc promptSearch*[T](
    backend: TerminalBackend,
    question: string,
    options: openArray[T],
    query: var string,
    maxShown: int = 10,
    allowAny: bool = false,
  ): int =
  ## Interactive search with filtering
  ## Updates query var parameter with final query or selected option
  ## Returns index of selected option, or -1 if no match
  let (resIdx, display) = runPrompt(
    backend, question, "Type to filter | Arrows/Home/End: navigate | Enter: select",
    initSearch(@options, maxShown, query),
    renderSearch,
    proc(state: var SearchState[T], event: InputEvent): bool =
      handleSearchEvent(state, event, allowAny),
    getSelectedIndex,
    searchDisplay[T],
    textual = true
  )
  query = display
  resIdx

proc promptStrings*(
    backend: TerminalBackend,
    question: string,
    default: openArray[string] = []
  ): seq[string] =
  ## Prompt for multiple string inputs (empty line to finish)
  let promptText = formatPromptWithDefault(question, default.join(", "))
  let defaults = @default

  let (items, _) = runPrompt(
    backend,
    promptText,
    "Enter items. Empty line to finish.",
    initStrings(promptText, default),
    renderStrings,
    handleStringsEvent,
    proc(state: StringsState): seq[string] = resolvedItems(state, defaults),
    proc(state: StringsState): string = stringsDisplay(state, defaults),
    textual = true
  )
  items

proc promptImpl[T](
    backend: TerminalBackend,
    question: string,
    default: Option[T],
    validator: proc(input: string, default: Option[T]): ValidationResult[T]
  ): T =
  ## Prompt for typed input with validation
  let promptText = if default.isSome:
      formatPromptWithDefault(question, default.unsafeGet())
    else: question

  let (value, _) = runPrompt(
    backend,
    promptText,
    "",  # No hint
    initValidation(promptText, default),
    renderValidation,
    proc(state: var ValidationState[T], event: InputEvent): bool =
      handleValidationEvent(state, event, validator),
    proc(state: ValidationState[T]): T = state.lastValidationResult.value,
    validationDisplay[T],
    textual = true
  )
  value

proc promptTyped*[T: SomeNumber | string](
    backend: TerminalBackend,
    question: string,
    default: Option[T],
  ): T =
  promptImpl(backend, question, default, validate)

proc promptBool*(
    backend: TerminalBackend,
    question: string,
    default: Option[bool] = none(bool),
  ): bool =
  ## Prompt for a yes/no answer.
  let answers = registerSuggestedAnswers(["yes", "no"])
  let defaultKey =
    if default.isSome:
      some(if default.unsafeGet(): answers[0].key else: answers[1].key)
    else:
      none(char)
  let promptText = question & " " &
    formatCompactSuggestedAnswers(answers, if defaultKey.isSome: defaultKey.unsafeGet() else: '\0')

  proc validateBool(input: string; _: Option[bool]): ValidationResult[bool] =
    let res = validateSuggested(input, answers, defaultKey)
    if not res.ok:
      return ValidationResult[bool](kind: vrErr, error: res.error)
    ValidationResult[bool](kind: vrOk, value: res.value == answers[0].key)

  let (value, _) = runPrompt(
    backend,
    promptText,
    "",
    initValidation(promptText, none(bool)),
    renderValidation,
    proc(state: var ValidationState[bool], event: InputEvent): bool =
      handleValidationEvent(state, event, validateBool),
    proc(state: ValidationState[bool]): bool = state.lastValidationResult.value,
    proc(state: ValidationState[bool]): string =
      if state.lastValidationResult.value: answers[0].label else: answers[1].label,
    textual = true
  )
  value

proc promptDate*(
    backend: TerminalBackend,
    question: string,
    format: TimeFormat,
    defOpt: Option[DateTime],
  ): DateTime =
  proc validate(input: string; default: Option[DateTime]): ValidationResult[DateTime] =
    validateDate(input, format, default)
  promptImpl[DateTime](backend, question, defOpt, validate)

proc prepareEnumOptions[T: enum](options: set[T]; sortAlpha: bool; defaults: set[T]): (seq[T], set[int16]) =
  # Convert enum to options list + default indices
  if options.card == 0:
   raise newException(ValueError, "Cannot prompt with empty options set")
  let invalidDefaults = defaults - options
  if invalidDefaults.card > 0:
   raise newException(ValueError, "Default values not in options: " & $invalidDefaults)
  var options = toSeq(items(options))
  if sortAlpha:
    options.sort(proc (x, y: T): int = cmp($x, $y))
  var defIndices: set[int16]
  for i, opt in pairs(options):
    if opt in defaults: defIndices.incl i.int16
  (options, defIndices)

proc normalizeEnumDefault[T: enum](options: set[T]; default: T): T =
  if default in options:
    return default
  for opt in options:
    return opt

proc promptEnum*[T: enum](
    backend: TerminalBackend;
    question: string;
    options: set[T];
    default: T;
    sortAlpha: bool = false
  ): T =
  ## Prompt for enum selection
  let (options, defIndices) = prepareEnumOptions(options, sortAlpha, {normalizeEnumDefault(options, default)})
  let selected = promptSelection(backend, question, options, multi=false, defaults=defIndices)
  for i in selected: return options[i]

proc promptEnumSet*[T: enum](
    backend: TerminalBackend;
    question: string;
    options: set[T];
    defaults: set[T] = {};
    sortAlpha: bool = false
  ): set[T] =
  ## Prompt for multiple enum selections
  let (options, defIndices) = prepareEnumOptions(options, sortAlpha, defaults)
  let selected = promptSelection(backend, question, options, multi=true, defaults=defIndices)
  for i in selected:
    result.incl(options[i])
