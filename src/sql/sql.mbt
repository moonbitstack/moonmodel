// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which SQL is being written. The three disagree about nearly every type
/// name, so the dialect is a parameter rather than a default anyone could
/// guess at.
pub(all) enum Dialect {
  Sqlite
  Postgres
  Mysql
} derive(Eq, Debug)

///|
pub extend Dialect with Eq::{equal, not_equal}

///|
pub extend Dialect with Debug::{to_repr}

///|
/// A field that has no column, and why.
///
/// Reported rather than dropped: a table silently missing a field is a bug
/// that shows up as missing data much later.
pub(all) struct Skipped {
  field : String
  why : String
} derive(Eq, Debug)

///|
pub extend Skipped with Eq::{equal, not_equal}

///|
pub extend Skipped with Debug::{to_repr}

///|
/// One column.
pub(all) struct Column {
  name : String
  /// The type as this dialect spells it.
  kind : String
  /// Whether the column takes NULL. A field that is optional or nullable
  /// does; a required, non-nullable one does not.
  null : Bool
  /// A default, already written as SQL text, or absent.
  default : String?
  /// Whether no two rows may carry the same value, from `Check::unique`.
  unique : Bool
  /// The CHECK clause the bounds amount to, or empty when they amount to
  /// nothing.
  check : String
} derive(Eq, Debug)

///|
pub extend Column with Eq::{equal, not_equal}

///|
pub extend Column with Debug::{to_repr}

///|
/// A model as columns, and the fields that could not become one.
///
/// Both halves are returned because a caller needs to decide what to do about
/// the second: store it as JSON, put it in another table, or refuse.
pub fn of(
  model : @moonmodel.Model,
  dialect~ : Dialect = Sqlite,
) -> (Array[Column], Array[Skipped]) {
  let columns = []
  let skipped = []
  for field in model.fields {
    match kind_of(field.kind, dialect) {
      Some(kind) =>
        columns.push({
          name: field.name,
          kind,
          null: !field.required || field.nullable,
          default: literal(field.default),
          unique: field.check.unique,
          check: clause(field.name, field.check),
        })
      None => skipped.push({ field: field.name, why: unstorable(field.kind), })
    }
  }
  (columns, skipped)
}

///|
/// `CREATE TABLE`, with the fields that have no column left out — the caller
/// reads the second half of `of` to learn which.
pub fn table(
  model : @moonmodel.Model,
  dialect~ : Dialect = Sqlite,
  name~ : String = "",
) -> String {
  let (columns, _skipped) = of(model, dialect~)
  let table = if name == "" { model.name } else { name }
  let out = StringBuilder()
  out.write_string("CREATE TABLE ")
  out.write_string(table)
  out.write_string(" (\n")
  for i = 0; i < columns.length(); i = i + 1 {
    let one = columns[i]
    out.write_string("  ")
    out.write_string(one.name)
    out.write_string(" ")
    out.write_string(one.kind)
    if !one.null {
      out.write_string(" NOT NULL")
    }
    if one.unique {
      out.write_string(" UNIQUE")
    }
    match one.default {
      Some(value) => {
        out.write_string(" DEFAULT ")
        out.write_string(value)
      }
      None => ()
    }
    if one.check != "" {
      out.write_string(" CHECK (")
      out.write_string(one.check)
      out.write_string(")")
    }
    if i + 1 < columns.length() {
      out.write_string(",")
    }
    out.write_string("\n")
  }
  out.write_string(")")
  out.to_string()
}

