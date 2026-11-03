#!/usr/bin/env python3
"""Write the front page from the library's own dump.

    python3 scripts/gen_sheet.py

The page in `scripts/template/` knows no field: it reads the JSON that
`moon run src/cmd/sheet` prints. Add a field to the model and every count,
column and width follows on the next build. CI runs this and compares the
result with what is committed, which is what keeps the page honest:

    python3 scripts/gen_sheet.py
    git diff --exit-code docs/index.html docs/sheet.json

`docs/sheet.json` is kept beside the page so a reader can fetch the same
description the page was typeset from.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "scripts" / "template"
DOCS = ROOT / "docs"


def sheet() -> str:
    out = subprocess.run(
        ["moon", "run", "src/cmd/sheet", "--target", "native"],
        cwd=ROOT, capture_output=True, text=True,
    )
    text = out.stdout
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < 0:
        sys.exit("the generator printed no JSON:\n" + out.stdout + out.stderr)
    body = text[start:end + 1]
    json.loads(body)                      # a broken sheet should stop the build
    return body


def render(name: str, body: str | None = None) -> str:
    page = (TEMPLATE / name).read_text(encoding="utf-8")
    if body is not None:
        page = page.replace("/*__DATA__*/ null", body)
    return page


def main():
    body = sheet()
    DOCS.mkdir(exist_ok=True)
    (DOCS / "sheet.json").write_text(body + "\n", encoding="utf-8", newline="\n")
    (DOCS / "index.html").write_text(render("sheet.html", body),
                                      encoding="utf-8", newline="\n")
    (DOCS / "404.html").write_text(render("hole.html"),
                                    encoding="utf-8", newline="\n")

    model = json.loads(body)
    print(f"{model['stat']['fields']} fields, {len(model['notes'])} notes "
          f"-> docs/index.html, docs/404.html, docs/sheet.json")


if __name__ == "__main__":
    main()
