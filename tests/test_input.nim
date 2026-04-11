import std/unittest
import types, input

suite "Input parsing":

  test "Enter produces Confirm":
    let event = parseInput('\r', ['\r'])
    check event.action == Confirm

  test "Ctrl+C produces Cancel":
    let event = parseInput('\3', ['\3'])
    check event.action == Cancel

  test "Space produces Select":
    let event = parseInput(' ', [' '])
    check event.action == Select

  test "Tab produces Navigate (+1)":
    let event = parseInput('\t', ['\t'])
    check event.action == Move
    check event.move.kind == mkRelative
    check event.move.delta == 1

  test "ESC [ A sequence produces Navigate (-1)":
    let event = parseInput('\27', ['[', 'A'])
    check event.action == Move
    check event.move.kind == mkRelative
    check event.move.delta == -1

  test "ESC [ B sequence produces Navigate (+1)":
    let event = parseInput('\27', ['[', 'B'])
    check event.action == Move
    check event.move.kind == mkRelative
    check event.move.delta == 1

  test "ESC [ H sequence produces MoveHome":
    let event = parseInput('\27', ['[', 'H'])
    check event.action == Move
    check event.move.kind == mkHome

  test "ESC [ F sequence produces MoveEnd":
    let event = parseInput('\27', ['[', 'F'])
    check event.action == Move
    check event.move.kind == mkEnd

  test "ESC O H sequence produces MoveHome":
    let event = parseInput('\27', ['O', 'H'])
    check event.action == Move
    check event.move.kind == mkHome

  test "ESC O F sequence produces MoveEnd":
    let event = parseInput('\27', ['O', 'F'])
    check event.action == Move
    check event.move.kind == mkEnd

  test "ESC [ 1 ~ sequence produces MoveHome":
    let event = parseInput('\27', ['[', '1', '~'])
    check event.action == Move
    check event.move.kind == mkHome

  test "ESC [ 4 ~ sequence produces MoveEnd":
    let event = parseInput('\27', ['[', '4', '~'])
    check event.action == Move
    check event.move.kind == mkEnd

  test "legacy Windows G sequence produces MoveHome":
    let event = parseInput('\27', ['\0', 'G'])
    check event.action == Move
    check event.move.kind == mkHome

  test "legacy Windows O sequence produces MoveEnd":
    let event = parseInput('\27', ['\xE0', 'O'])
    check event.action == Move
    check event.move.kind == mkEnd

  test "ESC ESC produces Cancel":
    let event = parseInput('\27', ['\27'])
    check event.action == Cancel

  test "printable char produces TypeChar":
    let event = parseInput('a', ['a'])
    check event.action == TypeChar
    check event.ch == 'a'

  test "null char produces NoOp":
    let event = parseInput('\0', ['\0'])
    check event.action == NoOp

  test "parseKey converts ESC [ B to ikDown":
    let key = parseKey('\27', ['[', 'B'])
    check key == InputKey(kind: ikDown)

  test "parseKey converts ESC [ H to ikHome":
    let key = parseKey('\27', ['[', 'H'])
    check key == InputKey(kind: ikHome)

  test "parseKey converts ESC [ F to ikEnd":
    let key = parseKey('\27', ['[', 'F'])
    check key == InputKey(kind: ikEnd)

  test "parseInput maps ikEscape to Cancel":
    let event = parseInput(InputKey(kind: ikEscape))
    check event.action == Cancel

  test "parseInput maps ikHome to MoveHome":
    let event = parseInput(InputKey(kind: ikHome))
    check event.action == Move
    check event.move.kind == mkHome

  test "parseInput maps ikEnd to MoveEnd":
    let event = parseInput(InputKey(kind: ikEnd))
    check event.action == Move
    check event.move.kind == mkEnd