///|
/// The type as this dialect spells it, or nothing when there is no column for
/// it.
///
/// A list becomes a column only in Postgres, which has real arrays; elsewhere
/// it has none, and storing it as JSON text is the caller's decision to make,
/// not this package's to make quietly.
fn kind_of(kind : @moonmodel.Type, dialect : Dialect) -> String? {
  match (kind, dialect) {
    (Bool, Sqlite) => Some("INTEGER")
    (Bool, Postgres) => Some("BOOLEAN")
    (Bool, Mysql) => Some("TINYINT(1)")
    (Int, Sqlite) => Some("INTEGER")
    (Int, Postgres) => Some("INTEGER")
    (Int, Mysql) => Some("INT")
    (Big, Sqlite) => Some("INTEGER")
    (Big, Postgres) => Some("BIGINT")
    (Big, Mysql) => Some("BIGINT")
    (Real, Sqlite) => Some("REAL")
    (Real, Postgres) => Some("DOUBLE PRECISION")
    (Real, Mysql) => Some("DOUBLE")
    (Text, Sqlite) => Some("TEXT")
    (Text, Postgres) => Some("TEXT")
    (Text, Mysql) => Some("TEXT")
    (Bytes, Sqlite) => Some("BLOB")
    (Bytes, Postgres) => Some("BYTEA")
    (Bytes, Mysql) => Some("BLOB")
    // SQLite has no date type at all; its own documentation says to store
    // one as TEXT in ISO-8601, which is what every SQLite library does.
    (Stamp, Sqlite) => Some("TEXT")
    (Stamp, Postgres) => Some("TIMESTAMPTZ")
    (Stamp, Mysql) => Some("DATETIME")
    (List(inner), Postgres) =>
      match kind_of(inner, Postgres) {
        Some(inner) => Some(inner + "[]")
        None => None
      }
    _ => None
  }
}

///|
/// Why a field has no column.
fn unstorable(kind : @moonmodel.Type) -> String {
  match kind {
    List(_) =>
      "a list needs its own table, or an array type the dialect does not have"
    Dict(_) => "a mapping with open keys needs its own table"
    Ref(name) =>
      "a reference to \{name} is a foreign key, which needs that table's key"
    Nest(_) => "a nested model needs its own table"
    Any => "anything at all has no column type"
    Raw(_) => "a schema written out by hand has no column type"
    _ => "no column type"
  }
}

///|
/// A default, written as SQL text. Only the literals every dialect agrees on.
fn literal(value : Json?) -> String? {
  match value {
    None => None
    Some(Null) => Some("NULL")
    Some(True) => Some("TRUE")
    Some(False) => Some("FALSE")
    Some(Number(value, ..)) => Some(value.to_string())
    Some(String(text)) => Some("'" + text.replace(old="'", new="''") + "'")
    // An array or object default is a literal in no two dialects alike.
    _ => None
  }
}

///|
/// The bounds as a CHECK clause.
///
/// Only the ones SQL states the same way everywhere: ranges and the closed
/// set. A pattern is a regular expression, and the three dialects spell that
/// with three different operators, so it is left to the caller.
fn clause(name : String, check : @moonmodel.Check) -> String {
  let parts = []
  bound(parts, name, ">=", check.least)
  bound(parts, name, "<=", check.most)
  bound(parts, name, ">", check.over)
  bound(parts, name, "<", check.under)
  if check.options.length() > 0 {
    let written = []
    for one in check.options {
      // A value SQL has no literal for takes the whole clause with it: a
      // partial IN list would silently refuse what it should allow.
      match literal(Some(one)) {
        Some(text) => written.push(text)
        None => {
          written.clear()
          break
        }
      }
    }
    if written.length() > 0 {
      parts.push(name + " IN (" + join(written, ", ") + ")")
    }
  }
  match check.longest {
    Some(longest) => parts.push("length(\{name}) <= \{longest}")
    None => ()
  }
  match check.shortest {
    Some(shortest) => parts.push("length(\{name}) >= \{shortest}")
    None => ()
  }
  join(parts, " AND ")
}

///|
fn bound(
  parts : Array[String],
  name : String,
  op : String,
  value : Double?,
) -> Unit {
  match value {
    Some(value) => parts.push("\{name} \{op} \{value}")
    None => ()
  }
}

///|
fn join(parts : Array[String], with_ : String) -> String {
  let out = StringBuilder()
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out.write_string(with_)
    }
    out.write_string(parts[i])
  }
  out.to_string()
}
