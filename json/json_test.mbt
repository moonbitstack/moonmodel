// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The projection is checked against JSON Schema 2020-12 itself: each keyword
// is the one the specification names, spelled as it spells it. Where a type
// has no direct counterpart — bytes, a date — the test pins the convention
// the whole ecosystem uses, because a convention nobody wrote down is the
// thing that drifts.

///|
/// A model with one field of each kind, used wherever the shape of a type is
/// what matters.
fn plain(kind : @moonmodel.Type) -> Json {
  let model = @moonmodel.Model::new("T", [@moonmodel.Field::new("x", kind)])
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
test "every type writes the keywords 2020-12 names" {
  assert_eq(plain(Bool), { "type": "boolean" })
  assert_eq(plain(Int), { "type": "integer", "format": "int32" })
  assert_eq(plain(Big), { "type": "integer", "format": "int64" })
  assert_eq(plain(Real), { "type": "number" })
  assert_eq(plain(Text), { "type": "string" })
  // JSON has no bytes; a base64 string wearing a format is what every schema
  // in the wild writes, OpenAPI included.
  assert_eq(plain(Bytes), { "type": "string", "format": "byte" })
  assert_eq(plain(Stamp), { "type": "string", "format": "date-time" })
  // The empty schema accepts anything. There has never been a "type": "any".
  assert_eq(plain(Any), {})
}

///|
test "a list and a mapping nest their element type" {
  assert_eq(plain(List(Text)), {
    "type": "array",
    "items": { "type": "string" },
  })
  assert_eq(plain(Dict(Int)), {
    "type": "object",
    "additionalProperties": { "type": "integer", "format": "int32" },
  })
  assert_eq(plain(List(List(Bool))), {
    "type": "array",
    "items": { "type": "array", "items": { "type": "boolean" } },
  })
}

///|
test "a reference points where it was told to" {
  assert_eq(plain(Ref("User")), { "$ref": "#/$defs/User" })
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("x", Ref("User")),
  ])
  let other = @json.of(model, at="#/components/schemas/")
  assert_eq(other, {
    "type": "object",
    "title": "T",
    "properties": { "x": { "$ref": "#/components/schemas/User" } },
    "required": ["x"],
  })
}

///|
/// `required` is a list on the object, `null` is a type on the value, and the
/// two are set independently. A field can be required and nullable, which is
/// "the key must be there and may say null".
test "required and nullable are separate" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("a", Text),
    @moonmodel.Field::new("b", Text, required=false),
    @moonmodel.Field::new("c", Text, nullable=true),
    @moonmodel.Field::new("d", Text, required=false, nullable=true),
  ])
  assert_eq(@json.of(model), {
    "type": "object",
    "title": "T",
    "properties": {
      "a": { "type": "string" },
      "b": { "type": "string" },
      "c": { "type": ["string", "null"] },
      "d": { "type": ["string", "null"] },
    },
    "required": ["a", "c"],
  })
}

///|
test "the bounds are written under the names the draft gives them" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "n",
      Real,
      check=@moonmodel.Check::new(least=1.0, most=10.0, step=0.5),
    ),
    @moonmodel.Field::new(
      "m",
      Real,
      check=@moonmodel.Check::new(over=0.0, under=1.0),
    ),
    @moonmodel.Field::new(
      "s",
      Text,
      check=@moonmodel.Check::new(
        shortest=1,
        longest=64,
        pattern="^[a-z]+$",
        format="email",
      ),
    ),
    @moonmodel.Field::new(
      "k",
      Text,
      check=@moonmodel.Check::new(options=["red", "green"]),
    ),
  ])
  assert_eq(@json.of(model), {
    "type": "object",
    "title": "T",
    "properties": {
      "n": {
        "type": "number",
        "minimum": 1.0,
        "maximum": 10.0,
        "multipleOf": 0.5,
      },
      "m": {
        "type": "number",
        "exclusiveMinimum": 0.0,
        "exclusiveMaximum": 1.0,
      },
      "s": {
        "type": "string",
        "minLength": 1.0,
        "maxLength": 64.0,
        "pattern": "^[a-z]+$",
        "format": "email",
      },
      "k": { "type": "string", "enum": ["red", "green"] },
    },
    "required": ["n", "m", "s", "k"],
  })
}

///|
/// One pair of names for strings, another for arrays, chosen by the type
/// already written. Getting this wrong produces a schema that validates
/// everything.
test "length bounds follow the type they are bounding" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "tags",
      List(Text),
      check=@moonmodel.Check::new(shortest=1, longest=5, distinct=true),
    ),
  ])
  assert_eq(@json.of(model), {
    "type": "object",
    "title": "T",
    "properties": {
      "tags": {
        "type": "array",
        "items": { "type": "string" },
        "minItems": 1.0,
        "maxItems": 5.0,
        "uniqueItems": true,
      },
    },
    "required": ["tags"],
  })
}

