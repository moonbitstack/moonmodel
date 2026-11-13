# moonmodel

One field description; JSON Schema, OpenAPI, SQL and GraphQL SDL are its
projections.

MoonBit already turns a struct into JSON and back — `#derive(ToJson)`,
`#derive(FromJson)`, `@json`'s `JsonPath`. That is not what this is for.

A service describes the same field four times over: once to check a request,
once to document it, once to store it, once to serve it. Describe it once
instead:

```moonbit
#model.derive(doc="somebody with an account")
pub struct User {
  #model.field(unique=true)
  id : Int64
  #model.field(longest="64")
  name : String
  age : Int32?
  home : Address
}

#model.derive
pub struct Address {
  city : String
}
```

`User::describe()` is then the description, and every projection takes it. The
method returns a `Model`, which is data and nothing else, so the same value can
be written out by hand — at run time, or from a generator:

```moonbit
let user = @moonmodel.Model::new(
  "User",
  [
    @moonmodel.Field::new("id", Big, check=@moonmodel.Check::new(unique=true)),
    @moonmodel.Field::new("name", Text, check=@moonmodel.Check::new(longest=64)),
    @moonmodel.Field::new("age", Int, required=false, nullable=true),
    @moonmodel.Field::new("home", Ref("Address")),
  ],
  doc="somebody with an account",
)

let address = @moonmodel.Model::new("Address", [
  @moonmodel.Field::new("city", Text),
])
```

## Four projections

JSON Schema 2020-12 is the one that loses least: a 64-bit integer is
`format: int64`, an optional-and-nullable field is a union with `null`, and a
field that names another model is a reference. A reference that may also be
null becomes a choice between the two, because a pointer has no type of its own
to widen.

```moonbit
assert_eq(@json.of(user), {
  "type": "object",
  "title": "User",
  "description": "somebody with an account",
  "properties": {
    "id": { "type": "integer", "format": "int64" },
    "name": { "type": "string", "maxLength": 64 },
    "age": { "type": ["integer", "null"], "format": "int32" },
    "home": { "$ref": "#/$defs/Address" },
  },
  "required": ["id", "name", "home"],
})
```

An OpenAPI 3.0 Schema Object says the same in its own dialect: nullability is a
keyword rather than a type, and a reference points into the components.

```moonbit
assert_eq(@open.of(user, dialect=@open.Dialect::OpenApi30), {
  "type": "object",
  "title": "User",
  "description": "somebody with an account",
  "properties": {
    "id": { "type": "integer", "format": "int64" },
    "name": { "type": "string", "maxLength": 64 },
    "age": { "type": "integer", "format": "int32", "nullable": true },
    "home": { "$ref": "#/components/schemas/Address" },
  },
  "required": ["id", "name", "home"],
})
```

SQL keeps the columns and drops the rest: a field that names another model
needs its own table, so `home` is reported rather than quietly turned into
text. `sql.of` returns both halves — the columns it wrote and the fields it
could not. A table or column whose name the dialect reserves is quoted, so a
model called `Order` with a field called `group` is still a table.

```moonbit
assert_eq(@sql.table(user, dialect=@sql.Dialect::Postgres), (
  #|CREATE TABLE User (
  #|  id BIGINT NOT NULL UNIQUE,
  #|  name TEXT NOT NULL CHECK (length(name) <= 64),
  #|  age INTEGER
  #|)
))
```

GraphQL has no 64-bit integer — its `Int` is 32 bits by specification — so
`id` is carried as a `String`, and `!` folds "required" and "not null" into one
mark.

```moonbit
let (sdl, skipped) = @sdl.of(user)
assert_eq(sdl, (
  #|"""
  #|somebody with an account
  #|"""
  #|type User {
  #|  id: String!
  #|  name: String!
  #|  age: Int
  #|  home: Address!
  #|}
))
assert_eq(skipped.length(), 0)
```

## Annotations

`cmd/derive` reads the annotations at build time. In `moon.mod`:

<!-- nocheck -->
```
rule(name: "model", command: "moonx moonbitstack/moonmodel/cmd/derive@0.1.3 -C \"$mod_dir\" \"$input\" -o \"$output\"")
```

and in the `moon.pkg` of the package holding the structs:

<!-- nocheck -->
```
dev_build(rule: "model", input: "models.mbt", output: "models.g.mbt")
formatter(ignore: [ "models.g.mbt" ])
import { "moonbitstack/moonmodel" }
```

| Annotation | Goes on | Means |
|:--:|:--:|:--|
| `#model.derive` | a struct | generate `T::describe()`; `name=` and `doc=` set the model's name and text |
| `#model.derive` | an enum | a field of this type is text limited to its constructors |
| `#model.field` | a field | everything below |
| `#model.skip` | a field | leave it out |

