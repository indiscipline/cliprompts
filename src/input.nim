# SPDX-FileCopyrightText: 2026 ZoomRmc
#
# SPDX-License-Identifier: GPL-2.0-or-later

import types
from std/strutils import PrintableChars

when defined(windows):
  import std/winlean

  proc getConsoleMode(hConsoleHandle: Handle, dwMode: ptr DWORD): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}

  proc setConsoleMode(hConsoleHandle: Handle, dwMode: DWORD): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}

export PrintableChars

when defined(windows):
  const
    KeyEvent = 1'i16
    EnableProcessedInput = 0x0001'i32
    LeftCtrlPressed = 0x0008'i32
    RightCtrlPressed = 0x0004'i32
    VkC = 0x43'i16
    VkBack = 0x08'i16
    VkTab = 0x09'i16
    VkReturn = 0x0D'i16
    VkEnd = 0x23'i16
    VkHome = 0x24'i16
    VkEscape = 0x1B'i16
    VkLeft = 0x25'i16
    VkUp = 0x26'i16
    VkRight = 0x27'i16
    VkDown = 0x28'i16

proc decodeDirectKey(ch: char): InputKey =
  case ch
  of '\r', '\n':
    InputKey(kind: ikEnter)
  of '\3':
    InputKey(kind: ikCtrlC)
  of '\t':
    InputKey(kind: ikTab)
  of '\b', '\127':
    InputKey(kind: ikBackspace)
  else:
    InputKey(kind: ikUnknown)

proc decodeArrowKey(ch: char): InputKey =
  case ch
  of 'A', 'H':
    InputKey(kind: ikUp)
  of 'B', 'P':
    InputKey(kind: ikDown)
  of 'C', 'M':
    InputKey(kind: ikRight)
  of 'D', 'K':
    InputKey(kind: ikLeft)
  else:
    InputKey(kind: ikUnknown)

proc decodeCsiTildeKey(ch: char): InputKey =
  case ch
  of '1', '7':
    InputKey(kind: ikHome)
  of '4', '8':
    InputKey(kind: ikEnd)
  else:
    InputKey(kind: ikUnknown)

proc decodeEscapeSequence(getNext: proc(): char): InputKey =
  case getNext()
  of '\27':  # Double ESC = cancel on byte-stream terminals
    InputKey(kind: ikEscape)
  of '[':
    let ch = getNext()
    case ch
    of 'H':
      InputKey(kind: ikHome)
    of 'F':
      InputKey(kind: ikEnd)
    of 'A', 'B', 'C', 'D':
      decodeArrowKey(ch)
    of '1', '4', '7', '8':
      let key = decodeCsiTildeKey(ch)
      if key.kind != ikUnknown and getNext() == '~':
        key
      else:
        InputKey(kind: ikUnknown)
    else:
      InputKey(kind: ikUnknown)
  of 'O':
    case getNext()
    of 'H':
      InputKey(kind: ikHome)
    of 'F':
      InputKey(kind: ikEnd)
    else:
      InputKey(kind: ikUnknown)
  of '\0', '\xE0':  # Legacy Windows cmd.exe extended keys
    let ch = getNext()
    case ch
    of 'G':
      InputKey(kind: ikHome)
    of 'O':
      InputKey(kind: ikEnd)
    of 'H', 'P', 'M', 'K':
      decodeArrowKey(ch)
    else:
      InputKey(kind: ikUnknown)
  else:
    InputKey(kind: ikUnknown)

template parseKeyImpl(ch: char; getNext: untyped): InputKey =
  ## Converts raw terminal input bytes to a platform-neutral key.
  ## getNext() is called for escape sequences
  let direct = decodeDirectKey(ch)
  if direct.kind != ikUnknown:
    direct
  elif ch == '\27':  # ESC - start of escape sequence
    decodeEscapeSequence(proc(): char = getNext)
  else:
    if ch in PrintableChars:
      InputKey(kind: ikChar, ch: ch)
    else:
      InputKey(kind: ikUnknown)

proc parseKey*(ch: char; getNext: proc(): char): InputKey =
  ## Converts raw terminal bytes to a platform-neutral key.
  ## getNext() is called for escape sequences
  parseKeyImpl(ch, getNext())

proc parseKey*(ch: char; input: openArray[char]): InputKey =
  ## Convenience overload for testing
  let buffered = @input
  var i = -1
  parseKeyImpl(ch):
    (inc(i); buffered[i])

