// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The labels, held to this library's own entry. The harness asks an
// independent validator the same questions, so a disagreement here is either
// the description or the reading of it — in both cases a real fault, since the
// label was written from the description.

///|
fn lookup(name : String) -> @moonmodel.Model raise {
  for one in models() {
    if one.name == name {
      return one
    }
  }
  fail("the corpus has no model \{name}")
}

///|
test "every labelled instance gets the verdict the description calls for" {
  let all = models()
  for one in cases() {
    let verdict = @verify.valid(lookup(one.model), one.data, known=all) catch {
      _ => false
    }
    if verdict != one.valid {
      fail("\{one.model}: \{one.why} — wanted \{one.valid}, read \{verdict}")
    }
  }
}

///|
test "every model has an instance, and every instance names a model" {
  let named = []
  for one in models() {
    named.push(one.name)
  }
  let covered = []
  for one in cases() {
    assert_true(named.contains(one.model))
    if !covered.contains(one.model) {
      covered.push(one.model)
    }
  }
  assert_eq(covered.length(), named.length())
}

///|
test "every model with a table has a probe, and every probe names a model" {
  let tables = []
  for one in models() {
    let (columns, _skipped) = @sql.of(one, dialect=@sql.Dialect::Sqlite)
    if columns.length() > 0 {
      tables.push(one.name)
    }
  }
  let covered = []
  for one in probes() {
    assert_true(tables.contains(one.model))
    if !covered.contains(one.model) {
      covered.push(one.model)
    }
  }
  assert_eq(covered.length(), tables.length())
}

///|
test "a probe runs against the table the DDL declares, name and all" {
  for one in probes() {
    let ddl = @sql.table(lookup(one.model), dialect=@sql.Dialect::Sqlite)
    let declared = match ddl.find("CREATE TABLE ") {
      Some(at) =>
        match ddl.exact_view(start=at + 13).find(" (") {
          Some(end) =>
            ddl.exact_view(start=at + 13, end=at + 13 + end).to_owned()
          None => fail("\{one.model}: the DDL has no column list")
        }
      None => fail("\{one.model}: the DDL does not start a table")
    }
    if !one.sql.contains(declared) {
      fail("\{one.model}: the probe does not name the table \{declared}")
    }
  }
}
