# SPDX-License-Identifier: GPL-2.0-or-later

import std/[terminal, times]

type
  DisplayType* = enum
    Error, Warning, Details, Hint, Message, Success

  MsgType* = enum
    SuccessMsg    = "Success",
    ErrorMsg      = "Error",
    PromptMsg     = "Prompt",
    AnswerMsg     = "Answer",
    HintMsg       = "Hint",
    InfoMsg       = "Info",
    ItemMsg       = "Item",
    AddedMsg      = "Added",
    ContinuingMsg = "...",

  MoveKind* = enum
    mkRelative, mkHome, mkEnd

  MoveCmd* = object
    case kind*: MoveKind
    of mkRelative:
      delta*: int
    of mkHome, mkEnd:
      discard

  InputAction* = enum
    Move, Select, Confirm, Cancel, TypeChar, Backspace, NoOp

  InputKeyKind* = enum
    ikChar,
    ikEnter,
    ikCtrlC,
    ikEscape,
    ikBackspace,
    ikTab,
    ikHome,
    ikEnd,
    ikUp,
    ikDown,
    ikLeft,
    ikRight,
    ikUnknown

  InputKey* = object
    case kind*: InputKeyKind
    of ikChar:
      ch*: char
    of ikEnter, ikCtrlC, ikEscape, ikBackspace, ikTab, ikHome, ikEnd,
       ikUp, ikDown, ikLeft, ikRight, ikUnknown:
      discard

  InputEvent* = object
    case action*: InputAction
    of Move:
      move*: MoveCmd
    of Select, Confirm, Cancel, Backspace, NoOp:
      discard
    of TypeChar:
      ch*: char

  StyleConfig* = object
    foreground*: ForegroundColor
    styles*: set[Style]

  SuggestedAnswer* = object
    label*: string
    key*: char

  DateTimeFormatted* = object
    dt*: DateTime
    format*: TimeFormat

proc `==`*(a, b: InputKey): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of ikChar:
    a.ch == b.ch
  of ikEnter, ikCtrlC, ikEscape, ikBackspace, ikTab, ikHome, ikEnd,
     ikUp, ikDown, ikLeft, ikRight, ikUnknown:
    true
