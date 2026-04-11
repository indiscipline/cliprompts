# SPDX-License-Identifier: GPL-2.0-or-later

proc splitToVisualLines*(text: string, width: Positive): seq[string] =
  ## Splits text into chunks that fit terminal width
  ## Returns at least one line (empty if text is empty)
  result = @[]
  if text.len == 0:
    result.add("")
    return

  var pos = 0
  while pos < text.len:
    let chunkSize = min(text.len - pos, width)
    result.add(text[pos ..< pos + chunkSize])
    pos += chunkSize

proc calculateVisualHeight*(lines: seq[string], width: Positive): int =
  ## Returns total terminal rows needed for logical lines
  result = 0
  for line in lines:
    result += splitToVisualLines(line, width).len

proc wrapLines*(lines: seq[string], width: Positive): seq[string] =
  ## Converts logical lines to visual lines (for rendering)
  result = @[]
  for line in lines:
    for visualLine in splitToVisualLines(line, width):
      result.add(visualLine)
