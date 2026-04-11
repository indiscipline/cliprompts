import std/unittest
import cliprompts, backend

# ---------------------------------------------------------------------------
# Concrete enum for all tests in this file
# ---------------------------------------------------------------------------
type Color* = enum Red, Green, Blue

# ---------------------------------------------------------------------------
# promptEnum end-to-end
# ---------------------------------------------------------------------------
# These tests exercise the enum-to-index mapping layer that does not exist
# yet.  They are expected to fail to compile until promptEnum / promptEnumSet
# are added to prompts.nim and core.nim.
#
# Input sequences (all go through promptSelection under the hood):
#   single select, pick Green:  Down + Enter               -> "\27[B\r"
#   multi select, pick {Red, Green}: Space, Down, Space, Enter -> " \27[B \r"
#   sortAlpha single, pick first (alphabetically Blue): Enter  -> "\r"
#     Alphabetical order of Color: Blue < Green < Red
# ---------------------------------------------------------------------------

suite "promptEnum via MockTerminal":
  test "single select returns correct enum value":
    let mock = newMockTerminal(width=80)
    setBackend(mock)
    mock.queueInput("\27[B\r")          # Down arrow + Enter -> index 1 = Green
    let result = promptEnum[Color]("Pick a colour")
    check result == Green

  test "multi select returns correct enum set":
    let mock = newMockTerminal(width=80)
    setBackend(mock)
    mock.queueInput(" \27[B \r")        # Space (select Red), Down, Space (select Green), Enter
    let result = promptEnumSet[Color]("Pick colours")
    check Red in result
    check Green in result
    check Blue notin result

  test "sortAlpha reorders options alphabetically":
    let mock = newMockTerminal(width=80)
    setBackend(mock)
    # Alphabetical order: Blue(0), Green(1), Red(2).  Enter on first -> Blue.
    mock.queueInput("\r")
    let result = promptEnum[Color]("Pick", sortAlpha = true, default = Blue)
    check result == Blue

  test "subset promptEnum falls back when default is outside options":
    let mock = newMockTerminal(width=80)
    setBackend(mock)
    mock.queueInput("\r")
    let result = promptEnum[Color]("Pick accent", {Green, Blue})
    check result in {Green, Blue}
