// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// SQL is the projection that loses most, so the tests are as much about what
// it refuses as about what it writes.

///|
fn column(field : @moonmodel.Field, dialect : @sql.Dialect) -> @sql.Column? {
  let model = @moonmodel.Model::new("T", [field])
  let (columns, _skipped) = @sql.of(model, dialect~)
  if columns.length() > 0 {
    Some(columns[0])
  } else {
    None
  }
}

///|
fn kind(kind : @moonmodel.Type, dialect : @sql.Dialect) -> String {
  match column(@moonmodel.Field::new("x", kind), dialect) {
    Some(one) => one.kind
    None => "(none)"
  }
}

///|
/// The three families spell nearly every type differently, which is why the
/// dialect is a parameter and not a default.
test "each dialect spells the types its own way" {
  assert_eq(kind(Bool, Sqlite), "INTEGER")
  assert_eq(kind(Bool, Postgres), "BOOLEAN")
  assert_eq(kind(Bool, Mysql), "TINYINT(1)")
  assert_eq(kind(Big, Sqlite), "INTEGER")
  assert_eq(kind(Big, Postgres), "BIGINT")
  assert_eq(kind(Bytes, Postgres), "BYTEA")
  assert_eq(kind(Bytes, Mysql), "BLOB")
  // SQLite has no date type; its own documentation says to store one as
  // ISO-8601 text, which is what every SQLite library does.
  assert_eq(kind(Stamp, Sqlite), "TEXT")
  assert_eq(kind(Stamp, Postgres), "TIMESTAMPTZ")
  assert_eq(kind(Stamp, Mysql), "DATETIME")
}

///|
/// Postgres has real arrays. The other two have none, and a field is
/// reported rather than quietly turned into JSON text.
test "a list is a column only where arrays exist" {
  assert_eq(kind(List(Text), Postgres), "TEXT[]")
  assert_eq(kind(List(Text), Sqlite), "(none)")
  assert_eq(kind(List(Text), Mysql), "(none)")
}

///|
/// A field with no column is named, with the reason. A table silently
/// missing one shows up as missing data much later.
test "what has no column says so" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("ok", Text),
    @moonmodel.Field::new("tags", Dict(Text)),
    @moonmodel.Field::new("home", Ref("Address")),
    @moonmodel.Field::new("blob", Any),
  ])
  let (columns, skipped) = @sql.of(model)
  assert_eq(columns.length(), 1)
  assert_eq(columns[0].name, "ok")
  assert_eq(skipped.length(), 3)
  assert_eq(skipped[0].field, "tags")
  assert_true(skipped[0].why.contains("own table"))
  assert_eq(skipped[1].field, "home")
  assert_true(skipped[1].why.contains("foreign key"))
  assert_eq(skipped[2].field, "blob")
}

///|
/// NULL is allowed when the field is optional or nullable — SQL has one
/// notion where the description has two, and either one reaches it.
test "NOT NULL follows required and nullable together" {
  let required = column(@moonmodel.Field::new("a", Text), Sqlite)
  let optional = column(
    @moonmodel.Field::new("b", Text, required=false),
    Sqlite,
  )
  let nullable = column(@moonmodel.Field::new("c", Text, nullable=true), Sqlite)
  assert_eq(required.unwrap().null, false)
  assert_eq(optional.unwrap().null, true)
  assert_eq(nullable.unwrap().null, true)
}

///|
test "a whole table reads as DDL" {
  let model = @moonmodel.Model::new("users", [
    @moonmodel.Field::new("id", Big),
    @moonmodel.Field::new(
      "name",
      Text,
      check=@moonmodel.Check::new(shortest=1, longest=64),
    ),
    @moonmodel.Field::new(
      "age",
      Int,
      required=false,
      check=@moonmodel.Check::new(least=0.0, most=150.0),
    ),
    @moonmodel.Field::new(
      "role",
      Text,
      default=Json::string("member"),
      check=@moonmodel.Check::new(options=["member", "admin"]),
    ),
  ])
  let ddl = @sql.table(model, dialect=Postgres)
  assert_eq(
    ddl,
    (
      #|CREATE TABLE users (
      #|  id BIGINT NOT NULL,
      #|  name TEXT NOT NULL CHECK (length(name) <= 64 AND length(name) >= 1),
      #|  age INTEGER CHECK (age >= 0 AND age <= 150),
      #|  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin'))
      #|)
    ),
  )
}

///|
/// A string default is quoted and its quotes doubled, which is the one
/// escaping every dialect agrees on.
test "a text default is quoted safely" {
  let one = column(
    @moonmodel.Field::new("s", Text, default=Json::string("it's")),
    Sqlite,
  )
  assert_eq(one.unwrap().default, Some("'it''s'"))
  // A structured default is a literal in no two dialects alike, so none is
  // written rather than one that is wrong somewhere.
  let other = column(
    @moonmodel.Field::new("t", Text, default=Json::array([])),
    Sqlite,
  )
  assert_eq(other.unwrap().default, None)
}
