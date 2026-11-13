#!/usr/bin/env python3
"""Hold what this library writes to the engines and libraries that read it.

    python3 scripts/conformance/check.py               # run the generator first
    python3 scripts/conformance/check.py --bundle f.json

`moon run src/cmd/conformance` prints one JSON document: the corpus of models,
their four projections, a labelled instance for every shape of value, and
statements the SQLite dialect's tables must accept or refuse. Nothing in this
script knows how to describe a model, and none of the implementations below are
ours — they are the reference implementations of the four formats, so a
disagreement is a fault in the projection and not a second opinion about it:

* JSON Schema 2020-12 — `jsonschema`, the validator the official test suite is
  run against. Every written schema must be a schema, and every verdict on a
  labelled instance must be the label.
* OpenAPI 3.1, 3.0 and 2.0 — `openapi-spec-validator`, which checks the document
  against the specification's own JSON Schema.
* GraphQL — `graphql-core`, the port of the reference `graphql-js`. The SDL must
  build, and the types it builds to must agree with the model's own `required`
  and `nullable` flags.
* SQL — `sqlite3` executes the SQLite dialect's DDL and then refuses or accepts
  each labelled statement; `sqlglot` parses the PostgreSQL and MySQL dialects
  and reads the columns back, which is a second reader's view of the same text.
* JSON Schema, generation — `pydantic`, which describes the same corpus a second
  time (`twins.py`) and must agree about a field's type, its required set and
  its bounds.

Exit status is 0 only when every check passes.
"""

import argparse
import importlib.metadata
import json
import pathlib
import re
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import jsonschema
import sqlglot
from graphql import build_schema, GraphQLError
from graphql.type import is_list_type, is_non_null_type
from openapi_spec_validator import validate as validate_openapi
from sqlglot import exp

from twins import TWINS

BOUNDS = (
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
    "minLength", "maxLength", "minItems", "maxItems", "pattern", "enum",
)


class Report:
    """One line per area, and the failures that go under it."""

    def __init__(self):
        self.rows = []
        self.failures = []

    def row(self, area, detail, ok=True):
        self.rows.append((area, detail, ok))

    def fail(self, area, detail):
        self.rows.append((area, detail, False))
        self.failures.append(f"{area}: {detail}")

    def print(self):
        width = max(len(area) for area, _, _ in self.rows)
        for area, detail, ok in self.rows:
            mark = "ok  " if ok else "FAIL"
            print(f"  {mark}  {area.ljust(width)}  {detail}")
        print()
        if self.failures:
            print(f"{len(self.failures)} disagreement(s):")
            for one in self.failures:
                print(f"  - {one}")
        else:
            print("every projection agrees with every reader it was offered to")


def bundle(path):
    if path:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    run = subprocess.run(
        ["moon", "run", "src/cmd/conformance", "--target", "native"],
        cwd=ROOT, capture_output=True, text=True,
    )
    text = run.stdout
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < 0:
        sys.exit("the generator printed no JSON:\n" + run.stdout + run.stderr)
    return json.loads(text[start:end + 1])


# --- JSON Schema ------------------------------------------------------------

def check_schemas(doc, report):
    schemas = {one["name"]: one["schema"] for one in doc["models"]}
    for name, schema in schemas.items():
        try:
            jsonschema.Draft202012Validator.check_schema(schema)
        except jsonschema.SchemaError as error:
            report.fail("JSON Schema", f"{name}: {error.message}")
    report.row(
        "JSON Schema",
        f"{len(schemas)} documents are 2020-12 schemas "
        f"(jsonschema {importlib.metadata.version('jsonschema')})",
        not any(area == "JSON Schema" and not ok for area, _, ok in report.rows),
    )
    return schemas


def check_verdicts(doc, schemas, report):
    total = 0
    agree = 0
    for case in doc["cases"]:
        total += 1
        schema = schemas[case["model"]]
        theirs = jsonschema.Draft202012Validator(schema).is_valid(case["instance"])
        if theirs == case["valid"] and case["ours"] == case["valid"]:
            agree += 1
            continue
        report.fail(
            "verdicts",
            f"{case['model']}: {case['why']} — label {case['valid']}, "
            f"jsonschema {theirs}, this library {case['ours']}",
        )
    report.row(
        "verdicts",
        f"{agree}/{total} labelled instances read the same by jsonschema "
        f"and by this library",
        agree == total,
    )


# --- JSON Schema generation, against a second implementation ---------------

def kinds(schema):
    """The JSON types a schema admits, before `null` is taken out."""
    if not isinstance(schema, dict):
        return set()
    if "$ref" in schema:
        return {"object"}
    found = schema.get("type")
    if found is None:
        out = set()
        for key in ("anyOf", "oneOf", "allOf"):
            for part in schema.get(key, []):
                out |= kinds(part)
        return out or {"any"}
    return set(found) if isinstance(found, list) else {found}


