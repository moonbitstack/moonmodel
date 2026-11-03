// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Code without spaces, line breaks or the trailing commas the printer adds when
/// it wraps a call, so a test can look for one call written on one line.
fn flat(code : String) -> String {
  let out = StringBuilder()
  for c in code {
    if c != ' ' && c != '\n' {
      out.write_char(c)
    }
  }
  out.to_string().replace_all(old=",)", new=")").replace_all(old=",]", new="]")
}

///|
fn generate(source : String) -> String raise {
  flat(@gen.render(Derive::{ }, [("models.mbt", source)]))
}

///|
fn refused(source : String) -> String {
  try {
    ignore(generate(source))
    ""
  } catch {
    e => "\{e}"
  }
}

///|
fn has(code : String, part : String) -> Bool {
  code.contains(flat(part))
}

///|
test "field types pick their kind, and `T?` is optional and nullable" {
  let source =
    #|#model.derive
    #|pub struct User {
    #|  id : Int64
    #|  name : String
    #|  age : Int32?
    #|  score : Double
    #|  active : Bool
    #|  photo : Bytes
    #|  extra : Json
    #|  tags : Array[String]
    #|  counts : Map[String, Int]
    #|}
  let code = generate(source)
  assert_true(has(code, "pub fn User::describe() -> @moonmodel.Model"))
  assert_true(has(code, "@moonmodel.Field::new(\"id\", Big)"))
  assert_true(has(code, "@moonmodel.Field::new(\"name\", Text)"))
  assert_true(
    has(
      code, "@moonmodel.Field::new(\"age\", Int, required=false, nullable=true)",
    ),
  )
  assert_true(has(code, "@moonmodel.Field::new(\"score\", Real)"))
  assert_true(has(code, "@moonmodel.Field::new(\"active\", Bool)"))
  assert_true(has(code, "@moonmodel.Field::new(\"photo\", Bytes)"))
  assert_true(has(code, "@moonmodel.Field::new(\"extra\", Any)"))
  assert_true(has(code, "@moonmodel.Field::new(\"tags\", List(Text))"))
  assert_true(has(code, "@moonmodel.Field::new(\"counts\", Dict(Int))"))
}

///|
test "a private struct gets a private describe" {
  let source =
    #|#model.derive
    #|struct Hidden {
    #|  x : Int
    #|}
  let code = generate(source)
  assert_true(has(code, "fn Hidden::describe()"))
  assert_false(has(code, "pub fn Hidden::describe()"))
}

///|
test "names, docs and every bound come through" {
  let source =
    #|#model.derive(name="Person", doc="somebody")
    #|pub struct User {
    #|  #model.field(name="user_id", doc="the key", unique=true)
    #|  id : Int64
    #|  #model.field(shortest="1", longest="64", pattern="^[a-z]+$")
    #|  name : String
    #|  #model.field(least="0", most="150")
    #|  age : Int32
    #|  #model.field(over="0.5", under="1.5", step="0.25")
    #|  ratio : Double
    #|  #model.field(format="email")
    #|  mail : String
    #|  #model.field(distinct=true, longest="8")
    #|  tags : Array[String]
    #|}
  let code = generate(source)
  assert_true(has(code, "\"Person\""))
  assert_true(has(code, "doc=\"somebody\""))
  assert_true(
    has(
      code, "@moonmodel.Field::new(\"user_id\", Big, doc=\"the key\", check=@moonmodel.Check::new(unique=true))",
    ),
  )
  assert_true(
    has(
      code, "check=@moonmodel.Check::new(shortest=1, longest=64, pattern=\"^[a-z]+$\")",
    ),
  )
  assert_true(has(code, "check=@moonmodel.Check::new(least=0.0, most=150.0)"))
  assert_true(
    has(code, "check=@moonmodel.Check::new(over=0.5, under=1.5, step=0.25)"),
  )
  assert_true(has(code, "check=@moonmodel.Check::new(format=\"email\")"))
  assert_true(
    has(code, "check=@moonmodel.Check::new(longest=8, distinct=true)"),
  )
}

