version       = "0.1.1"
author        = "Kirill I."
description   = "Interactive command line prompts"
license       = "GPL-2.0-or-later"
srcDir        = "."


# Dependencies

requires "nim >= 2.0.0"

import std/[os, strutils]

const
  SRC = "cliprompts.nim"
  URL = "https://github.com/indiscipline/cliprompts"

task updatedocs, "Regenerates `docs/index.html`":
  exec("nim doc --git.commit:main --git.url:$1  --putenv:nimbleversion=$2 -o:docs/index.html $3" % [URL, version, SRC])
