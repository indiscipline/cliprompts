import std/[unittest, times, options]
from std/strutils import contains
import state, types

type SmallInt = range[0..100]

suite "State machines":
  test "selection navigate wraps around":
    var s = initSelection(["a", "b", "c"], multi=false)
    s.move(MoveCmd(kind: mkRelative, delta: 1))
    check s.current == 1
    s.move(MoveCmd(kind: mkRelative, delta: 2))
    check s.current == 0  # 1 + 2 = 3, 3 mod 3 = 0

  test "selection moveHome and moveEnd jump to bounds":
    var s = initSelection(["a", "b", "c", "d"], multi=false)
    s.move(MoveCmd(kind: mkRelative, delta: 2))
    s.move(MoveCmd(kind: mkHome))
    check s.current == 0
    s.move(MoveCmd(kind: mkEnd))
    check s.current == 3

  test "selection toggle multi-select":
    var s = initSelection(["a", "b"], multi=true)
    s.toggle()
    check 0.int16 in s.selected
    s.toggle()
    check 0.int16 notin s.selected

  test "search filtering works":
    let opts = ["apple", "banana", "cherry"]
    var s = initSearch(opts)
    s.updateQuery("an")
    let filtered = s.getFiltered()
    check filtered == @[1] # "banana"

  test "search navigate filtered":
    let opts = ["apple", "apricot", "banana"]
    var s = initSearch(opts)
    s.updateQuery("ap") # matches apple (0) and apricot (1)
    check s.getFiltered() == @[0, 1]
    s.moveFiltered(MoveCmd(kind: mkRelative, delta: 1))
    check s.current == 1
    check s.getSelectedIndex() == 1

  test "search moveFilteredHome and moveFilteredEnd jump within filtered results":
    let opts = ["apple", "apricot", "banana", "application"]
    var s = initSearch(opts)
    s.updateQuery("ap") # matches 0, 1, 3
    s.moveFiltered(MoveCmd(kind: mkEnd))
    check s.current == 2
    check s.getSelectedIndex() == 3
    s.moveFiltered(MoveCmd(kind: mkHome))
    check s.current == 0
    check s.getSelectedIndex() == 0

  test "selection: single-select ignores toggle":
    var s = initSelection(["a", "b", "c"], multi=false)
    check s.selected == {}
    s.toggle()
    check s.selected == {}  # toggle is a no-op in single-select

  test "search: empty query returns all items":
    var s = initSearch(["a", "b", "c", "d", "e"], maxShown=3)
    check s.getFiltered() == @[0, 1, 2, 3, 4]
    check s.getVisibleFiltered() == @[0, 1, 2]

  test "search: navigate scrolls visible window":
    var s = initSearch(["a", "b", "c", "d", "e"], maxShown=2)
    s.moveFiltered(MoveCmd(kind: mkRelative, delta: 3)) # move to index 3
    check s.getVisibleFiltered() == @[2, 3]

  test "search: backspace updates filtered results":
    var s = initSearch(["apple", "apricot", "banana"])
    s.updateQuery("ap")
    check s.getFiltered() == @[0, 1]      # only apple, apricot match
    s.backspace()                          # query is now "a"
    check s.getFiltered() == @[0, 1, 2]   # all three contain "a"
    check s.current == 0                   # backspace resets current

suite "Suggested answers":
  test "registerSuggestedAnswers uses next free character on collision":
    let answers = registerSuggestedAnswers(["cancel", "cat", "continue"])
    check answers[0].key == 'c'
    check answers[1].key == 'a'
    check answers[2].key == 'o'

  test "validateSuggested matches case-insensitively":
    let answers = registerSuggestedAnswers(["yes", "no"])
    let res = validateSuggested("Y", answers)
    check res.ok
    check res.value == 'y'

  test "validateSuggested returns default on empty input":
    let answers = registerSuggestedAnswers(["yes", "no"])
    let res = validateSuggested("", answers, some('n'))
    check res.ok
    check res.value == 'n'

proc validate*[T: range | SomeNumber](input: string, default: T): ValidationResult[T] =
  validate(input, some(default))
suite "Validation State":

  test "updateInput appends char; error stays":
    var state = initValidation("Prompt", some(0))
    let e = "Some error"
    state.lastValidationResult = ValidationResult[int](kind: vrErr, error: e)
    state.updateInput('a')
    check state.input == "a"
    check state.lastValidationResult.error == e

suite "Number validation":
  test "validate returns default on empty input":
    let res = validate[int]("", 42)
    check res.ok == true
    check res.value == 42

  test "valid int returns parsed value":
    let res = validate("42", 0)
    check res.ok == true
    check res.value == 42

  test "non-numeric input returns error":
    let res = validate("abc", 0)
    check res.ok == false
    check res.error.len > 0   # some Nim's parseInt error message

  test "out-of-range int returns range error with bounds":
    let res = validate[range[0..10]]("15", 5)
    check not res.ok
    check res.error.contains("Valid range")
    check res.error.contains("0..10")

  test "validate respects ranges":
    let res = validate[range[0..10]]("5", 5)
    check res.ok

  test "int at exact low boundary accepted":
    let res = validate[SmallInt]("0", 50)
    check res.ok == true
    check res.value == 0

  test "int at exact high boundary accepted":
    let res = validate[SmallInt]("100", 50)
    check res.ok == true
    check res.value == 100

  test "int one below low boundary rejected":
    let res = validate[SmallInt]("-1", 50)
    check res.ok == false
    check res.error.contains("0..100")

  test "int one above high boundary rejected":
    let res = validate[SmallInt]("101", 50)
    check res.ok == false
    check res.error.contains("0..100")

  test "valid float parses correctly":
    let res = validate("3.14", 0.0)
    check res.ok == true
    check res.value == 3.14

  test "float empty input returns default":
    let res = validate("", 2.5)
    check res.ok == true
    check res.value == 2.5

  test "float non-numeric input returns error":
    let res = validate[float]("xyz", 0.0)
    check res.ok == false
    check res.error.len > 0


suite "Date validation":
  let dateFormat = initTimeFormat("yyyy-MM-dd")
  test "valid date string parses":
    let res = validateDate("2024-06-15", dateFormat, none(DateTime))
    check res.ok == true
    check res.value == parse("2024-06-15", dateFormat)

  test "invalid date string returns error":
    let res = validateDate("not-a-date", dateFormat, none(DateTime))
    check res.ok == false
    check res.error.len > 0

  test "empty input with default returns default":
    let date = parse("2024-01-01", dateFormat)
    let res = validateDate("", dateFormat, some(date))
    check res.ok == true
    check res.value == date

  test "empty input without default returns error":
    let res = validateDate("", dateFormat, none(DateTime))
    check res.ok == false
    check res.error == "No input and no default provided."
