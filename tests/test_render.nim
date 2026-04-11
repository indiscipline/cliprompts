import std/[unittest, strutils]
from std/sequtils import toSeq
import types, state, render, display

suite "Render functions":
  test "selection: focused item has > marker":
    var s = initSelection(@["a", "b", "c"], multi=false)
    s.current = 1
    let lines = renderSelection(s)
    check lines[0].contains("  ( ) a")
    check lines[1].contains("> (*) b")
    check lines[2].contains("  ( ) c")

  test "selection: multi-select shows [x] for selected":
    var s = initSelection(@["a", "b", "c"], multi=true, defaults={1.int16})
    let lines = renderSelection(s)
    check lines[0].contains("  [ ] a")
    check lines[1].contains("> [x] b")
    check lines[2].contains("  [ ] c")

  test "selection: single-select shows (*) for current":
    var s = initSelection(@["a", "b", "c"], multi=false)
    s.current = 0
    let lines = renderSelection(s)
    check lines[0].contains("> (*) a")

  test "selection: render scrolls window when maxShown is smaller":
    var s = initSelection(@["a", "b", "c", "d", "e"], multi=false, maxShown=2)
    s.current = 3
    let lines = renderSelection(s)
    check lines.len == 2
    check lines[0].contains("  ( ) c")
    check lines[1].contains("> (*) d")

  test "search: query line includes cursor placeholder _":
    var s = initSearch(@["a", "b"], initialQuery="test")
    let lines = renderSearch(s)
    check lines[0].contains("Search: test_")

  test "search: filtered list only shows matching items":
    var s = initSearch(@["apple", "banana", "cherry"])
    s.updateQuery("an")
    let lines = renderSearch(s)
    check lines.len == 2 # Query line + 1 option
    check lines[1].contains("banana")

suite "Display helpers":
  test "suggested answers mark the actual registered shortcut":
    let hint = formatSuggestedAnswers([
      SuggestedAnswer(label: "cancel", key: 'c'),
      SuggestedAnswer(label: "cat", key: 'a'),
      SuggestedAnswer(label: "continue", key: 'o')
    ])
    check hint == "[c]ancel/c[a]t/c[o]ntinue"

  test "compact suggested answers uppercase the default shortcut":
    let hint = formatCompactSuggestedAnswers([
      SuggestedAnswer(label: "yes", key: 'y'),
      SuggestedAnswer(label: "no", key: 'n')
    ], defaultKey = 'y')
    check hint == "[Y/n]"

suite "Multiline output":
  test "message: multi-line splits with continuation prefix":
    let msg = "line 1\nline 2\nline 3"
    let lines = formatPrefixed(PromptMsg, msg).toSeq()
    check lines.len == 3
    check lines[0].prefix.endswith $PromptMsg & PrefixSep
    check lines[0].line == "line 1"
    check lines[1].prefix.endswith $ContinuingMsg & PrefixSep
    check lines[1].line == "line 2"
    check lines[2].prefix.endswith $ContinuingMsg & PrefixSep
    check lines[2].line == "line 3"
