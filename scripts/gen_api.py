#!/usr/bin/env python3
"""Write `docs/api.html` from the packages' interfaces and their doc comments.

The interface of a MoonBit package is `pkg.generated.mbti`, which `moon info`
writes from the source; the prose is the `///` block above each declaration.
This script joins the two: every public type, variant, field, method and value,
grouped by package, each with the sentences its author wrote about it.

Methods that `derive` writes have no prose of their own — there is nothing to
say about `not_equal` that `Eq` has not said — so a type names the traits it
carries in one line instead of listing generated functions.

It refuses to publish a page with a hole in it: a public type or value with no
doc comment is a bug in the source, so the script names the item and exits
non-zero. CI runs it and compares the result with what is committed:

    python3 scripts/gen_api.py
    git diff --exit-code docs/api.html

Run it after `moon fmt`: the code inside doc comments is copied word for word.
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DOCS = ROOT / "docs"

# The order the guide reads in: the description itself, then the projections,
# then the thing that checks an instance against what they wrote.
PKGS = [
    ("moonmodel", "src", "the description itself — Model, Field, Check, Type; no dependencies"),
    ("moonmodel/json", "src/json", "JSON Schema 2020-12"),
    ("moonmodel/open", "src/open", "an OpenAPI Schema Object, three dialects"),
    ("moonmodel/sql", "src/sql", "columns and CREATE TABLE, three dialects"),
    ("moonmodel/sdl", "src/sdl", "GraphQL SDL"),
    ("moonmodel/verify", "src/verify", "a verdict on an instance"),
]

# The methods a derive writes; a type names its traits instead of listing them.
GENERATED = {"equal", "not_equal", "to_repr", "to_string", "compare", "hash"}


# --- the doc comments -------------------------------------------------------

def harvest_docs():
    """Every `///` block in the package sources, keyed by the declaration it
    sits above: `Type` for a type, `Type::method` for a method, `Type::Variant`
    for an enum variant."""
    docs = {}
    for path in sorted(SRC.rglob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        buf, current = [], None
        for raw in lines:
            s = raw.strip()
            if s.startswith("///"):
                body = s[3:]
                if body.startswith("|"):
                    body = body[1:]
                if body.startswith(" "):
                    body = body[1:]
                buf.append(body.rstrip())
                continue
            if not s:
                continue                       # a blank line may sit inside a block
            if s.startswith("#"):
                continue                       # `#derive(...)` sits between the doc and the decl
            if buf:
                key = decl_key(s, current)
                text = "\n".join(buf).strip()
                if key and text and key not in docs:
                    docs[key] = text
                buf = []
            current = type_of(s) or current
    return docs


def type_of(line):
    m = re.match(r"pub(?:\(all\))? (?:struct|enum|suberror) (\w+)", line)
    return m.group(1) if m else None


def decl_key(line, current):
    m = re.match(r"pub fn (\w+)::(\w+)", line)
    if m:
        return f"{m.group(1)}::{m.group(2)}"
    m = re.match(r"pub fn (\w+)", line)
    if m:
        return m.group(1)
    m = re.match(r"pub let (\w+)", line)
    if m:
        return m.group(1)
    m = re.match(r"pub(?:\(all\))? (?:struct|enum|suberror) (\w+)", line)
    if m:
        return m.group(1)
    m = re.match(r"pub typealias (\w+)", line)
    if m:
        return m.group(1)
    # an enum variant or a struct field: an indented name under a type
    if current:
        m = re.match(r"([A-Z]\w*)(?:\(|\s|$)", line)
        if m:
            return f"{current}::{m.group(1)}"
    return None


# --- the interfaces ---------------------------------------------------------

def parse(text):
    """Split a `.mbti` into values, types (with members and methods) and aliases."""
    values, types, aliases = [], [], []
    section = "Values"
    lines = text.splitlines()
    derive, i = [], 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("// "):
            head = s[3:]
            section = {"Values": "Values", "Errors": "Errors",
                       "Types and methods": "Types",
                       "Type aliases": "Aliases", "Traits": "Traits"}.get(head, section)
            i += 1
            continue
        if s.startswith("#derive("):
            derive = [t.strip() for t in s[s.index("(") + 1:s.rindex(")")].split(",") if t.strip()]
            i += 1
            continue
        m = re.match(r"pub(?:\(all\))? (struct|enum|suberror) (\w+)", s)
        if m:
            kind, name = m.group(1), m.group(2)
            members = []
            i += 1
            while i < len(lines) and lines[i].strip() != "}":
                line = lines[i].strip()
                if line:
                    vm = re.match(r"(\w+)", line)
                    members.append((vm.group(1) if vm else line, line))
                i += 1
            i += 1
            types.append({"kind": kind, "name": name, "members": members,
                          "derive": derive, "methods": [], "section": section})
            derive = []
            continue
        m = re.match(r"pub fn (\w+)::(\w+)\((.*)\)\s*(?:->\s*(.+?))?$", s)
        if m:
            owner = m.group(1)
            for t in types:
                if t["name"] == owner:
                    t["methods"].append({"name": m.group(2), "sig": sig(s),
                                         "raw": s})
                    break
            derive = []
            i += 1
            continue
        m = re.match(r"pub fn (\w+)\(", s)
        if m:
            values.append({"name": m.group(1), "sig": sig(s), "raw": s})
            derive = []
            i += 1
            continue
        m = re.match(r"pub let (\w+)\b", s)
        if m:
            values.append({"name": m.group(1), "sig": s[8:], "raw": s})
            derive = []
            i += 1
            continue
        m = re.match(r"pub typealias (\w+)\s*=\s*(.+)", s)
        if m:
            aliases.append({"name": m.group(1), "to": m.group(2).strip()})
            i += 1
            continue
        i += 1
    return values, types, aliases


def sig(line):
    """A declaration without its `pub`, ready to print as one line of code."""
    return line[4:] if line.startswith("pub ") else line


# --- the page ---------------------------------------------------------------

def esc(s):
    return html.escape(s, quote=False)


def para(text):
    """Doc prose as paragraphs, with `code` spans and line breaks kept."""
    out = []
    for block in text.split("\n\n"):
        block = block.strip()
        if not block:
            continue
        block = esc(block)
        block = re.sub(r"`([^`]+)`", r"<code>\1</code>", block)
        block = block.replace("\n", "<br>")
        out.append(f"<p>{block}</p>")
    return "".join(out)


def type_html(t, docs):
    doc = docs.get(t["name"])
    head = f'<h3 id="{esc(t["name"])}">{esc(t["name"])} <span class="kind">{t["kind"]}</span></h3>'
    traits = ""
    if t["derive"]:
        names = [re.sub(r"^@[\w]+\.", "", d) for d in t["derive"]]
        traits = f'<p class="traits">carries {esc(", ".join(names))}</p>'
    members = ""
    if t["members"]:
        rows = []
        for name, raw in t["members"]:
            mdoc = docs.get(f'{t["name"]}::{name}')
            rows.append(
                f'<li><code>{esc(raw.rstrip(","))}</code>'
                + (f'<span class="m-doc">{para(mdoc)}</span>' if mdoc else "")
                + "</li>"
            )
        members = f'<ul class="members">{"".join(rows)}</ul>'
    methods = []
    for m in t["methods"]:
        if m["name"] in GENERATED and not docs.get(f'{t["name"]}::{m["name"]}'):
            continue
        mdoc = docs.get(f'{t["name"]}::{m["name"]}')
        methods.append(
            f'<div class="method"><code>{esc(m["sig"])}</code>'
            + (para(mdoc) if mdoc else "") + "</div>"
        )
    meth = f'<div class="methods">{"".join(methods)}</div>' if methods else ""
    return f'<article class="type">{head}{traits}{(para(doc) if doc else "<p class=\"missing\">missing doc</p>")}{members}{meth}</article>'


def value_html(v, docs):
    doc = docs.get(v["name"])
    body = para(doc) if doc else '<p class="missing">missing doc</p>'
    return (f'<div class="value"><code>{esc(v["sig"])}</code>{body}</div>')


def build():
    docs = harvest_docs()
    missing = []
    sections = []
    for name, rel, blurb in PKGS:
        mbti = ROOT / rel / "pkg.generated.mbti"
        values, types, aliases = parse(mbti.read_text(encoding="utf-8"))
        for v in values:
            if v["name"] not in docs:
                missing.append(f"{name}::{v['name']}")
        for t in types:
            if t["name"] not in docs and t["kind"] != "suberror":
                missing.append(f"{name}::{t['name']}")

        vals = "".join(value_html(v, docs) for v in values) or '<p class="empty">no loose values</p>'
        tps = "".join(type_html(t, docs) for t in types) or '<p class="empty">no named types</p>'
        als = ""
        if aliases:
            als = '<h4>aliases</h4><ul class="aliases">' + "".join(
                f'<li><code>typealias {esc(a["name"])} = {esc(a["to"])}</code></li>' for a in aliases
            ) + "</ul>"
        sections.append(f"""
        <section class="pkg" id="pkg-{esc(name.replace('/', '-'))}">
          <header class="pkg-head">
            <h2>{esc(name)}</h2>
            <p class="blurb">{esc(blurb)}</p>
          </header>
          <h4>values</h4>
          <div class="values">{vals}</div>
          <h4>types</h4>
          <div class="types">{tps}</div>
          {als}
        </section>""")

    if missing:
        sys.exit("these public items have no doc comment:\n  " + "\n  ".join(missing))

    nav = "".join(
        f'<a href="#pkg-{esc(n.replace("/", "-"))}">{esc(n)}</a>' for n, _, _ in PKGS
    )
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MOONMODEL — API reference</title>
<link rel="stylesheet" href="assets/type.css">
<link rel="stylesheet" href="assets/tokens.css">
<style>
  html,body{{margin:0;background:var(--desk);color:var(--ink);}}
  body{{font-family:'Jost',system-ui,sans-serif;-webkit-font-smoothing:antialiased;}}
  .wrap{{max-width:1180px;margin:0 auto;padding:56px 40px 120px;}}
  .sheet{{background:var(--paper);border:1px solid var(--ink);outline:1px solid var(--ink);
          outline-offset:8px;padding:56px 64px;position:relative;
          box-shadow:0 24px 60px -30px rgba(0,0,0,.55);}}
  .sheet::after{{content:"";position:absolute;inset:14px;border:1px solid var(--ink);
                 opacity:.25;pointer-events:none;}}
  h1{{font-family:'Cinzel',serif;font-weight:700;letter-spacing:.16em;font-size:40px;margin:0;}}
  .sub{{font-family:'EB Garamond',serif;font-style:italic;font-size:20px;opacity:.85;margin:.3em 0 0;}}
  .meta{{font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.14em;opacity:.6;
         display:flex;gap:22px;margin-top:22px;flex-wrap:wrap;}}
  .meta a{{color:inherit;}}
  nav{{margin:28px 0 12px;display:flex;gap:10px;flex-wrap:wrap;}}
  nav a{{font-family:'IBM Plex Mono',monospace;font-size:11px;letter-spacing:.06em;
         text-decoration:none;color:var(--ink);border:1px solid var(--ink);
         border-radius:14px;padding:5px 13px;opacity:.8;}}
  nav a:hover{{background:var(--accent);color:var(--paper);border-color:var(--accent);}}
  .bar{{display:flex;gap:12px;margin:18px 0 6px;align-items:stretch;}}
  .bar #filter{{flex:1;font-family:'IBM Plex Mono',monospace;font-size:12.5px;letter-spacing:.02em;}}
  .bar #night{{flex:0 0 auto;font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.14em;}}
  .pkg{{margin-top:54px;border-top:1px solid var(--ink);padding-top:26px;}}
  .pkg-head h2{{font-family:'IBM Plex Mono',monospace;font-size:15px;letter-spacing:.04em;
                margin:0;color:var(--accent);}}
  .blurb{{font-family:'EB Garamond',serif;font-style:italic;font-size:15px;opacity:.7;margin:.3em 0 0;}}
  h4{{font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.22em;
      text-transform:uppercase;opacity:.55;margin:30px 0 12px;}}
  .value,.method{{border-left:2px solid var(--brass);padding:10px 0 10px 16px;margin:0 0 16px;}}
  .value>code,.method>code{{font-family:'IBM Plex Mono',monospace;font-size:12.5px;
      display:block;white-space:pre-wrap;word-break:break-word;line-height:1.5;}}
  .value p,.method p,.type p{{font-size:14px;line-height:1.62;opacity:.86;margin:.5em 0 0;max-width:74ch;}}
  .type{{margin:0 0 30px;}}
  .type h3{{font-family:'Cinzel',serif;font-size:20px;letter-spacing:.06em;margin:0 0 .1em;}}
  .kind{{font-family:'IBM Plex Mono',monospace;font-size:9px;letter-spacing:.14em;
         border:1px solid var(--ink);border-radius:9px;padding:2px 7px;opacity:.55;
         vertical-align:middle;text-transform:uppercase;}}
  .traits{{font-family:'IBM Plex Mono',monospace;font-size:10.5px;opacity:.6;margin:.4em 0;}}
  .members{{list-style:none;padding:0;margin:12px 0;border-left:1px dotted var(--ink);}}
  .members li{{padding:5px 0 5px 16px;font-size:13px;}}
  .members code{{font-family:'IBM Plex Mono',monospace;font-size:12.5px;}}
  .m-doc{{display:block;font-size:12.5px;opacity:.7;margin-top:2px;}}
  .m-doc p{{margin:.2em 0;}}
  .missing{{color:var(--red);font-family:'IBM Plex Mono',monospace;font-size:11px;}}
  .empty{{font-family:'IBM Plex Mono',monospace;font-size:11px;opacity:.45;}}
  .aliases code{{font-family:'IBM Plex Mono',monospace;font-size:12.5px;}}
  code{{font-family:'IBM Plex Mono',monospace;}}
  p code,li code{{background:rgba(0,0,0,.06);padding:.05em .3em;border-radius:3px;font-size:.92em;}}
  .foot{{margin-top:64px;padding-top:18px;border-top:1px solid var(--ink);
         font-family:'IBM Plex Mono',monospace;font-size:10px;letter-spacing:.1em;opacity:.6;
         display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;}}
  a{{color:var(--accent);}}
</style>
</head>
<body>
<div class="wrap"><div class="sheet">
  <h1>MOONMODEL</h1>
  <p class="sub">API reference — one description, four projections</p>
  <div class="meta">
    <span>SHEET 02 / 01 · THE SURFACE</span>
    <span><a href="index.html">← the front sheet</a></span>
    <span><a href="guide.html">guide</a></span>
    <span><a href="showcase.html">showcase</a></span>
    <span><a href="https://github.com/moonbitstack/moonmodel">github</a></span>
  </div>
  <nav>{nav}</nav>
  <div class="bar">
    <input id="filter" type="text" autocomplete="off"
           placeholder="filter the surface — a type, a value, a method…">
    <button id="night" type="button">EDITION 1 — CHART</button>
  </div>
  {''.join(sections)}
  <div class="foot">
    <span>APACHE-2.0 · MOONBITSTACK/MOONMODEL</span>
    <span>moon add moonbitstack/moonmodel</span>
  </div>
</div></div>
<script>
  const filter = document.getElementById('filter');
  filter.addEventListener('input', () => {{
    const q = filter.value.trim().toLowerCase();
    document.querySelectorAll('.type,.value').forEach(n => {{
      n.style.display = (!q || n.textContent.toLowerCase().includes(q)) ? '' : 'none';
    }});
    document.querySelectorAll('.pkg').forEach(p => {{
      const any = [...p.querySelectorAll('.type,.value')].some(n => n.style.display !== 'none');
      p.style.display = any ? '' : 'none';
    }});
  }});
  const nightBtn = document.getElementById('night');
  function setNight(on) {{
    document.documentElement.classList.toggle('night', on);
    nightBtn.textContent = on ? 'EDITION 2 — NIGHT' : 'EDITION 1 — CHART';
  }}
  nightBtn.addEventListener('click', () =>
    setNight(!document.documentElement.classList.contains('night')));
  if (location.search.includes('night')) setNight(true);
</script>
</body>
</html>
"""


def main():
    DOCS.mkdir(exist_ok=True)
    (DOCS / "api.html").write_text(build(), encoding="utf-8", newline="\n")
    print("api.html <- the interfaces and their doc comments")


if __name__ == "__main__":
    main()
