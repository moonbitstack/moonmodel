// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A nullable value that is not a scalar, in the two older dialects. Neither
// has a null type, and 3.0 says a `$ref` may have no siblings, so "may be
// null" has to be said beside a wrapper rather than beside the pointer.

///|
/// The Schema Object of a one-field model, which is where a field's schema
/// lives in every dialect.
fn only(model : @moonmodel.Model, dialect : @open.Dialect) -> Json {
  match @open.of(model, dialect~) {
    Object(fields) =>
      match fields.get("properties") {
        Some(Object(properties)) =>
          match properties.get("x") {
            Some(one) => one
            None => Json::null()
          }
        _ => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn pointer() -> @moonmodel.Model {
  @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "x",
      @moonmodel.Ref("U"),
      required=false,
      nullable=true,
    ),
  ])
}

///|
test "3.1 is 2020-12, so a nullable reference is a choice" {
  assert_eq(only(pointer(), OpenApi31), {
    "anyOf": [{ "$ref": "#/components/schemas/U" }, { "type": "null" }],
  })
}

///|
test "3.0 gives the pointer a wrapper, because a $ref has no siblings" {
  assert_eq(only(pointer(), OpenApi30), {
    "allOf": [{ "$ref": "#/components/schemas/U" }],
    "nullable": true,
  })
}

///|
test "2.0 says the same with the extension its tooling reads" {
  assert_eq(only(pointer(), Swagger20), {
    "allOf": [{ "$ref": "#/definitions/U" }],
    "x-nullable": true,
  })
}

///|
test "a reference that may not be null is still a bare pointer" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", @moonmodel.Ref("U")),
  ])
  assert_eq(only(model, OpenApi30), { "$ref": "#/components/schemas/U" })
  assert_eq(only(model, Swagger20), { "$ref": "#/definitions/U" })
}

///|
test "a scalar still says nullable with a flag, not with a wrapper" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", @moonmodel.Text, nullable=true),
  ])
  assert_eq(only(model, OpenApi30), { "type": "string", "nullable": true })
  assert_eq(only(model, Swagger20), { "type": "string", "x-nullable": true })
}