def value(schema):
    """The schema of the value itself: pydantic puts a field's bounds inside the
    branch that is not null, and this library puts them beside the type."""
    for key in ("anyOf", "oneOf"):
        parts = schema.get(key)
        if parts:
            kept = [one for one in parts if one.get("type") != "null"]
            if len(kept) == 1:
                return kept[0]
    return schema


def under_ref(schema):
    """A model that refers to itself is a document whose top level is the
    reference; a reader has to go through it before it sees any properties."""
    found = schema.get("$ref")
    if found and found.startswith("#/$defs/"):
        return schema.get("$defs", {}).get(found.rsplit("/", 1)[-1], schema)
    return schema


def same(one, two):
    if isinstance(one, float) or isinstance(two, float):
        try:
            return abs(float(one) - float(two)) < 1e-9
        except (TypeError, ValueError):
            return one == two
    return one == two


def check_pydantic(doc, schemas, report):
    before = len(report.failures)
    compared = 0
    fields = 0
    for model in doc["models"]:
        twin = TWINS.get(model["name"])
        if twin is None:
            continue
        compared += 1
        theirs = under_ref(twin.model_json_schema())
        ours = under_ref(schemas[model["name"]])
        if sorted(ours.get("required", [])) != sorted(theirs.get("required", [])):
            report.fail(
                "generation",
                f"{model['name']}: required is {sorted(ours.get('required', []))} here and "
                f"{sorted(theirs.get('required', []))} there",
            )
        mine = ours.get("properties", {})
        other = theirs.get("properties", {})
        if sorted(mine) != sorted(other):
            report.fail(
                "generation",
                f"{model['name']}: properties are {sorted(mine)} here and {sorted(other)} there",
            )
        for name in sorted(set(mine) & set(other)):
            fields += 1
            left, right = value(mine[name]), value(other[name])
            # pydantic spells "may be absent" and "may be null" the same way,
            # so null is compared by the verdicts above and not here.
            if kinds(left) - {"null"} != kinds(right) - {"null"}:
                report.fail(
                    "generation",
                    f"{model['name']}.{name}: type {sorted(kinds(left))} here, "
                    f"{sorted(kinds(right))} there",
                )
            for bound in BOUNDS:
                if bound in left and bound in right:
                    if not same(left[bound], right[bound]):
                        report.fail(
                            "generation",
                            f"{model['name']}.{name}: {bound} {left[bound]!r} here, "
                            f"{right[bound]!r} there",
                        )
                elif bound in left:
                    report.fail(
                        "generation",
                        f"{model['name']}.{name}: {bound} is written here and not there",
                    )
                elif bound in right:
                    report.fail(
                        "generation",
                        f"{model['name']}.{name}: {bound} is written there and not here",
                    )
    report.row(
        "generation",
        f"{compared} models and {fields} fields agree with pydantic",
        len(report.failures) == before,
    )


# --- OpenAPI ----------------------------------------------------------------

def check_openapi(doc, report):
    envelope = doc["openapi"]
    documents = {
        "openapi31": {
            "openapi": "3.1.0",
            "info": {"title": "moonmodel", "version": "1"},
            "paths": {},
            **envelope["openapi31"],
        },
        "openapi30": {
            "openapi": "3.0.3",
            "info": {"title": "moonmodel", "version": "1"},
            "paths": {},
            **envelope["openapi30"],
        },
        "swagger20": {
            "swagger": "2.0",
            "info": {"title": "moonmodel", "version": "1"},
            "paths": {},
            **envelope["swagger20"],
        },
    }
    for name, document in documents.items():
        try:
            validate_openapi(document)
        except Exception as error:            # the validator raises its own tree
            first = str(error).splitlines()[0] if str(error) else repr(error)
            report.fail("OpenAPI", f"{name}: {first}")
    report.row(
        "OpenAPI",
        f"{len(documents)} documents validate: 3.1, 3.0 and 2.0",
        not any(area == "OpenAPI" and not ok for area, _, ok in report.rows),
    )


# --- GraphQL ----------------------------------------------------------------

def check_graphql(doc, report):
    try:
        schema = build_schema(doc["sdl"])
    except GraphQLError as error:
        report.fail("GraphQL", f"the SDL does not build: {error.message}")
        return
    fields = 0
    for model in doc["models"]:
        kind = schema.type_map.get(model["name"])
        if kind is None:
            report.fail("GraphQL", f"{model['name']} is not a type in the document")
            continue
        skipped = {one["field"] for one in model["sdl_skipped"]}
        for field in model["fields"]:
            if field["name"] in skipped:
                continue
            written = kind.fields.get(field["name"])
            if written is None:
                report.fail("GraphQL", f"{model['name']}.{field['name']} is missing")
                continue
            fields += 1
            wanted = field["required"] and not field["nullable"]
            if is_non_null_type(written.type) != wanted:
                report.fail(
                    "GraphQL",
                    f"{model['name']}.{field['name']}: written as {written.type}, "
                    f"but required={field['required']} nullable={field['nullable']}",
                )
            inner = written.type.of_type if is_non_null_type(written.type) else written.type
            if field["list"]:
                if not is_list_type(inner):
                    report.fail(
                        "GraphQL",
                        f"{model['name']}.{field['name']}: a list is written as {inner}",
                    )
                elif not is_non_null_type(inner.of_type):
                    report.fail(
                        "GraphQL",
                        f"{model['name']}.{field['name']}: the items of a list are nullable",
                    )
    report.row(
        "GraphQL",
        f"{fields} fields build and keep their nullability",
        not any(area == "GraphQL" and not ok for area, _, ok in report.rows),
    )