///|
/// A type that names its own format keeps it. A check saying otherwise is the
/// caller contradicting the type, and the type wins.
test "a type's own format is not overwritten" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "at",
      Stamp,
      check=@moonmodel.Check::new(format="email"),
    ),
  ])
  assert_eq(plain_of(model, "at"), { "type": "string", "format": "date-time" })
}

///|
test "the description and the default come through" {
  let model = @moonmodel.Model::new(
    "User",
    [
      @moonmodel.Field::new(
        "name",
        Text,
        doc="what to call them",
        default=Json::string("anonymous"),
      ),
    ],
    doc="somebody with an account",
  )
  assert_eq(@json.of(model), {
    "type": "object",
    "title": "User",
    "description": "somebody with an account",
    "properties": {
      "name": {
        "type": "string",
        "description": "what to call them",
        "default": "anonymous",
      },
    },
    "required": ["name"],
  })
}

///|
/// A document gathers every model reached, through one hop or several, and
/// says which dialect it is.
test "a document carries the models it reaches" {
  let address = @moonmodel.Model::new("Address", [
    @moonmodel.Field::new("city", Text),
  ])
  let user = @moonmodel.Model::new("User", [
    @moonmodel.Field::new("home", Ref("Address")),
  ])
  let order = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("buyer", Ref("User")),
    @moonmodel.Field::new("items", List(Ref("Line"))),
  ])
  let line = @moonmodel.Model::new("Line", [@moonmodel.Field::new("sku", Text)])
  let whole = @json.document(order, known=[user, address, line])
  guard whole is Object(fields) else { fail("not an object") }
  assert_eq(
    fields.get("$schema"),
    Some(Json::string("https://json-schema.org/draft/2020-12/schema")),
  )
  guard fields.get("$defs") is Some(Object(defs)) else { fail("no $defs") }
  // User through one hop, Address through two, Line through a list.
  // A map's keys come out in no stated order, so compare as a set.
  for name in ["Address", "Line", "User"] {
    assert_true(defs.get(name) is Some(_))
  }
  assert_eq(defs.length(), 3)
}

///|
/// A reference to something the writer was not given stays a reference. A
/// schema naming a type defined elsewhere is ordinary, and this package
/// cannot know whether the reader has it.
test "a model that is not to hand is left as a reference" {
  let order = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("buyer", Ref("User")),
  ])
  let whole = @json.document(order)
  guard whole is Object(fields) else { fail("not an object") }
  assert_true(fields.get("$defs") is None)
  guard fields.get("properties") is Some(Object(properties)) else {
    fail("no properties")
  }
  assert_eq(properties.get("buyer"), Some({ "$ref": "#/$defs/User" }))
}

///|
fn plain_of(model : @moonmodel.Model, name : String) -> Json {
  match @json.of(model) {
    Object(fields) =>
      match fields.get("properties") {
        Some(Object(properties)) =>
          match properties.get(name) {
            Some(one) => one
            None => Json::null()
          }
        _ => Json::null()
      }
    _ => Json::null()
  }
}

///|
/// A model with no name of its own is written where it stands. There is
/// nothing to hoist it under and nothing that could point at it.
test "a nested model is written in place" {
  let model = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new(
      "ship_to",
      Nest(
        @moonmodel.Model::new("", [
          @moonmodel.Field::new("city", Text),
          @moonmodel.Field::new("zip", Text, required=false),
        ]),
      ),
    ),
  ])
  assert_eq(@json.of(model), {
    "type": "object",
    "title": "Order",
    "properties": {
      "ship_to": {
        "type": "object",
        "properties": {
          "city": { "type": "string" },
          "zip": { "type": "string" },
        },
        "required": ["city"],
      },
    },
    "required": ["ship_to"],
  })
}

///|
/// What the vocabulary cannot say goes through as it stands. Nothing reads
/// inside it, which is the point and also the reason to reach for it last.
test "a hand-written schema passes through" {
  let written : Json = {
    "allOf": [{ "$ref": "#/$defs/A" }, { "$ref": "#/$defs/B" }],
  }
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("both", Raw(written)),
  ])
  assert_eq(@json.of(model), {
    "type": "object",
    "title": "T",
    "properties": { "both": written },
    "required": ["both"],
  })
}

///|
/// A closed set of numbers is as ordinary as one of names, so the values are
/// Json and reach the schema unchanged.
test "a closed set may hold any json" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "n",
      Int,
      check=@moonmodel.Check::new(options=[Json::number(1), Json::number(2)]),
    ),
  ])
  guard @json.of(model) is Object(fields) else { fail("not an object") }
  guard fields.get("properties") is Some(Object(properties)) else {
    fail("no properties")
  }
  guard properties.get("n") is Some(Object(one)) else { fail("no n") }
  assert_eq(
    one.get("enum"),
    Some(Json::array([Json::number(1), Json::number(2)])),
  )
}

///|
/// A nested model has no name, but what it refers to still has to be carried.
test "a document reaches references inside a nested model" {
  let inner = @moonmodel.Model::new("", [
    @moonmodel.Field::new("home", Ref("Address")),
  ])
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("at", Nest(inner)),
  ])
  assert_eq(model.mentions(), ["Address"])
}
