import std/[unittest, strutils]
import visual

suite "Visual line calculation":
  test "empty string":
    check splitToVisualLines("", 80) == @[""]

  test "text shorter than width":
    check splitToVisualLines("hello", 80) == @["hello"]

  test "text exactly width":
    check splitToVisualLines("x".repeat(80), 80) == @["x".repeat(80)]

  test "text wraps correctly":
    let result = splitToVisualLines("hello world", 5)
    check result == @["hello", " worl", "d"]

  test "calculate total height":
    let lines = @["short", "this is a very long line that will wrap"]
    # - "short" -> 1 line
    # "this is a very long line that will wrap" (39 chars), with width 10:
    # - "this is a " (10) -> 2
    # - "very long " (10) -> 3
    # - "line that " (10) -> 4
    # - "will wrap" (9)   -> 5
    check calculateVisualHeight(lines, 10) == 5

  test "width=1 splits every character":
    let result = splitToVisualLines("abc", 1)
    check result == @["a", "b", "c"]