| `#model.field` key | Means |
|:--:|:--|
| `name`, `doc` | the field's name in the model, and its text |
| `kind` | the type, when the field's own says nothing: `bool`, `int`, `big`, `real`, `text`, `bytes`, `stamp`, `any`; or a width — `int8`, `int16`, `uint16`, `uint64`, `float32` — with `-be` after it for a big-endian number and `-ref` for one written by reference |
| `model` | the type is the model of this name |
| `required`, `nullable` | override what the type says |
| `default` | a default, read by the field's type, so `"0"` on a `String` is text |
| `least`, `most`, `over`, `under`, `step` | numeric bounds, as strings, since an annotation has no numbers |
| `shortest`, `longest` | the length of text or a list |
| `pattern`, `format` | a text field's shape |
| `option` | one allowed value, repeated |
| `distinct`, `unique` | a list's items differ; no two records share the value |

A field with no annotation is named after itself and required. `T?` may be left
out and may be null. A field with a default may be left out. `Array[T]` is a
list, `Map[String, T]` a dictionary, an annotated struct a `Ref`, and `@pkg.T` a
`Ref` to the model named `T`. A type that says nothing is refused at build time,
with the file and line, and so is a `kind=` word the vocabulary does not have.

The generated file is a `Model::new` call per type, which is why the two ways
of saying it agree: `moon run src/examples/annotations` holds an annotated
model to the same model written by hand, and `moon run src/examples/tour` runs
all four projections and a check on one description that uses every part of the
vocabulary.

## Install

```bash
moon add moonbitstack/moonmodel
```

In `moon.pkg`, import the root package and whichever projections you need:

```
import {
  "moonbitstack/moonmodel",
  "moonbitstack/moonmodel/json",
}
```

## Packages

|  Package  | Writes | Costs you |
|:--:|:--|:--|
| `moonmodel` | the description itself | nothing — no dependencies |
| `moonmodel/json` | JSON Schema 2020-12 | the root package |
| `moonmodel/open` | an OpenAPI Schema Object, three dialects | the root package and the JSON writer |
| `moonmodel/sql` | columns and `CREATE TABLE`, three dialects | the root package |
| `moonmodel/sdl` | GraphQL SDL | the root package |
| `moonmodel/verify` | a verdict on an instance | the JSON writer and a validator |

A program that wants OpenAPI does not link the SQL writer.

`moon run src/cmd/sheet` prints one description as a single JSON document —
every field, four times over, with what each projection could not carry — which
is what the project's front page is typeset from.

## The description

A `Field` carries a name, a `Type`, two separate flags, documentation, a
default and a `Check`.

|  Type  | Means |
|:--:|:--|
| `Bool` `Int` `Big` `Real` `Text` `Bytes` `Stamp` | the scalars; `Big` is 64-bit, `Stamp` an instant |
| `List(Type)` `Dict(Type)` | a sequence, and a mapping with open keys |
| `Ref(String)` | another model, by name, so descriptions refer to each other without nesting |
| `Nest(Model)` | a model written where it stands, for the one with no name of its own |
| `Wire(Layout)` | a value with the exact layout a byte format writes: a width, a sign, a byte order and a reference mark |
| `Any` | anything at all |
| `Raw(Json)` | a schema written out in full, for what this vocabulary cannot say |

**`required` and `nullable` are two questions.** The first asks whether the
key has to be there, the second whether its value may be null. JSON Schema
keeps them apart, SQL's `NOT NULL` is the second alone, and GraphQL's `!` is
both at once — folding them into one would leave at least one projection
guessing.

`Check` holds the bounds, under names that mean the same thing everywhere:

|  Field  | Means |
|:--:|:--|
| `least` `most` | closed bounds |
| `over` `under` | open bounds — JSON Schema's `exclusiveMinimum` and `exclusiveMaximum` |
| `step` | `multipleOf` |
| `shortest` `longest` | a string's characters or a list's items |
| `pattern` `format` | a regular expression, and a named shape such as `email` |
| `options` | the values allowed, if the set is closed — any Json, not only text |
| `distinct` | one list's items must differ |
| `unique` | no two records carry the same value — only SQL can state this |

`min` and `max` are avoided on purpose: they mean different things in the four
targets.

## Values a byte format writes

A document says what a value is. A format that writes bytes also fixes how wide
it is, whether it carries a sign, which byte comes first, and whether it is
written where it stands or as an offset to somewhere else. `Layout` carries
those four, so one description serves a codec as well as a schema:

