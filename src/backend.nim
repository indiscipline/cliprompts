# SPDX-License-Identifier: GPL-2.0-or-later

import std/[terminal, os]
from std/strutils import splitLines
import metrics, types, display, input

const TerminalWidthFallback* = 80

# STYLING

const StyleMap: array[MsgType, tuple[fg: ForegroundColor, style: set[Style]]] = [
  SuccessMsg: (fgGreen, {styleBright}),
  ErrorMsg:   (fgRed, {styleBright}),
  PromptMsg:  (fgYellow, {styleBright}),
  AnswerMsg:  (fgYellow, {}),
  HintMsg:    (fgWhite, {styleDim}),
  InfoMsg:    (fgCyan, {}),
  ItemMsg:    (fgWhite, {}),
  AddedMsg:   (fgWhite, {styleDim}),
  ContinuingMsg: (fgWhite, {styleDim}),
]

# TERMINAL BACKEND TYPES

type
  TerminalBackendKind* = enum
    tkReal, tkMock

  TerminalBackend* = ref object
    width*: int
    showColor*: bool
    case kind*: TerminalBackendKind
    of tkReal:
      fd*: File
    of tkMock:
      lines*: seq[string] = @[""]
      inputQueue*: string = ""
      newline: bool = false

# BACKEND OPERATIONS

proc write*(t: TerminalBackend; text: string) =
  trackWrite:
    case t.kind
    of tkReal:
      t.fd.write(text)
      t.fd.flushFile()
    of tkMock:
      if t.newline or t.lines.len == 0:
        t.lines.add ""; t.newline = false
      var i = 0
      var lastEmpty = false
      for line in text.splitLines():
        lastEmpty = (line.len == 0)
        if i == 0:
          t.lines[^1].add line
        else:
          t.lines.add line
        i.inc()
      t.newline = (i > 1 and lastEmpty)
      if t.newline and t.lines.len > 0:
        t.lines.shrink(t.lines.len - 1)

proc write*(t: TerminalBackend; args: varargs[string]) =
  case t.kind
  of tkReal:
    for str in args:
      t.fd.write(str)
    t.fd.flushFile()
  of tkMock:
    let text: string = args.concat()
    t.write(text)

proc writeStyled*(t: TerminalBackend; text: string, fg: ForegroundColor,
                 style: set[Style]) =
  trackWriteStyled:
    case t.kind
    of tkReal:
      t.fd.styledWrite(fg, style, text)
      resetAttributes(t.fd)
      t.fd.flushFile()
    of tkMock:
      # Ignore styling in tests
      t.write(text)

proc clearLines*(t: TerminalBackend; n: int) =
  trackClearLines(n):
    case t.kind
    of tkReal:
      for _ in 0..<n:
        cursorUp(t.fd)
        setCursorXPos(t.fd, 0)
        eraseLine(t.fd)
    of tkMock:
      let toClear = min(t.lines.len, n)
      t.lines.setLen(t.lines.len - toClear)
      if toClear > 0:
        t.newline = true

proc clearLinesFromCurrent*(t: TerminalBackend; n: int) =
  ## Clears N lines assuming the cursor is on the last rendered line.
  trackClearLines(n):
    case t.kind
    of tkReal:
      if n <= 0: return
      setCursorXPos(t.fd, 0)
      eraseLine(t.fd)
      for _ in 1..<n:
        cursorUp(t.fd)
        setCursorXPos(t.fd, 0)
        eraseLine(t.fd)
    of tkMock:
      let toClear = min(t.lines.len, n)
      if toClear == 0: return
      t.lines.setLen(t.lines.len - toClear)
      t.newline = true

proc getKey*(t: TerminalBackend): InputKey =
  when MetricsEnabled:
    globalMetrics.getCharCount.inc

  case t.kind
  of tkReal:
    when defined(windows):
      result = getConsoleKey()
    else:
      let ch = getch()
      result = parseKey(ch, proc(): char = getch())
  of tkMock:
    if t.inputQueue.len > 0:
      let ch = t.inputQueue[^1]
      t.inputQueue.setLen(t.inputQueue.len - 1)
      result = parseKey(ch, proc(): char =
        if t.inputQueue.len == 0:
          raise newException(EOFError, "MockTerminal input queue exhausted")
        let next = t.inputQueue[^1]
        t.inputQueue.setLen(t.inputQueue.len - 1)
        next)
    else:
      raise newException(EOFError, "MockTerminal input queue exhausted")

proc hideCursor*(t: TerminalBackend) =
  if t.kind == tkReal:
    hideCursor(t.fd)

proc showCursor*(t: TerminalBackend) =
  if t.kind == tkReal:
    showCursor(t.fd)

proc restoreTerminalState*(t: TerminalBackend) =
  ## Restores visible terminal state after an interactive prompt exits.
  if t.kind == tkReal:
    resetAttributes(t.fd)
    showCursor(t.fd)
    t.fd.flushFile()

proc showStyled*(backend: TerminalBackend, msgType: MsgType, text: string) =
  for (prefix, line) in formatPrefixed(msgType, text):
    if backend.kind == tkReal and backend.showColor:
      backend.writeStyled(prefix, StyleMap[msgType].fg, StyleMap[msgType].style)
    else:
      backend.write(prefix)
    backend.write(line, "\n")

# CONSTRUCTORS

proc newRealTerminal*(fd: File = stderr; showColor: bool = true): TerminalBackend =
  let w = try: terminalWidth()
          except: TerminalWidthFallback
  let showColor = showColor and not (existsEnv("NO_COLOR") and getEnv("NO_COLOR").len > 0)
  TerminalBackend(kind: tkReal, fd: fd, width: w, showColor: showColor)

proc newMockTerminal*(width: int = TerminalWidthFallback; showColor: bool = false): TerminalBackend =
  TerminalBackend(kind: tkMock, width: width, showColor: showColor, lines: @[""], newline: false, inputQueue: "")

proc queueInput*(t: TerminalBackend; chars: string) =
  case t.kind
  of tkReal: raise newException(Defect, "queueInput only works with MockTerminal")
  of tkMock:
    for c in countDown(chars.high, 0):
      t.inputQueue.add chars[c]