# --- SQL --------------------------------------------------------------------

TABLE = re.compile(r"^CREATE TABLE (.+?) \($", re.M)


def check_sqlite(doc, report):
    tables = 0
    columns = 0
    probes = 0
    refusals = 0
    for model in doc["models"]:
        ddl = model["ddl"]["sqlite"]
        written = model["columns"]["sqlite"]
        if not written:
            continue
        found = TABLE.search(ddl)
        if not found:
            report.fail("SQLite", f"{model['name']}: the DDL does not start a table")
            continue
        handle = sqlite3.connect(":memory:")
        try:
            handle.execute(ddl)
        except sqlite3.Error as error:
            report.fail("SQLite", f"{model['name']}: {error}")
            handle.close()
            continue
        tables += 1
        rows = handle.execute(f"PRAGMA table_info({found.group(1)})").fetchall()
        if [row[1] for row in rows] != [one["name"] for one in written]:
            report.fail(
                "SQLite",
                f"{model['name']}: the engine has {[r[1] for r in rows]} where the "
                f"projection has {[one['name'] for one in written]}",
            )
        for row, one in zip(rows, written):
            columns += 1
            _, name, kind, notnull, default, _pk = row
            if kind.upper() != one["kind"].upper():
                report.fail("SQLite", f"{model['name']}.{name}: {kind} != {one['kind']}")
            if bool(notnull) != (not one["null"]):
                report.fail("SQLite", f"{model['name']}.{name}: NOT NULL disagrees")
            if (default or None) != (one["default"] or None):
                report.fail(
                    "SQLite", f"{model['name']}.{name}: default {default!r} != {one['default']!r}"
                )
        for probe in doc["probes"]:
            if probe["model"] != model["name"]:
                continue
            probes += 1
            try:
                handle.execute(probe["sql"])
                accepted = True
            except sqlite3.Error:
                accepted = False
                refusals += 1
            if accepted != probe["valid"]:
                report.fail(
                    "SQLite",
                    f"{model['name']}: {probe['why']} — the engine "
                    f"{'accepted' if accepted else 'refused'} it",
                )
        handle.rollback()
        handle.close()
    report.row(
        "SQLite",
        f"{tables} tables, {columns} columns read back, {probes} statements run "
        f"({refusals} refused by the engine)",
        not any(area == "SQLite" and not ok for area, _, ok in report.rows),
    )


def normal(kind, dialect):
    """A type as the dialect's own parser writes it, so `INTEGER` and `INT` are
    the same type and not two."""
    if isinstance(kind, str):
        kind = exp.DataType.build(kind, dialect=dialect)
    return kind.sql(dialect=dialect)


def check_dialects(doc, report):
    parsed = 0
    columns = 0
    for model in doc["models"]:
        for dialect in ("postgres", "mysql"):
            ddl = model["ddl"][dialect]
            if not model["columns"][dialect]:
                continue
            try:
                tree = sqlglot.parse_one(ddl, dialect=dialect)
            except Exception as error:        # sqlglot raises its own tree
                report.fail("PostgreSQL/MySQL", f"{model['name']} ({dialect}): {error}")
                continue
            parsed += 1
            found = [
                (one.this.this, normal(one.args["kind"], dialect))
                for one in tree.find_all(exp.ColumnDef)
            ]
            written = [
                (one["name"], normal(one["kind"], dialect))
                for one in model["columns"][dialect]
            ]
            if found != written:
                report.fail(
                    "PostgreSQL/MySQL",
                    f"{model['name']} ({dialect}): read back {found}, wrote {written}",
                )
            columns += len(found)
    report.row(
        "PostgreSQL/MySQL",
        f"{parsed} DDL statements parse and {columns} columns read back "
        f"(sqlglot {sqlglot.__version__})",
        not any(area == "PostgreSQL/MySQL" and not ok for area, _, ok in report.rows),
    )


# --- driver -----------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", help="read a generator dump instead of running it")
    args = parser.parse_args()

    doc = bundle(args.bundle)
    report = Report()
    schemas = check_schemas(doc, report)
    check_verdicts(doc, schemas, report)
    check_pydantic(doc, schemas, report)
    check_openapi(doc, report)
    check_graphql(doc, report)
    check_sqlite(doc, report)
    check_dialects(doc, report)
    report.print()
    sys.exit(1 if report.failures else 0)


if __name__ == "__main__":
    main()