///|
test "a default makes a field optional, read by the field's own type" {
  let source =
    #|#model.derive
    #|pub struct T {
    #|  #model.field(default="0")
    #|  a : String
    #|  #model.field(default="7")
    #|  b : Int
    #|  #model.field(default="1.5")
    #|  c : Double
    #|  #model.field(default="true")
    #|  d : Bool
    #|  #model.field(default="[1, \"x\", null, {\"k\": false}]")
    #|  e : Json
    #|  #model.field(default="3", required=true)
    #|  f : Int
    #|}
  let code = generate(source)
  assert_true(
    has(code, "Field::new(\"a\", Text, required=false, default=\"0\")"),
  )
  assert_true(has(code, "Field::new(\"b\", Int, required=false, default=7)"))
  assert_true(has(code, "Field::new(\"c\", Real, required=false, default=1.5)"))
  assert_true(
    has(code, "Field::new(\"d\", Bool, required=false, default=true)"),
  )
  assert_true(has(code, "default=[1, \"x\", null, { \"k\": false }]"))
  assert_true(has(code, "Field::new(\"f\", Int, default=3)"))
}

///|
test "required and nullable can say otherwise than the type" {
  let source =
    #|#model.derive
    #|pub struct T {
    #|  #model.field(required=true)
    #|  a : Int?
    #|  #model.field(nullable=false)
    #|  b : Int?
    #|  #model.field(required=false)
    #|  c : Int
    #|  #model.field(nullable=true)
    #|  d : Int
    #|}
  let code = generate(source)
  assert_true(has(code, "Field::new(\"a\", Int, nullable=true)"))
  assert_true(has(code, "Field::new(\"b\", Int, required=false)"))
  assert_true(has(code, "Field::new(\"c\", Int, required=false)"))
  assert_true(has(code, "Field::new(\"d\", Int, nullable=true)"))
}

///|
test "a model refers to another, here or in another package" {
  let source =
    #|#model.derive(name="Place")
    #|pub struct Address {
    #|  city : String
    #|}
    #|
    #|#model.derive
    #|pub struct User {
    #|  home : Address
    #|  homes : Array[Address]
    #|  work : Address?
    #|  other : @places.Office
    #|  #model.field(model="Thing")
    #|  thing : Thing
    #|}
  let code = generate(source)
  assert_true(has(code, "Field::new(\"home\", Ref(\"Place\"))"))
  assert_true(has(code, "Field::new(\"homes\", List(Ref(\"Place\")))"))
  assert_true(
    has(
      code, "Field::new(\"work\", Ref(\"Place\"), required=false, nullable=true)",
    ),
  )
  assert_true(has(code, "Field::new(\"other\", Ref(\"Office\"))"))
  assert_true(has(code, "Field::new(\"thing\", Ref(\"Thing\"))"))
}

///|
test "an annotated enum is a closed set of text" {
  let source =
    #|#model.derive
    #|pub enum Role {
    #|  Admin
    #|  Guest
    #|}
    #|
    #|#model.derive
    #|pub struct User {
    #|  role : Role
    #|  #model.field(option="red", option="blue")
    #|  colour : String
    #|  #model.field(option="1", option="2")
    #|  level : Int
    #|}
  let code = generate(source)
  assert_true(
    has(
      code, "Field::new(\"role\", Text, check=@moonmodel.Check::new(options=[\"Admin\", \"Guest\"]))",
    ),
  )
  assert_true(has(code, "options=[\"red\", \"blue\"]"))
  assert_true(has(code, "options=[1, 2]"))
  assert_false(has(code, "Role::describe"))
}

///|
test "a skipped field is left out, and `kind=` overrides the type" {
  let source =
    #|#model.derive
    #|pub struct T {
    #|  #model.skip
    #|  cache : Int
    #|  #model.field(kind="stamp")
    #|  at : String
    #|}
  let code = generate(source)
  assert_false(has(code, "\"cache\""))
  assert_true(has(code, "Field::new(\"at\", Stamp)"))
}

///|
test "a struct without the annotation is left alone" {
  assert_false(generate("struct Plain {\n  x : Int\n}").contains("describe"))
}

