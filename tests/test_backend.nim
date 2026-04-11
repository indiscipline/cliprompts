import std/unittest
import backend, types

suite "Backend abstraction":
  test "mock records writes correctly":
    let mock = newMockTerminal()
    mock.write("hello")
    mock.write(" world")
    check mock.lines == @["hello world"]

  test "mock clearLines removes correct number":
    let mock = newMockTerminal()
    mock.write("line 1\n")
    mock.write("line 2\n")
    mock.write("line 3\n")
    mock.clearLines(2)
    check mock.lines == @["line 1"]

  test "mock input queue works":
    let mock = newMockTerminal()
    mock.queueInput("abc")
    check mock.getKey() == InputKey(kind: ikChar, ch: 'a')
    check mock.getKey() == InputKey(kind: ikChar, ch: 'b')
    check mock.getKey() == InputKey(kind: ikChar, ch: 'c')
    expect(EOFError):
      discard mock.getKey()

  test "mock parses arrow escape sequences into typed keys":
    let mock = newMockTerminal()
    mock.queueInput("\27[B")
    check mock.getKey() == InputKey(kind: ikDown)
