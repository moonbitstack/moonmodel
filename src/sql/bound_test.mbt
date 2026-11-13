// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The four bounds, and the one character that tells the two pairs apart. An
// engine reads `>= 0` and `> 0` differently, so a column written with the
// wrong one accepts a row the description refuses.

///|
test "a closed bound keeps its value, an open one does not" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "closed",
      @moonmodel.Real,
      check=@moonmodel.Check::new(least=0.0, most=10.0),
    ),
    @moonmodel.Field::new(
      "open",
      @moonmodel.Real,
      check=@moonmodel.Check::new(over=0.0, under=10.0),
    ),
  ])
  assert_eq(
    @sql.table(model, dialect=Sqlite),
    (
      #|CREATE TABLE T (
      #|  closed REAL NOT NULL CHECK (closed >= 0 AND closed <= 10),
      #|  open REAL NOT NULL CHECK (open > 0 AND open < 10)
      #|)
    ),
  )
}

///|
test "one pair of bounds holds both ends at once" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "x",
      @moonmodel.Int,
      check=@moonmodel.Check::new(least=0.0, under=100.0),
    ),
  ])
  assert_eq(
    @sql.table(model, dialect=Sqlite),
    (
      #|CREATE TABLE T (
      #|  x INTEGER NOT NULL CHECK (x >= 0 AND x < 100)
      #|)
    ),
  )
}

///|
test "a length bound counts characters, not values" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "x",
      @moonmodel.Text,
      check=@moonmodel.Check::new(shortest=1, longest=8),
    ),
  ])
  assert_eq(
    @sql.table(model, dialect=Sqlite),
    (
      #|CREATE TABLE T (
      #|  x TEXT NOT NULL CHECK (length(x) <= 8 AND length(x) >= 1)
      #|)
    ),
  )
}
