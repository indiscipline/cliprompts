# SPDX-License-Identifier: GPL-2.0-or-later

import types, backend, visual, input

type
  FrameState = object
    lastVisualHeight: int

proc runInteractive*[S](
      backend: TerminalBackend;
      initialState: S;
      renderFn: proc(state: var S): seq[string];
      handleFn: proc(state: var S, event: InputEvent): bool;  # true = continue
      textual: static bool = false;
    ): S =
  ## Generic interactive loop with width-aware rendering
  ## Returns final state after user confirms/cancels

  var state = initialState
  var frame = FrameState(lastVisualHeight: 0)

  backend.hideCursor()
  try:
    while true:
      # Render current state
      let logicalLines = renderFn(state)
      let visualLines = wrapLines(logicalLines, backend.width)
      let newHeight = visualLines.len

      # Clear previous frame (width-aware!)
      if frame.lastVisualHeight > 0:
        backend.clearLinesFromCurrent(frame.lastVisualHeight)

      # Draw new frame
      for i, line in visualLines:
        if i < visualLines.high:
          backend.write(line, "\n")
        else:
          backend.write(line)

      # Update frame tracking
      frame.lastVisualHeight = newHeight

      # Get input
      let key = backend.getKey()
      let event = parseInput(key, textual)

      # Handle cancellation
      if event.action == Cancel:
        raise newException(IOError, "User cancelled")

      # Update state - returns false to exit
      if not handleFn(state, event):
        break
  finally:
    if frame.lastVisualHeight > 0:
      backend.clearLinesFromCurrent(frame.lastVisualHeight)
    backend.restoreTerminalState()

  return state
