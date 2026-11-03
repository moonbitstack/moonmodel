#!/usr/bin/env python3
"""Write `docs/showcase.html` from the tour example's own output.

    python3 scripts/gen_showcase.py

`moon run src/examples/tour` builds one model that uses every `Type` and every
field of `Check`, then prints the four projections of it — the JSON Schema, the
OpenAPI dialects, the SQL, the GraphQL SDL — and a check against an instance.
This script only typesets that output, so the page can never claim something
the library does not do:

    python3 scripts/gen_showcase.py
    git diff --exit-code docs/showcase.html
"""

import html
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

# One line of framing per section the tour prints, keyed by its heading.
INTRO = {
    "the description": "The description answers questions about itself — how many fields, which are required, what it refers to — before any projection runs.",
    "JSON Schema 2020-12": "A model that refers to another writes a `$ref`; the schema is the document's own vocabulary.",
    "one document, references resolved": "Passing `known=` resolves every `$ref` into `$defs`, for a validator that wants a single file.",
    "the three OpenAPI dialects": "Nullable, an open bound and a reference are spelled differently in 3.1, 3.0 and 2.0 — the same description, three ways.",
    "SQL, three dialects": "SQL loses the most, so it returns both halves: the columns it wrote and the fields it could not.",
    "GraphQL SDL": "GraphQL folds required and nullable into one `!`, and has no type for a mapping, a nested model, `Any` or `Raw`.",
    "a document declares its scalars": "The two scalars GraphQL lacks are declared once per document, and both names are parameters.",
    "checking an instance": "The description is what an instance is checked against — held to the very JSON Schema it wrote.",
}


# A short label for the nav; the section keeps its full heading.
SHORT = {
    "the description": "description",
    "JSON Schema 2020-12": "JSON Schema",
    "one document, references resolved": "resolved",
    "the three OpenAPI dialects": "OpenAPI",
    "SQL, three dialects": "SQL",
    "GraphQL SDL": "GraphQL",
    "a document declares its scalars": "scalars",
    "checking an instance": "checking",
}


