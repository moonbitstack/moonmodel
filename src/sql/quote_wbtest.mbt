// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Names, and the one place a document is not a name: `CREATE TABLE Order` is a
// syntax error, and so is a column called `group`. A name is quoted when the
// engine would read it as a keyword, and left alone when it would not — a
// table called `users` reads better than a quoted one and means the same.

///|
test "a name every dialect reads as a name is left bare" {
  let model = @moonmodel.Model::new("users", [
    @moonmodel.Field::new("id", @moonmodel.Big),
    @moonmodel.Field::new("display_name", @moonmodel.Text),
    @moonmodel.Field::new("login2", @moonmodel.Text),
  ])
  assert_eq(
    table(model, dialect=Sqlite),
    (
      #|CREATE TABLE users (
      #|  id INTEGER NOT NULL,
      #|  display_name TEXT NOT NULL,
      #|  login2 TEXT NOT NULL
      #|)
    ),
  )
}

///|
test "a reserved word is quoted, before and after the name it belongs to" {
  let model = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("group", @moonmodel.Text),
    @moonmodel.Field::new(
      "total",
      @moonmodel.Real,
      check=@moonmodel.Check::new(least=0.0),
    ),
  ])
  assert_eq(
    table(model, dialect=Sqlite),
    (
      #|CREATE TABLE "Order" (
      #|  "group" TEXT NOT NULL,
      #|  total REAL NOT NULL CHECK (total >= 0)
      #|)
    ),
  )
}

///|
test "a bound names its column the same way the column is named" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "order",
      @moonmodel.Text,
      check=@moonmodel.Check::new(longest=8, options=["a", "b"]),
    ),
  ])
  assert_eq(
    table(model, dialect=Sqlite),
    (
      #|CREATE TABLE T (
      #|  "order" TEXT NOT NULL CHECK ("order" IN ('a', 'b') AND length("order") <= 8)
      #|)
    ),
  )
}

///|
test "mysql quotes with the mark it quotes with" {
  let model = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("group", @moonmodel.Text),
  ])
  assert_eq(
    table(model, dialect=Mysql),
    (
      #|CREATE TABLE `Order` (
      #|  `group` TEXT NOT NULL
      #|)
    ),
  )
}

///|
test "a name that is not an identifier at all is quoted, and its quotes doubled" {
  let model = @moonmodel.Model::new("two words", [
    @moonmodel.Field::new("a\"b", @moonmodel.Text),
  ])
  assert_eq(
    table(model, dialect=Postgres),
    (
      #|CREATE TABLE "two words" (
      #|  "a""b" TEXT NOT NULL
      #|)
    ),
  )
  assert_eq(
    table(model, dialect=Mysql),
    (
      #|CREATE TABLE `two words` (
      #|  `a"b` TEXT NOT NULL
      #|)
    ),
  )
}

///|
test "the words the engine refuses are the words this package quotes" {
  // Every word in the generated table is one SQLite will not take bare, and
  // the DDL for each is the same word with quotes around it.
  for word in reserved {
    let model = @moonmodel.Model::new("T", [
      @moonmodel.Field::new(word, @moonmodel.Text),
    ])
    let ddl = table(model, dialect=Sqlite)
    let wanted = "\"" + word + "\" TEXT NOT NULL"
    if !ddl.contains(wanted) {
      fail("\{word} is not quoted: \{ddl}")
    }
  }
}