///|
test "what cannot be described is refused, with where" {
  let cases : Array[(String, String)] = [
    ("#model.derive\nstruct T {\n  x : Unknown\n}", "has no type of its own"),
    (
      "#model.derive\nstruct T {\n  #model.skip\n  x : Int\n}", "declares no field",
    ),
    (
      "struct T {\n  #model.field(name=\"a\")\n  x : Int\n}", "has no `#model.derive`",
    ),
    ("#model.derive\n#model.derive\nstruct T {\n  x : Int\n}", "written twice"),
    (
      "#model.derive\nstruct T {\n  #model.field(name=\"a\")\n  #model.field(name=\"b\")\n  x : Int\n}",
      "written twice",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(name=\"a\")\n  #model.skip\n  x : Int\n}",
      "takes no `#model.field`",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(name=\"a\")\n  x : Int\n  #model.field(name=\"a\")\n  y : Int\n}",
      "declares field `a` twice",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(longest=\"1\")\n  x : Int\n}", "bounds text or a list",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(least=\"1\")\n  x : String\n}",
      "bounds a number",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(pattern=\"a\")\n  x : Int\n}", "is for text",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(distinct=true)\n  x : Int\n}", "is for a list",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(least=\"x\")\n  x : Int\n}", "is not a number",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(longest=\"1.5\")\n  x : String\n}",
      "is not a whole number",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(default=\"yes\")\n  x : Bool\n}",
      "is not true or false",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(default=\"{\")\n  x : Json\n}",
      "is not JSON",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(kind=\"money\")\n  x : Int\n}",
      "is not a type",
    ),
    (
      "#model.derive\nstruct T {\n  #model.field(kind=\"int\", model=\"A\")\n  x : Int\n}",
      "not both",
    ),
    ("#model.field(name=\"a\")\nstruct T {\n  x : Int\n}", "goes on a field"),
    ("#model.derive\nfn f() -> Unit {\n}", "goes on a struct or an enum"),
    (
      "#model.derive\nstruct T {\n  #model.other\n  x : Int\n}", "not a moonmodel field annotation",
    ),
    ("#model.derive(type=\"x\")\nstruct T {\n  x : Int\n}", "does not parse"),
  ]
  for one in cases {
    let (source, want) = one
    let got = refused(source)
    assert_true(got.contains(want), msg="\{source}\nwanted \{want}\ngot \{got}")
  }
}

///|
test "the place in an error is the annotation's" {
  let got = refused(
    "#model.derive\nstruct T {\n  #model.field(least=\"x\")\n  x : Int\n}",
  )
  assert_true(got.contains("models.mbt:3:"))
}

///|
/// A width, a byte order and a reference mark belong to the type, so an
/// annotation states them in the same `kind=` word the description reads back:
/// one table, read from both ends.
test "a kind word states the layout a byte format needs" {
  let source =
    #|#model.derive
    #|pub struct Counter {
    #|  #model.field(kind="uint16")
    #|  count : Int
    #|  #model.field(kind="int32-be", least="0")
    #|  size : Int
    #|  #model.field(kind="text-ref")
    #|  name : String
    #|  #model.field(kind="float32")
    #|  ratio : Double
    #|  #model.field(kind="uint16", default="7")
    #|  limit : Int
    #|}
  let code = generate(source)
  assert_true(has(code, "@moonmodel.Layout::new(Int, bits=16, unsigned=true)"))
  assert_true(
    has(
      code, "@moonmodel.Layout::new(Int, bits=32, order=@moonmodel.Order::Big)",
    ),
  )
  assert_true(has(code, "check=@moonmodel.Check::new(least=0.0)"))
  assert_true(has(code, "@moonmodel.Layout::new(Text, reference=true)"))
  assert_true(has(code, "@moonmodel.Layout::new(Real, bits=32)"))
  // A default is read by the kind inside the layout, so `"7"` is a number.
  assert_true(has(code, "default=7"))
}

///|
/// A word the vocabulary does not have is refused where it is written, and the
/// message says what a word of this kind looks like: a typo should not become
/// a type nobody meant.
test "a kind word that is not a type is refused" {
  let message = refused(
    (
      #|#model.derive
      #|pub struct T {
      #|  #model.field(kind="uint24")
      #|  x : Int
      #|}
    ),
  )
  assert_true(message.contains("uint24"))
  assert_true(message.contains("uint16"))
}

///|
/// A bound follows the kind inside the layout: a width says how the number is
/// written, not that it is not a number.
test "a bound follows the kind inside a layout" {
  let message = refused(
    (
      #|#model.derive
      #|pub struct T {
      #|  #model.field(kind="uint16", shortest="1")
      #|  x : Int
      #|}
    ),
  )
  assert_true(message.contains("bounds text or a list"))
}
