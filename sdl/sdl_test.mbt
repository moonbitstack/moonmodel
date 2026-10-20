// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// GraphQL says one thing the others cannot — non-null with `!` — and cannot
// say two they can: a mapping with open keys, and any bound at all. The
// bounds become nothing on purpose: GraphQL validates shape, not range.

///|
fn written(model : @moonmodel.Model) -> String {
  let (text, _skipped) = @sdl.of(model)
  text
}

///|
/// `!` is where GraphQL folds "must be there" and "may not be null" into one
/// mark, so three of the four combinations come out the same.
test "the exclamation mark is required and non-nullable together" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("a", Text),
    @moonmodel.Field::new("b", Text, required=false),
    @moonmodel.Field::new("c", Text, nullable=true),
    @moonmodel.Field::new("d", Text, required=false, nullable=true),
  ])
  assert_eq(
    written(model),
    (
      #|type T {
      #|  a: String!
      #|  b: String
      #|  c: String
      #|  d: String
      #|}
    ),
  )
}

///|
/// GraphQL's Int is 32-bit by specification, so a 64-bit one is not it; and
/// there is no date and no byte string, so both are custom scalars. The
/// names are the ones the ecosystem settled on, and both are parameters for
/// a schema that chose others.
test "the types GraphQL does not have become the conventional scalars" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("i", Int),
    @moonmodel.Field::new("n", Big),
    @moonmodel.Field::new("f", Real),
    @moonmodel.Field::new("at", Stamp),
    @moonmodel.Field::new("raw", Bytes),
  ])
  assert_eq(
    written(model),
    (
      #|type T {
      #|  i: Int!
      #|  n: String!
      #|  f: Float!
      #|  at: DateTime!
      #|  raw: Base64!
      #|}
    ),
  )
  let (named, _s) = @sdl.of(model, stamp="Timestamp", bytes="Bytes")
  assert_true(named.contains("at: Timestamp!"))
  assert_true(named.contains("raw: Bytes!"))
}

///|
/// A list's element carries its own `!`, which is what a description with a
/// non-nullable element means. The outer mark is the field's.
test "a list marks its element and itself separately" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("tags", List(Text)),
    @moonmodel.Field::new("maybe", List(Text), required=false),
  ])
  assert_eq(
    written(model),
    (
      #|type T {
      #|  tags: [String!]!
      #|  maybe: [String!]
      #|}
    ),
  )
}

///|
test "a reference is the named type" {
  let model = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("buyer", Ref("User")),
  ])
  assert_eq(
    written(model),
    (
      #|type Order {
      #|  buyer: User!
      #|}
    ),
  )
}

///|
/// A mapping with open keys has no GraphQL type. Inventing a list of pairs
/// here would put a type in the schema nobody declared, so the field is
/// reported instead.
test "what GraphQL cannot type says so" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("ok", Text),
    @moonmodel.Field::new("meta", Dict(Text)),
    @moonmodel.Field::new("blob", Any),
  ])
  let (text, skipped) = @sdl.of(model)
  assert_eq(
    text,
    (
      #|type T {
      #|  ok: String!
      #|}
    ),
  )
  assert_eq(skipped.length(), 2)
  assert_eq(skipped[0].field, "meta")
  assert_true(skipped[0].why.contains("list of pairs"))
  assert_eq(skipped[1].field, "blob")
}

///|
/// Bounds are dropped, and that is right rather than a gap: GraphQL has no
/// place to put a range, and a schema that pretended otherwise would be
/// claiming a check the server does not make.
test "bounds do not reach the schema" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "n",
      Int,
      check=@moonmodel.Check::new(least=1.0, most=10.0),
    ),
  ])
  assert_eq(
    written(model),
    (
      #|type T {
      #|  n: Int!
      #|}
    ),
  )
}

///|
test "a document declares the scalars it used, once" {
  let user = @moonmodel.Model::new("User", [
    @moonmodel.Field::new("name", Text),
    @moonmodel.Field::new("joined", Stamp),
  ])
  let post = @moonmodel.Model::new("Post", [
    @moonmodel.Field::new("at", Stamp),
    @moonmodel.Field::new("author", Ref("User")),
  ])
  assert_eq(
    @sdl.document([user, post][:]),
    (
      #|scalar DateTime
      #|
      #|type User {
      #|  name: String!
      #|  joined: DateTime!
      #|}
      #|
      #|type Post {
      #|  at: DateTime!
      #|  author: User!
      #|}
      #|
    ),
  )
}

///|
test "an input type is the same shape under the other keyword" {
  let model = @moonmodel.Model::new("NewUser", [
    @moonmodel.Field::new("name", Text),
  ])
  let (text, _s) = @sdl.of(model, input=true)
  assert_eq(
    text,
    (
      #|input NewUser {
      #|  name: String!
      #|}
    ),
  )
}

///|
test "documentation becomes a description block" {
  let model = @moonmodel.Model::new(
    "User",
    [@moonmodel.Field::new("name", Text, doc="what to call them")],
    doc="somebody with an account",
  )
  assert_eq(
    written(model),
    (
      #|"""
      #|somebody with an account
      #|"""
      #|type User {
      #|  "what to call them"
      #|  name: String!
      #|}
    ),
  )
}
