# SPDX-License-Identifier: GPL-2.0-or-later

import std/strutils
from std/sequtils import foldl
import types

const
  PrefixOffset* = foldl(MsgType, max(a, len($b)), 0) + 1
  PrefixSep* = ": "

func concat*(a: varargs[string]): string {.noinit.} =
  var totalLen = 0
  for i in 0 .. high(a):
    inc(totalLen, a[i].len)
  result = newStringOfCap(totalLen)
  for i in 0 .. high(a):
    result.add(a[i])

proc spaces*(count: int): string =
  repeat(' ', count)

proc formatPrefix*(msgType: MsgType): string =
  let text = $msgType
  concat(spaces(PrefixOffset - text.len), text, PrefixSep)

proc formatPromptWithDefault*[T](question: string, default: T): string =
  let defaultStr = $default
  if defaultStr.len > 0:
    question & " [" & defaultStr & "]"
  else:
    question

proc formatSuggestedAnswer(answer: SuggestedAnswer; defaultKey: char): string =
  let activeKey =
    if answer.key == defaultKey: answer.key.toUpperAscii()
    else: answer.key
  for i, ch in answer.label:
    if ch.toLowerAscii() == answer.key:
      result = answer.label[0 ..< i] & "[" & $activeKey & "]"
      if i < answer.label.high:
        result.add answer.label[i + 1 .. ^1]
      return
  "[" & $activeKey & "]" & answer.label

proc formatSuggestedAnswers*(answers: openArray[SuggestedAnswer]; defaultKey: char = '\0'): string =
  result = ""
  for i, answer in answers:
    if i > 0:
      result.add "/"
    result.add formatSuggestedAnswer(answer, defaultKey)

proc formatCompactSuggestedAnswers*(answers: openArray[SuggestedAnswer]; defaultKey: char = '\0'): string =
  result = "["
  for i, answer in answers:
    if i > 0:
      result.add "/"
    if answer.key == defaultKey:
      result.add answer.key.toUpperAscii()
    else:
      result.add answer.key
  result.add "]"

iterator formatPrefixed*(msgType: MsgType, text: string):
  tuple[prefix: string, line: string] =
  let msgPrefix = formatPrefix(msgType)
  let contPrefix = formatPrefix(ContinuingMsg)
  for i, line in text.splitLines().pairs():
    yield (
      prefix: if i == 0: msgPrefix else: contPrefix,
      line: line
    )