```moonbit
let counter = @moonmodel.Field::new(
  "count",
  @moonmodel.Wire(
    @moonmodel.Layout::new(
      @moonmodel.Int,
      bits=16,
      unsigned=true,
      order=@moonmodel.Order::Big,
    ),
  ),
)
assert_eq(counter.kind.word().unwrap_or("none"), "uint16-be")
assert_eq(@moonmodel.Type::of_word("uint16-be").unwrap_or(@moonmodel.Any), counter.kind)
```

|  Part  | Means |
|:--:|:--|
| `kind` | the value's own type: `Bool`, `Int`, `Big`, `Real`, `Text`, `Bytes`, `Stamp` |
| `bits` | the width a format fixes — 8, 16, 32 or 64 — or absent when the format's own table decides |
| `unsigned` | there is no sign bit |
| `order` | `Order::Little` or `Order::Big`: which byte of a number comes first |
| `reference` | the value is an offset into the buffer rather than written in place |

A layout also has a word, and the word reads back: `uint16`, `int32-be`,
`text-ref`. `Type::word` writes it and `Type::of_word` reads it, which is the
same vocabulary `#model.field(kind=…)` takes — so an annotation and a
description state a layout in exactly one way.

The width is the one part a document can state, so JSON Schema and OpenAPI
write it as `format` — `int8`, `uint16`, `float32` — beside the type. SQL
narrows the column where the dialect has a narrower type, widens it where the
sign does not fit, and SQLite keeps its one integer type. GraphQL's `Int` is
signed and 32 bits, so a wider or unsigned number is carried as a `String`, the
way a 64-bit integer already is. A byte order and a reference mark are left to
the format that writes the bytes: no document has a keyword for them.

## Checking an instance

The description is what an instance is checked against. It is written out as
JSON Schema and read by a validator that knows the specification, so the schema
a reader sees and the schema a request is held to are the same one:

```moonbit
let checker = @verify.schema(user, known=[address]) catch {
  error => abort("the description is not a schema: \{error}")
}
let good : Json = { "id": 1, "name": "ada", "home": { "city": "Kyoto" } }
let no_id : Json = { "name": "ada", "home": { "city": "Kyoto" } }
assert_eq(checker.valid(good), true)
assert_eq(checker.valid(no_id), false)
let faults = checker.faults(no_id)
assert_eq(faults[0].keyword, "required")
```

|  Call  | Answers |
|:--:|:--|
| `schema(model, known=…)` | the model as a `Schema`, with every model it refers to |
| `valid(model, instance, known=…)` | whether the instance conforms, reading the description on the way |
| `faults(model, instance, known=…)` | every reason it does not, each with `at` — where in the instance — and the keyword that refused it |

`schema` reads the description once, and the `Schema` it gives answers for as
many instances as there are. A `Ref` to a model the call did not hand over is
refused by name: a validator asked about a `$ref` that points nowhere can only
answer no to everything, which would blame the instance.

## What each projection cannot carry

Every projection reports what it dropped rather than inventing a shape for it
or failing. `sql.of` and `sdl.of` return the fields they skipped along with
the reason; the JSON Schema and OpenAPI writers drop nothing but `unique`,
which is about the collection rather than the value.

`Raw` is the escape hatch, and it is the last thing to reach for: nothing
reads inside it, so a projection can only pass it through or report that it
cannot.

|  | Cannot carry |
|:--:|:--|
| JSON Schema | `unique`, which is about the collection and not the value; a layout's byte order and reference mark |
| OpenAPI 2.0 | nullable has no keyword — written as `x-nullable`, which is what its tooling reads |
| OpenAPI 2.0 / 3.0 | an open bound is a boolean beside the closed one, not a number |
| SQL | `Dict`, `Nest` and `Ref` need their own table; `List` is a column only in Postgres; `Any` and `Raw` have no type; `pattern` is spelled three different ways; a byte order and a reference mark are not a column; a name that only MySQL or PostgreSQL reserves is left bare, since the words quoted are the ones SQLite refuses |
| GraphQL | `Dict`, `Nest`, `Any` and `Raw` have no type; no bound of any kind reaches the schema; a 64-bit or unsigned-wide number becomes a `String` |

GraphQL has no date and no byte string, so both are custom scalars —
`DateTime` and `Base64` by default, and `document` declares them once. A
64-bit integer is not GraphQL's `Int`, which the specification fixes at 32
bits, so it is carried as a `String`.

## Configuration priority

Every parameter has a public preset, so changing one is a parameter away:
`@sdl.stamp`, `@sdl.bytes`, `@json.defs`, `@moonmodel.check`.

## Where a description comes from

A description is plain data with no builder hidden behind it, so it comes from
wherever it is easiest to keep right: the annotations at the declaration,
`Model::new` at run time, or a generator that writes those calls out. The three
meet at `Model`, and nothing downstream can tell which one a value came from.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
