// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The entry is a convenience, not a second validator: every answer below is
// one the specification already defines for the schema this library writes
// down. What is worth pinning here is the shape of the answer — where a fault
// points, and which keyword refused the value.

///|
fn user() -> @moonmodel.Model {
  @moonmodel.Model::new("User", [
    @moonmodel.Field::new(
      "name",
      Text,
      check=@moonmodel.Check::new(shortest=1, longest=8),
    ),
    @moonmodel.Field::new(
      "age",
      Int,
      required=false,
      check=@moonmodel.Check::new(least=0.0, most=150.0),
    ),
  ])
}

///|
fn address() -> @moonmodel.Model {
  @moonmodel.Model::new("Address", [@moonmodel.Field::new("city", Text)])
}

///|
/// A model that points at another one, which is what `known` is for.
fn resident() -> @moonmodel.Model {
  @moonmodel.Model::new("Resident", [
    @moonmodel.Field::new("name", Text),
    @moonmodel.Field::new("home", Ref("Address"), required=false),
  ])
}

///|
test "an instance that conforms is valid" {
  assert_true(
    @verify.valid(user(), { "name": "Ada", "age": Json::number(36.0) }),
  )
  // A field that may be left out may be left out; being left out is not the
  // same question as being null, which this field may not be.
  assert_true(@verify.valid(user(), { "name": "Ada" }))
  assert_false(@verify.valid(user(), { "name": "Ada", "age": Json::null() }))
}

///|
/// A key that has to be there and is not: the fault points at the object that
/// should have carried it, and names the keyword that asked for it.
test "a missing key is a fault at the object" {
  let faults = @verify.faults(user(), { "age": Json::number(36.0) })
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].at, "")
  assert_eq(faults[0].keyword, "required")
  assert_true(faults[0].message.contains("name"))
}

///|
/// A bound is checked against the field it was written on, so the answer says
/// which field to look at rather than stopping at "no".
test "a bound is a fault at the field" {
  let faults = @verify.faults(user(), {
    "name": "Ada",
    "age": Json::number(151.0),
  })
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].at, "/age")
  assert_eq(faults[0].keyword, "maximum")
  let short = @verify.faults(user(), { "name": "" })
  assert_eq(short[0].at, "/name")
  assert_eq(short[0].keyword, "minLength")
}

///|
/// A reference is checked through the model it names, which the document
/// carries under `$defs` — so a fault lands at the field inside the other
/// model, not merely at the one that pointed there.
test "a referenced model is checked where it is used" {
  let instance : Json = {
    "name": "Ada",
    "home": Json::object({ "city": Json::number(1.0) }),
  }
  assert_false(@verify.valid(resident(), instance, known=[address()]))
  let faults = @verify.faults(resident(), instance, known=[address()])
  assert_eq(faults[0].at, "/home/city")
  assert_eq(faults[0].keyword, "type")
}

///|
/// The closed set a `Check` carries is an `enum`, and a value outside it is
/// refused with the field's path.
test "the allowed values are an enum" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "tier",
      Text,
      check=@moonmodel.Check::new(options=[
        Json::string("free"),
        Json::string("paid"),
      ]),
    ),
  ])
  assert_true(@verify.valid(model, { "tier": "paid" }))
  let faults = @verify.faults(model, { "tier": "staff" })
  assert_eq(faults[0].at, "/tier")
  assert_eq(faults[0].keyword, "enum")
}

///|
/// An instance is whatever the core library parsed, including values no model
/// describes: a description narrows objects, and an array is not one.
test "an instance that is not an object never conforms" {
  assert_false(@verify.valid(user(), Json::array([])))
  assert_false(@verify.valid(user(), Json::null()))
  assert_false(@verify.valid(user(), Json::string("Ada")))
}

///|
/// A reference the document cannot resolve is a defect in the description, and
/// it is reported as one: a validator can only answer "no" to every instance
/// of a schema whose `$ref` points nowhere, which would blame the instance.
test "a reference to a model the call did not carry is refused by name" {
  let mut missing = ""
  ignore(@verify.schema(resident())) catch {
    @verify.Missing(name~) => missing = name
    _ => ()
  }
  assert_eq(missing, "Address")
}

///|
/// A model that names itself is the one reference a document resolves without
/// being handed anything: the document carries it under `$defs` as well.
test "a model that refers to itself is checkable on its own" {
  let node = @moonmodel.Model::new("Node", [
    @moonmodel.Field::new("next", Ref("Node"), required=false),
  ])
  assert_true(@verify.valid(node, Json::object(Map([]))))
}

///|
/// `Check::pattern` goes out as JSON Schema's `pattern`, which is an ECMA-262 expression
/// matched anywhere in the string unless it is anchored.
test "a pattern is a regular expression the value has to match" {
  let slug = @moonmodel.Model::new("Page", [
    @moonmodel.Field::new(
      "slug",
      Text,
      check=@moonmodel.Check::new(pattern="^[a-z0-9]+(?:-[a-z0-9]+)*$"),
    ),
  ])
  assert_true(@verify.valid(slug, { "slug": "moon-stack-2" }))
  let faults = @verify.faults(slug, { "slug": "Moon Stack" })
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].at, "/slug")
  assert_eq(faults[0].keyword, "pattern")
}

///|
/// The README's own example: its model, the two instances it checks, and the
/// keyword its one fault names. The reference to `Address` is resolved from
/// `known`, which is what lets the nested object be checked rather than
/// waved through.
test "the model the README checks answers what the README shows" {
  let user = @moonmodel.Model::new(
    "User",
    [
      @moonmodel.Field::new("id", Big, check=@moonmodel.Check::new(unique=true)),
      @moonmodel.Field::new(
        "name",
        Text,
        check=@moonmodel.Check::new(longest=64),
      ),
      @moonmodel.Field::new("age", Int, required=false, nullable=true),
      @moonmodel.Field::new("home", Ref("Address")),
    ],
    doc="somebody with an account",
  )
  let address = @moonmodel.Model::new("Address", [
    @moonmodel.Field::new("city", Text),
  ])
  let checker = @verify.schema(user, known=[address]) catch {
    error => abort("the description is not a schema: \{error}")
  }
  let good : Json = { "id": 1, "name": "ada", "home": { "city": "Kyoto" } }
  let no_id : Json = { "name": "ada", "home": { "city": "Kyoto" } }
  assert_eq(checker.valid(good), true)
  assert_eq(checker.valid(no_id), false)
  let faults = checker.faults(no_id)
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].keyword, "required")
}