proc parseInput*(key: InputKey; textual: static bool = false): InputEvent =
  ## Converts a platform-neutral key to a semantic input event.
  case key.kind
  of ikEnter:
    InputEvent(action: Confirm)
  of ikCtrlC, ikEscape:
    InputEvent(action: Cancel)
  of ikTab:
    InputEvent(action: Move, move: MoveCmd(kind: mkRelative, delta: 1))
  of ikBackspace:
    InputEvent(action: Backspace)
  of ikHome:
    InputEvent(action: Move, move: MoveCmd(kind: mkHome))
  of ikEnd:
    InputEvent(action: Move, move: MoveCmd(kind: mkEnd))
  of ikUp:
    InputEvent(action: Move, move: MoveCmd(kind: mkRelative, delta: -1))
  of ikDown:
    InputEvent(action: Move, move: MoveCmd(kind: mkRelative, delta: 1))
  of ikChar:
    if key.ch == ' ' and not textual:
      InputEvent(action: Select)
    else:
      InputEvent(action: TypeChar, ch: key.ch)
  of ikLeft, ikRight, ikUnknown:
    InputEvent(action: NoOp)

proc parseInput*(ch: char; getNext: proc(): char; textual: static bool = false): InputEvent =
  ## Compatibility overload for tests and byte-stream callers.
  parseInput(parseKey(ch, getNext), textual)

proc parseInput*(ch: char; input: openArray[char]): InputEvent =
  ## Compatibility overload for tests.
  parseInput(parseKey(ch, input))

when defined(windows):
  proc decodeVirtualKey(virtualKey: int16): InputKey =
    case virtualKey
    of VkHome:
      InputKey(kind: ikHome)
    of VkEnd:
      InputKey(kind: ikEnd)
    of VkUp:
      InputKey(kind: ikUp)
    of VkDown:
      InputKey(kind: ikDown)
    of VkLeft:
      InputKey(kind: ikLeft)
    of VkRight:
      InputKey(kind: ikRight)
    of VkReturn:
      InputKey(kind: ikEnter)
    of VkBack:
      InputKey(kind: ikBackspace)
    of VkTab:
      InputKey(kind: ikTab)
    of VkEscape:
      InputKey(kind: ikEscape)
    else:
      InputKey(kind: ikUnknown)

  proc decodeConsoleChar(ch: char): InputKey =
    let direct = decodeDirectKey(ch)
    if direct.kind != ikUnknown:
      direct
    elif ch in PrintableChars:
      InputKey(kind: ikChar, ch: ch)
    else:
      InputKey(kind: ikUnknown)

  proc decodeConsoleKeyEvent(keyEvent: KEY_EVENT_RECORD): InputKey =
    let ctrlPressed =
      (keyEvent.dwControlKeyState and DWORD(LeftCtrlPressed or RightCtrlPressed)) != 0

    if ctrlPressed and keyEvent.wVirtualKeyCode == VkC:
      return InputKey(kind: ikCtrlC)

    result = decodeVirtualKey(keyEvent.wVirtualKeyCode)
    if result.kind != ikUnknown:
      return
    if keyEvent.uChar != 0:
      return decodeConsoleChar(char(keyEvent.uChar))
    result = InputKey(kind: ikUnknown)

  proc getConsoleKey*(): InputKey =
    ## Reads a Windows console key without losing special-key information.
    let fd = getStdHandle(STD_INPUT_HANDLE)
    var keyEvent = KEY_EVENT_RECORD()
    var numRead: cint
    var oldMode: DWORD
    let hasConsoleMode = getConsoleMode(fd, addr oldMode) != 0

    if hasConsoleMode:
      discard setConsoleMode(fd, oldMode and not DWORD(EnableProcessedInput))

    try:
      while true:
        doAssert(waitForSingleObject(fd, INFINITE) == WAIT_OBJECT_0)
        doAssert(readConsoleInput(fd, addr(keyEvent), 1, addr(numRead)) != 0)

        if numRead == 0 or keyEvent.eventType != KeyEvent or keyEvent.bKeyDown == 0:
          continue

        return decodeConsoleKeyEvent(keyEvent)
    finally:
      if hasConsoleMode:
        discard setConsoleMode(fd, oldMode)