def slug(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def run_tour() -> str:
    out = subprocess.run(
        ["moon", "run", "src/examples/tour", "--target", "native"],
        cwd=ROOT, capture_output=True, text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit("the tour printed nothing:\n" + out.stdout + out.stderr)
    return out.stdout


def split_sections(text: str):
    head = re.compile(r"^──\s+(.*?)\s+─+\s*$")
    sections, title, body = [], None, []
    for line in text.splitlines():
        m = head.match(line)
        if m:
            if title is not None:
                sections.append((title, "\n".join(body).strip("\n")))
            title, body = m.group(1).strip(), []
        elif title is not None:
            body.append(line)
    if title is not None:
        sections.append((title, "\n".join(body).strip("\n")))
    return sections


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def inline(s: str) -> str:
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", esc(s))


def build() -> str:
    sections = split_sections(run_tour())
    body, nav = [], []
    for title, text in sections:
        sid = slug(title)
        intro = INTRO.get(title, "")
        nav.append(f'<a href="#{sid}">{esc(SHORT.get(title, title))}</a>')
        body.append(
            f'<section class="sec" id="{sid}">'
            f'<h2>{esc(title)}</h2>'
            + (f'<p class="intro">{inline(intro)}</p>' if intro else "")
            + '<div class="code"><button class="copy" type="button" aria-label="copy">COPY</button>'
            + f'<pre>{esc(text)}</pre></div>'
            + "</section>"
        )
    return (TEMPLATE
            .replace("{{NAV}}", "".join(nav))
            .replace("{{SECTIONS}}", "".join(body)))


TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MOONMODEL — showcase</title>
<link rel="stylesheet" href="assets/type.css">
<link rel="stylesheet" href="assets/tokens.css">
<style>
  html,body{margin:0;background:var(--desk);color:var(--ink);}
  body{font-family:'Jost',system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
  .wrap{max-width:1180px;margin:0 auto;padding:56px 40px 120px;}
  .sheet{background:var(--paper);border:1px solid var(--ink);outline:1px solid var(--ink);
         outline-offset:8px;padding:56px 64px;position:relative;box-shadow:0 24px 60px -30px rgba(0,0,0,.55);}
  .sheet::after{content:"";position:absolute;inset:14px;border:1px solid var(--ink);opacity:.25;pointer-events:none;}
  h1{font-family:'Cinzel',serif;font-weight:700;letter-spacing:.16em;font-size:40px;margin:0;}
  .sub{font-family:'EB Garamond',serif;font-style:italic;font-size:20px;opacity:.85;margin:.3em 0 0;}
  .meta{font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.14em;opacity:.6;
         display:flex;gap:22px;margin-top:22px;flex-wrap:wrap;}
  .meta a{color:inherit;}
  nav{margin:26px 0 8px;display:flex;gap:9px;flex-wrap:wrap;}
  nav a{font-family:'IBM Plex Mono',monospace;font-size:10.5px;letter-spacing:.05em;text-decoration:none;
        color:var(--ink);border:1px solid var(--ink);border-radius:14px;padding:5px 12px;opacity:.8;}
  nav a:hover{background:var(--accent);color:var(--paper);border-color:var(--accent);}
  .sec{margin-top:44px;border-top:1px solid var(--ink);padding-top:22px;}
  .sec h2{font-family:'Cinzel',serif;font-size:19px;letter-spacing:.05em;margin:0 0 .25em;}
  .intro{font-size:14px;line-height:1.6;opacity:.85;margin:0 0 12px;max-width:74ch;}
  .intro code{background:rgba(0,0,0,.06);padding:.05em .3em;border-radius:3px;font-size:.92em;}
  .code{position:relative;background:var(--paper-hi);border:1px solid var(--ink);padding-top:38px;}
  .code pre{margin:0;padding:16px 18px;overflow:auto;max-height:520px;
            font-family:'IBM Plex Mono',monospace;font-size:11.5px;line-height:1.55;color:var(--ink);}
  .copy{position:absolute;top:7px;right:8px;font-family:'IBM Plex Mono',monospace;font-size:9px;
        letter-spacing:.12em;padding:5px 10px;border:1px solid var(--ink);background:var(--paper);
        color:var(--ink);cursor:pointer;opacity:.7;}
  .copy:hover{opacity:1;background:var(--accent);color:var(--paper);border-color:var(--accent);}
  .copy.done{background:var(--accent);color:var(--paper);border-color:var(--accent);opacity:1;}
  .foot{margin-top:56px;padding-top:18px;border-top:1px solid var(--ink);
        font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.1em;opacity:.6;
        display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;}
  a{color:var(--accent);}
</style>
</head>
<body>
<div class="wrap"><div class="sheet">
  <header class="doc-head">
  <h1>MOONMODEL</h1>
  <div class="pagerail" role="navigation" aria-label="pages">
    <a href="index.html">sheet</a>
    <a href="guide.html">guide</a>
    <a href="showcase.html" aria-current="page">showcase</a>
    <a href="api.html">api</a>
  </div>
  <p class="sub">Showcase — one description, projected four ways, and checked</p>
  <div class="meta">
    <span>SHOWCASE 03 / 01 · THE OUTPUT</span>
    <span><a href="https://github.com/moonbitstack/moonmodel">github</a></span>
  </div>
  <nav>{{NAV}}</nav>
  </header>
  {{SECTIONS}}
  <div class="foot">
    <span>APACHE-2.0 · MOONBITSTACK/MOONMODEL</span>
    <span>every line above is printed by <code>moon run src/examples/tour</code></span>
  </div>
</div></div>
<script>
  document.querySelectorAll('.copy').forEach(btn => {
    btn.addEventListener('click', () => {
      const pre = btn.parentElement.querySelector('pre');
      const text = pre ? pre.textContent : '';
      const done = () => {
        btn.textContent = 'COPIED';
        btn.classList.add('done');
        setTimeout(() => { btn.textContent = 'COPY'; btn.classList.remove('done'); }, 1200);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, done);
      } else { done(); }
    });
  });
</script>
<script src="assets/ui.js" defer></script>
</body>
</html>
"""


def main():
    DOCS.mkdir(exist_ok=True)
    (DOCS / "showcase.html").write_text(build(), encoding="utf-8", newline="\n")
    print("showcase.html <- the tour's own output")


if __name__ == "__main__":
    main()
