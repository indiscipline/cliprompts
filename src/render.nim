# SPDX-License-Identifier: GPL-2.0-or-later

import types, state, metrics, display

const UseUTFSymbols {.booldefine: "cliprompts.useutf".} = false

type Symbol = enum
  CheckboxUnchecked,
  CheckboxChecked,
  CheckboxFocused,
  RadioBtnOff,
  RadioBtnOn,
  MarkerFocused,
  MarkerUnfocused

const Symbols: array[Symbol, string] =
  when UseUTFSymbols:
    [ "☐", "☑", "□", "◯", "●", "▶", " " ]
  else:
    [ "[ ]", "[x]", "[_]", "( )", "(*)", ">", " " ]

proc selectionSymbols[T](state: SelectionState[T], idx: int): tuple[marker, checkbox: string] =
  let isFocused = idx == state.current
  let isSelected = idx.int16 in state.selected
  result.marker = if isFocused: Symbols[MarkerFocused] else: Symbols[MarkerUnfocused]
  result.checkbox =
    if state.multi:
      if isSelected: Symbols[CheckboxChecked]
      elif isFocused: Symbols[CheckboxFocused]
      else: Symbols[CheckboxUnchecked]
    else:
      if isFocused: Symbols[RadioBtnOn] else: Symbols[RadioBtnOff]

proc renderSelectionLine[T](state: SelectionState[T], idx: int): string =
  let (marker, checkbox) = selectionSymbols(state, idx)
  concat(spaces(PrefixOffset), marker, " ", checkbox, " ", $state.options[idx])

proc renderSelection*[T](state: var SelectionState[T]): seq[string] =
  ## Returns lines to display for selection UI
  trackRender:
    result = @[]
    let total = state.options.len
    let shown = effectiveMaxShown(state.maxShown, total)
    if shown >= total:
      for i in 0 ..< total:
        result.add renderSelectionLine(state, i)
      return
    ensureVisible(state.windowStart, state.current, state.maxShown, total)
    let endIdx = min(state.windowStart + shown, total)
    for i in state.windowStart ..< endIdx:
      result.add renderSelectionLine(state, i)

proc renderSearch*[T](state: var SearchState[T]): seq[string] =
  ## Returns lines: query input + filtered options
  const searchPrefix = "Search: " # keep shorter than longest $MsgType
  trackRender:
    result = @[]
    # Query line
    result.add concat(
      spaces(PrefixOffset + 2 - searchPrefix.len), # ": " already in prefix
      searchPrefix, state.query, "_")

    # Filtered options
    let filtered = state.getVisibleFiltered()
    for i, idx in filtered:
      let isFocused = (state.windowStart + i == state.current)
      let marker = if isFocused: Symbols[MarkerFocused] else: Symbols[MarkerUnfocused]
      result.add concat(spaces(PrefixOffset), marker, " ", $state.options[idx])


proc renderStrings*(state: var StringsState): seq[string] =
  result = @[]
  for item in state.items:
    result.add(formatPrefix(ItemMsg) & item)
  result.add(formatPrefix(ItemMsg) & state.input & "_")

proc renderValidation*[T](state: var ValidationState[T]): seq[string] =
  result = @[]
  if not state.lastValidationResult.ok:
    result.add(formatPrefix(ErrorMsg) & state.lastValidationResult.error)
  result.add(formatPrefix(AnswerMsg) & state.input & "_")
