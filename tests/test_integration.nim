import std/[unittest, times]
from std/strutils import contains, endsWith
import cliprompts, backend, types
from display import PrefixSep

suite "End-to-end prompts":
  const strings = ["foo", "bar", "baz"]
  setup:
    let mock = newMockTerminal(width=80)
    cliprompts.setBackend(mock)

  test "selection with arrow and enter":
    mock.queueInput("\27[B\r")  # Down arrow + Enter
    let result = promptSelection("Choose", strings, multi=false)
    check 1.int16 in result  # Selected second option
    check mock.lines.len > 0  # Something was rendered

  test "search with typing":
    mock.queueInput("ba\r")  # Type "ba" + Enter
    let idx = promptSearch("Search", strings, maxShown=5)
    check idx == 1  # "bar" is first match

  test "search ignores enter when no matches":
    # "x" (no match), Enter (ignored), Backspace, "ba" (match), Enter
    mock.queueInput("x\r\bba\r")
    let idx = promptSearch("Search", strings, maxShown=5)
    check idx == 1

  test "search allowAny accepts enter with no matches":
    mock.queueInput("x\r")
    var query = ""
    let idx = promptSearchMut("Search", strings, query, maxShown=5, allowAny=true)
    check idx == -1
    check query == "x"

  test "search cancel clears interactive frame and hint":
    mock.queueInput("\3")
    expect IOError:
      discard promptSearch("Search", strings, maxShown=5)
    check mock.lines.len == 1
    check mock.lines[0].contains("Search")

suite "Input prompts via MockTerminal":
  # lines layout: [PromptPrefix, PromptText, AnswerPrefix, AnswerText]
  setup:
    let mock = newMockTerminal(width=80)
    cliprompts.setBackend(mock)

  test "promptString displays and returns default on empty enter":
    mock.queueInput("\r")
    let res = promptString("Name", "Guest")
    check res == "Guest"
    # Verify render: Prompt [Default]\nAnswer
    check mock.lines.len == 2
    check mock.lines[^2].contains("Name [Guest]")
    check mock.lines[^1].contains("Guest")

  test "promptString accepts typed input":
    mock.queueInput("Bob\r")
    let res = promptString("Name", "Anon")
    check res == "Bob"
    check mock.lines[^1].contains("Bob")

  test "promptBool accepts y/n case-insensitively":
    mock.queueInput("Y\r")
    let res = promptBool("Continue?", default = false)
    check res == true

  test "promptBool accepts Enter as default":
    mock.queueInput("\r")
    let res = promptBool("Continue?", default = false)
    check res == false

  test "promptBool rejects empty input without default and reprompts":
    mock.queueInput("\ry\r")
    let res = promptBool("Continue?")
    check res == true

  test "promptBool cancel raises IOError":
    mock.queueInput("\27\27")
    expect IOError:
      discard promptBool("Continue?", default = true)
    check mock.lines.len == 1
    check mock.lines[0].contains("Continue?")

  test "promptNumber accepts valid int":
    mock.queueInput("123\r")
    let res = promptNumber("Age", 0)
    check res == 123

  test "promptNumber loops on invalid input":
    # Queue: "abc" (enter) -> fails, "42" (enter) -> succeeds
    mock.queueInput("abc\r42\r")
    let res = promptNumber("Age", 0)
    check res == 42

  test "promptStrings collects items":
    # "one" (enter), "two" (enter), "" (enter)
    mock.queueInput("one\rtwo\r\r")
    let res = promptStrings("List")
    check res == @["one", "two"]
    # Verify output contains the list
    check mock.lines[^1].contains("[one, two]")

  test "promptStrings displays defaults":
    # Empty input -> defaults
    mock.queueInput("\r")
    let res = promptStrings("Tags", @["nim", "lang"])
    check res == @["nim", "lang"]
    check mock.lines[^2].contains("Tags [nim, lang]")

  test "promptDate accepts valid date":
    let f = initTimeFormat("yyyy-MM-dd")
    mock.queueInput("1964-11-09\r")
    let dt = promptDate("Date", f)
    check dt.year == 1964
    check dt.month == mNov
    check dt.monthday == 09

suite "displayMessageLine via MockTerminal":
  setup:
    let mock = newMockTerminal(width=80)
    cliprompts.setBackend(mock)

  test "single-line message writes prefix then text":
    displayMessageLine(SuccessMsg, "all good")
    # lines[0] = prefix & "all good\n"
    check mock.lines.len == 1
    check mock.lines[0].endsWith $SuccessMsg & PrefixSep & "all good"

  test "empty message writes prefix":
    displayMessageLine(HintMsg, "")
    check mock.lines.len == 1
    check mock.lines[0].contains $HintMsg

  test "multi-line message uses continuation prefix on lines 2+":
    displayMessageLine(PromptMsg, "first\nsecond\nthird")
    check mock.lines.len == 3
    check mock.lines[0].endswith $PromptMsg & PrefixSep & "first"
    check mock.lines[1].endswith $ContinuingMsg & PrefixSep & "second"
    check mock.lines[2].endswith $ContinuingMsg & PrefixSep & "third"

suite "Multiline showStyled":
  setup:
    let mock = newMockTerminal(width=80)
    cliprompts.setBackend(mock)

  test "message: multi-line splits with continuation prefix":
    mock.showStyled(PromptMsg, "line 1\nline 2\nline 3")
    check mock.lines.len == 3
    check mock.lines[0].endswith $PromptMsg & PrefixSep & "line 1"
    check mock.lines[1].endswith $ContinuingMsg & PrefixSep & "line 2"
    check mock.lines[2].endswith $ContinuingMsg & PrefixSep & "line 3"

# ---------------------------------------------------------------------------
# success / error write the right MsgType prefix
# ---------------------------------------------------------------------------

suite "success and error write correct prefix":
  setup:
    let mock = newMockTerminal(width=80)
    cliprompts.setBackend(mock)

  test "success writes SuccessMsg prefix":
    success("it worked")
    check mock.lines[0].endswith $SuccessMsg & PrefixSep & "it worked"

  test "error writes ErrorMsg prefix":
    error("something broke")
    check mock.lines[0].endswith $ErrorMsg & PrefixSep & "something broke"
