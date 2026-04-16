# SPDX-License-Identifier: GPL-2.0-or-later

## Performance metrics for cliprompts
## Compile with -d:debugMetrics to enable tracking

const MetricsEnabled* = defined(debugMetrics)

when MetricsEnabled:
  import std/[times, monotimes, strformat]
  from strutils import formatFloat, FloatFormatMode
  type
    Metrics* = object
      writeCount*: int
      writeStyledCount*: int
      clearLinesCount*: int
      totalLinesCleared*: int
      getCharCount*: int
      renderCalls*: int
      totalRenderTime*: float  # milliseconds

  var globalMetrics* = Metrics()

  proc reset*() =
    ## Reset all metrics to zero
    globalMetrics = Metrics()

  proc report*(): string =
    ## Generate a human-readable metrics report
    let renderTime = if globalMetrics.renderCalls > 0:
        (globalMetrics.totalRenderTime / globalMetrics.renderCalls.float).formatFloat(ffDecimal, 3)
      else: "0.000"
    result = fmt"""
Performance Metrics:
  Terminal Operations:
    - write() calls:       {$globalMetrics.writeCount}
    - writeStyled() calls: {globalMetrics.writeStyledCount}
    - clearLines() calls:  {globalMetrics.clearLinesCount}
    - total lines cleared: {globalMetrics.totalLinesCleared}
    - getChar() calls:     {globalMetrics.getCharCount}

  Rendering:
    - render() calls:      {globalMetrics.renderCalls}
    - total render time:   {globalMetrics.totalRenderTime:.3f} ms
    - avg render time:     {renderTime} ms
"""

else:
  # Disabled - provide no-op procs
  template reset*() = discard
  template report*(): string = ""

template trackWrite*(body: untyped) =
  ## Wraps a write operation to count it
  when MetricsEnabled:
    globalMetrics.writeCount.inc
  body

template trackWriteStyled*(body: untyped) =
  ## Wraps a writeStyled operation to count it
  when MetricsEnabled:
    globalMetrics.writeStyledCount.inc
  body

template trackClearLines*(n: int, body: untyped) =
  ## Wraps a clearLines operation to count it
  when MetricsEnabled:
    globalMetrics.clearLinesCount.inc
    globalMetrics.totalLinesCleared += n
  body

# Note: For getChar, just use `when MetricsEnabled: globalMetrics.getCharCount.inc`
# directly in the proc, since it needs to return a value

template trackRender*(body: untyped): untyped =
  ## Wraps a render function to time it
  when MetricsEnabled:
    let startTime = getMonoTime()
    body
    let endTime = getMonoTime()
    globalMetrics.renderCalls.inc
    globalMetrics.totalRenderTime += (endTime - startTime).inNanoseconds.float / 1_000_000.0
  else:
    body

when MetricsEnabled:
  template countAlloc*(T: typedesc, size: int): int =
    ## Returns estimated bytes for allocation
    ## Usage: let bytes = countAlloc(string, myStr.len)
    when T is string:
      size
    elif T is seq:
      size * sizeof(T.X)  # X is element type
    else:
      sizeof(T)

  proc estimateStringAlloc*(s: string): int {.inline.} =
    ## Estimate allocation size for a string
    if s.len > 0: s.len else: 0

  proc estimateSeqAlloc*[T](s: seq[T]): int {.inline.} =
    ## Estimate allocation size for a seq
    s.len * sizeof(T)

else:
  template countAlloc*(T: typedesc, size: int): int = 0
  template estimateStringAlloc*(s: string): int = 0
  template estimateSeqAlloc*[T](s: seq[T]): int = 0
