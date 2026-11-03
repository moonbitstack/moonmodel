// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A subset of the official JSON Schema test suite, run through this library's
// entry rather than through the validator directly.
//
// The suite states a schema and instances that must and must not conform to
// it. A model cannot state every schema the suite has — it always writes an
// object, and it has no `allOf`, no `not`, no `propertyNames` — so what is
// taken here is the cases whose schema a model can state exactly, transcribed
// with the suite's own data and verdicts. Each group names the file it came
// from so a reader can check the transcription against the source.
//
// Left out on purpose, and why:
//
// * `type.json` cases whose schema is not an object — a model always writes
//   `"type": "object"`.
// * The cases of `required.json` and `properties.json` whose instance is not
//   an object. The suite requires those to conform, because its schema says
//   nothing about the type; a model does say it, so the verdicts would differ
//   by design rather than by mistake.

///|
/// One case: the model that states the suite's schema, the instance, and the
/// verdict the suite requires.
priv struct Case {
  source : String
  group : String
  name : String
  model : @moonmodel.Model
  data : Json
  valid : Bool
}

///|
fn Case::new(
  source : String,
  group : String,
  name : String,
  model : @moonmodel.Model,
  data : Json,
  valid : Bool,
) -> Case {
  { source, group, name, model, data, valid, }
}

///|
/// `type.json` — "object type matches objects".
fn objects() -> Array[Case] {
  let source = "type.json"
  let group = "object type matches objects"
  let model = @moonmodel.Model::new("", [])
  [
    Case::new(
      source,
      group,
      "an integer is not an object",
      model,
      Json::number(1.0),
      false,
    ),
    Case::new(
      source,
      group,
      "a float is not an object",
      model,
      Json::number(1.1),
      false,
    ),
    Case::new(
      source,
      group,
      "a string is not an object",
      model,
      Json::string("foo"),
      false,
    ),
    Case::new(
      source,
      group,
      "an object is an object",
      model,
      Json::object(Map([])),
      true,
    ),
    Case::new(
      source,
      group,
      "an array is not an object",
      model,
      Json::array([]),
      false,
    ),
    Case::new(
      source,
      group,
      "a boolean is not an object",
      model,
      Json::boolean(true),
      false,
    ),
    Case::new(
      source,
      group,
      "null is not an object",
      model,
      Json::null(),
      false,
    ),
  ]
}

///|
/// `enum.json` — "enums in properties": one closed set that may be left out,
/// one that may not.
fn enums() -> Array[Case] {
  let source = "enum.json"
  let group = "enums in properties"
  let model = @moonmodel.Model::new("", [
    @moonmodel.Field::new(
      "foo",
      Text,
      required=false,
      check=@moonmodel.Check::new(options=[Json::string("foo")]),
    ),
    @moonmodel.Field::new(
      "bar",
      Text,
      check=@moonmodel.Check::new(options=[Json::string("bar")]),
    ),
  ])
  [
    Case::new(
      source,
      group,
      "both properties are valid",
      model,
      { "foo": Json::string("foo"), "bar": Json::string("bar") },
      true,
    ),
    Case::new(
      source,
      group,
      "wrong foo value",
      model,
      { "foo": Json::string("foot"), "bar": Json::string("bar") },
      false,
    ),
    Case::new(
      source,
      group,
      "wrong bar value",
      model,
      { "foo": Json::string("foo"), "bar": Json::string("bart") },
      false,
    ),
    Case::new(
      source,
      group,
      "missing optional property is valid",
      model,
      { "bar": Json::string("bar") },
      true,
    ),
    Case::new(
      source,
      group,
      "missing required property is invalid",
      model,
      { "foo": Json::string("foo") },
      false,
    ),
    Case::new(
      source,
      group,
      "missing all properties is invalid",
      model,
      Json::object(Map([])),
      false,
    ),
  ]
}

///|
/// `required.json` — "required validation": the two cases whose instance is an
/// object.
fn required() -> Array[Case] {
  let source = "required.json"
  let group = "required validation"
  let model = @moonmodel.Model::new("", [
    @moonmodel.Field::new("foo", Any),
    @moonmodel.Field::new("bar", Any, required=false),
  ])
  [
    Case::new(
      source,
      group,
      "present required property is valid",
      model,
      { "foo": Json::number(1.0) },
      true,
    ),
    Case::new(
      source,
      group,
      "non-present required property is invalid",
      model,
      { "bar": Json::number(1.0) },
      false,
    ),
  ]
}

///|
/// `required.json` — "required default validation" and "required with empty
/// array": a field with no `required` written is not one.
fn optional() -> Array[Case] {
  let model = @moonmodel.Model::new("", [
    @moonmodel.Field::new("foo", Any, required=false),
  ])
  [
    Case::new(
      "required.json",
      "required default validation",
      "not required by default",
      model,
      Json::object(Map([])),
      true,
    ),
    Case::new(
      "required.json",
      "required with empty array",
      "property not required",
      model,
      Json::object(Map([])),
      true,
    ),
  ]
}

///|
/// `properties.json` — "object properties validation": the four cases whose
/// instance is an object.
fn properties() -> Array[Case] {
  let source = "properties.json"
  let group = "object properties validation"
  let model = @moonmodel.Model::new("", [
    @moonmodel.Field::new("foo", Int, required=false),
    @moonmodel.Field::new("bar", Text, required=false),
  ])
  [
    Case::new(
      source,
      group,
      "both properties present and valid is valid",
      model,
      { "foo": Json::number(1.0), "bar": Json::string("baz") },
      true,
    ),
    Case::new(
      source,
      group,
      "one property invalid is invalid",
      model,
      { "foo": Json::number(1.0), "bar": Json::object(Map([])) },
      false,
    ),
    Case::new(
      source,
      group,
      "both properties invalid is invalid",
      model,
      { "foo": Json::array([]), "bar": Json::object(Map([])) },
      false,
    ),
    Case::new(
      source,
      group,
      "doesn't invalidate other properties",
      model,
      { "quux": Json::array([]) },
      true,
    ),
  ]
}

///|
fn cases() -> Array[Case] {
  let out = []
  out.append(objects())
  out.append(enums())
  out.append(required())
  out.append(optional())
  out.append(properties())
  out
}

///|
/// Every transcribed case gives the verdict the suite requires. The mismatches
/// are collected first so a failure names the case rather than the first
/// assertion the test happened to reach.
test "the transcribed cases give the suite's verdicts" {
  let wrong = []
  for one in cases() {
    if @verify.valid(one.model, one.data) != one.valid {
      wrong.push("\{one.source} / \{one.group} / \{one.name}")
    }
  }
  assert_eq(wrong, [])
}

///|
/// A front door: the subset is meant to grow case by case, and a group that
/// quietly lost its cases would still pass the test above.
test "the subset has the cases it says it has" {
  assert_eq(cases().length(), 21)
}
