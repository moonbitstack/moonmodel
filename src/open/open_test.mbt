// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Three dialects, and the three places the older two cannot say what 2020-12
// says. Each is checked in both directions: what the old one writes, and
// that the new one still writes the 2020-12 form.

///|
fn one(field : @moonmodel.Field, dialect : @open.Dialect) -> Json {
  let model = @moonmodel.Model::new("T", [field])
  match @open.of(model, dialect~) {
    Object(fields) =>
      match fields.get("properties") {
        Some(Object(properties)) =>
          match properties.get(field.name) {
            Some(one) => one
            None => Json::null()
          }
        _ => Json::null()
      }
    _ => Json::null()
  }
}

///|
/// 3.1 is 2020-12, so a nullable value is a two-element type. 3.0 has a flag.
/// 2.0 has nothing in the specification and uses the extension its tooling
/// reads — writing nothing would turn an optional value into a required one.
test "each dialect says nullable its own way" {
  let field = @moonmodel.Field::new("x", Text, nullable=true)
  assert_eq(one(field, OpenApi31), { "type": ["string", "null"] })
  assert_eq(one(field, OpenApi30), { "type": "string", "nullable": true })
  assert_eq(one(field, Swagger20), { "type": "string", "x-nullable": true })
}

///|
/// An open bound is a number in 2020-12 and a boolean beside the closed one
/// in draft 4. Getting this wrong makes the bound mean its own value.
test "an exclusive bound changes shape for the older dialects" {
  let field = @moonmodel.Field::new(
    "n",
    Real,
    check=@moonmodel.Check::new(over=0.0, under=100.0),
  )
  assert_eq(one(field, OpenApi31), {
    "type": "number",
    "exclusiveMinimum": 0.0,
    "exclusiveMaximum": 100.0,
  })
  assert_eq(one(field, OpenApi30), {
    "type": "number",
    "minimum": 0.0,
    "exclusiveMinimum": true,
    "maximum": 100.0,
    "exclusiveMaximum": true,
  })
  assert_eq(one(field, Swagger20), {
    "type": "number",
    "minimum": 0.0,
    "exclusiveMinimum": true,
    "maximum": 100.0,
    "exclusiveMaximum": true,
  })
}

///|
/// 2.0 keeps named schemas at the top level; 3.x moved them one level down.
test "a reference points where the dialect keeps its schemas" {
  let field = @moonmodel.Field::new("home", Ref("Address"))
  assert_eq(one(field, OpenApi31), { "$ref": "#/components/schemas/Address" })
  assert_eq(one(field, OpenApi30), { "$ref": "#/components/schemas/Address" })
  assert_eq(one(field, Swagger20), { "$ref": "#/definitions/Address" })
}

///|
test "the envelope matches the dialect" {
  let user = @moonmodel.Model::new("User", [@moonmodel.Field::new("name", Text)])
  let three = @open.schemas([user][:], dialect=OpenApi31)
  guard three is Object(outer) else { fail("not an object") }
  guard outer.get("components") is Some(Object(components)) else {
    fail("no components")
  }
  assert_true(components.get("schemas") is Some(_))
  let two = @open.schemas([user][:], dialect=Swagger20)
  guard two is Object(flat) else { fail("not an object") }
  assert_true(flat.get("definitions") is Some(_))
  assert_true(flat.get("components") is None)
}

///|
/// Everything the three dialects agree on comes through unchanged, which is
/// most of it — the point of 3.1 adopting 2020-12.
test "what the dialects agree on is left alone" {
  let field = @moonmodel.Field::new(
    "s",
    Text,
    check=@moonmodel.Check::new(shortest=1, longest=8, pattern="^a"),
  )
  let same : Json = {
    "type": "string",
    "minLength": 1.0,
    "maxLength": 8.0,
    "pattern": "^a",
  }
  assert_eq(one(field, OpenApi31), same)
  assert_eq(one(field, OpenApi30), same)
  assert_eq(one(field, Swagger20), same)
}

///|
/// A schema filed under its own name needs no title saying the same thing.
/// A standalone one keeps it, which is why this is a parameter rather than a
/// rule — and it is what makes the output match moonapi's byte for byte.
test "a title is written standalone and left out under a key" {
  let user = @moonmodel.Model::new("User", [@moonmodel.Field::new("name", Text)])
  guard @open.of(user) is Object(alone) else { fail("not an object") }
  assert_eq(alone.get("title"), Some(Json::string("User")))
  guard @open.of(user, title=false) is Object(quiet) else {
    fail("not an object")
  }
  assert_eq(quiet.get("title"), None)
  guard @open.schemas([user][:]) is Object(outer) else { fail("not an object") }
  guard outer.get("components") is Some(Object(components)) else {
    fail("no components")
  }
  guard components.get("schemas") is Some(Object(named)) else {
    fail("no schemas")
  }
  guard named.get("User") is Some(Object(one)) else { fail("no User") }
  assert_eq(one.get("title"), None)
}
