// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A nullable value that is not a scalar. `type: [t, "null"]` only works when
// the schema has a `type` of its own; a reference is a pointer, and 2020-12
// resolves it beside its siblings rather than through them, so the choice has
// to be written out or the nullability is silently lost.

///|
/// The property of a one-field model, which is where a field's schema lives.
fn only(model : @moonmodel.Model) -> Json {
  match @json.of(model) {
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
test "a nullable reference is a choice between the model and null" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "x",
      @moonmodel.Ref("U"),
      required=false,
      nullable=true,
    ),
  ])
  assert_eq(only(model), {
    "anyOf": [{ "$ref": "#/$defs/U" }, { "type": "null" }],
  })
}

///|
test "a reference that may not be null stays a bare pointer" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", @moonmodel.Ref("U")),
  ])
  assert_eq(only(model), { "$ref": "#/$defs/U" })
}

///|
test "a nested model is widened the same way, and keeps its own fields" {
  let inner = @moonmodel.Model::new("", [
    @moonmodel.Field::new("y", @moonmodel.Text),
  ])
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", @moonmodel.Nest(inner), nullable=true),
  ])
  // A model written where it stands has a type of its own — an object — so it
  // is widened by listing both, which is the form a scalar takes too.
  assert_eq(only(model), {
    "type": ["object", "null"],
    "properties": { "y": { "type": "string" } },
    "required": ["y"],
  })
}

///|
test "anything at all already takes null, so nothing is added" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", @moonmodel.Any, nullable=true),
  ])
  assert_eq(only(model), {})
}

///|
test "a description and a default stay beside the widened type" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "x",
      @moonmodel.Ref("U"),
      nullable=true,
      doc="who it belongs to",
    ),
  ])
  assert_eq(only(model), {
    "description": "who it belongs to",
    "anyOf": [{ "$ref": "#/$defs/U" }, { "type": "null" }],
  })
}

///|
test "a document says the same, and still carries the model it names" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", @moonmodel.Ref("U"), nullable=true),
  ])
  let known = @moonmodel.Model::new("U", [
    @moonmodel.Field::new("y", @moonmodel.Text),
  ])
  let document = @json.document(model, known=[known])
  assert_eq(document, {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "title": "T",
    "properties": {
      "x": { "anyOf": [{ "$ref": "#/$defs/U" }, { "type": "null" }] },
    },
    "required": ["x"],
    "$defs": {
      "U": {
        "type": "object",
        "title": "U",
        "properties": { "y": { "type": "string" } },
        "required": ["y"],
      },
    },
  })
}
