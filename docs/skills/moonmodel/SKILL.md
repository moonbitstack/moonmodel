---
name: moonmodel
description: Describe a MoonBit type once and project it to JSON Schema 2020-12, an OpenAPI Schema Object, SQL DDL or GraphQL SDL, or hold an instance to that description. Use it when the same fields are written several times over — to check a request, to document it, to store it, to serve it — or when a byte format needs a width and a byte order that no schema keywords can state.
---

# moonmodel

`moon add moonbitstack/moonmodel`, then import the root package and only the
projections in use. Each projection is a package of its own, so a program that
serves OpenAPI does not link the SQL writer.

```moonbit
import {
  "moonbitstack/moonmodel",
  "moonbitstack/moonmodel/json",
}
```

## Describe a type

A description is plain data: `Model::new` and one `Field::new` per field. There
is no builder and no hidden state, so it can come from a literal, a loop over a
table, or generated code without anything downstream noticing.

```moonbit
let signup = @moonmodel.Model::new("Signup", [
  @moonmodel.Field::new("id", Big),
  @moonmodel.Field::new(
    "name",
    Text,
    check=@moonmodel.Check::new(shortest=1, longest=64),
  ),
  @moonmodel.Field::new(
    "age",
    Int,
    required=false,
    check=@moonmodel.Check::new(least=0.0, under=150.0),
  ),
])
```

`Type` is a closed set — `Bool Int Big Real Text Bytes Stamp`, `List(T)`,
`Dict(T)`, `Ref("Other")`, `Nest(model)`, `Wire(layout)`, `Any`, `Raw(json)` —
so a projection can answer for every one of them. With the `#model`
annotations wired as a `dev_build` rule, `Signup::describe()` returns this same
value and the struct holds the only copy of the field list; the generated file
is a `Model::new` call per type, so the two routes are interchangeable.

## Project it

JSON Schema takes `at=` for where a `Ref` resolves and `title=` for whether the
model's own name is written; both are parameters because a fragment and a
document want different answers.

```moonbit
assert_eq(@json.of(signup, title=false), {
  "type": "object",
  "properties": {
    "id": { "type": "integer", "format": "int64" },
    "name": { "type": "string", "minLength": 1, "maxLength": 64 },
    "age": {
      "type": "integer",
      "format": "int32",
      "minimum": 0,
      "exclusiveMaximum": 150,
    },
  },
  "required": ["id", "name"],
})
```

SQL and GraphQL are the two that lose fields. Both return what they could not
carry, with the reason, instead of inventing a shape for it: `sql.of` and
`sdl.of` give `(items, skipped)`, and `sql.table` writes the DDL from the same
columns.

```moonbit
assert_eq(@sql.table(signup, dialect=@sql.Dialect::Postgres, name="signups"), (
  #|CREATE TABLE signups (
  #|  id BIGINT NOT NULL,
  #|  name TEXT NOT NULL CHECK (length(name) <= 64 AND length(name) >= 1),
  #|  age INTEGER CHECK (age >= 0 AND age < 150)
  #|)
))

let (sdl, skipped) = @sdl.of(signup)
assert_eq(sdl, (
  #|type Signup {
  #|  id: String!
  #|  name: String!
  #|  age: Int
  #|}
))
assert_eq(skipped.length(), 0)
```

`id` is a `String` in SDL because GraphQL's `Int` is 32 bits by specification.
`@sdl.document([signup][:])` writes the `DateTime` and `Base64` scalar
declarations a document needs when it uses them; both names are parameters.

## Hold an instance to it

The description is written out as JSON Schema and read by a validator that knows
the specification, so the schema a reader sees and the schema a request is held
to cannot diverge. `schema` reads the description once and answers for as many
instances as there are; `valid` and `faults` do it in one call each.

```moonbit
let checker = @verify.schema(signup) catch {
  error => abort("the description is not a schema: \{error}")
}
let good : Json = { "id": 1, "name": "ada", "age": 36 }
let bad : Json = { "id": 1, "name": "ada", "age": 200 }
assert_eq(checker.valid(good), true)
assert_eq(checker.valid(bad), false)
let faults = checker.faults(bad)
assert_eq(faults[0].at, "/age")
assert_eq(faults[0].keyword, "exclusiveMaximum")
```

## Rules that catch people out

- **`required` and `nullable` are two questions.** The first is whether the key
  must be present, the second whether its value may be `null`. Set them
  separately; GraphQL's `!` folds both, so a field that is required and nullable
  loses its `!` there and nothing in the SDL says which way it went.
- **Bounds are `least`/`most` (closed) and `over`/`under` (open),** never
  `min`/`max`: those two words mean different things in the four targets.
  `shortest`/`longest` bound text and lists alike.
- **A reference does not resolve itself.** Pass every model a `Ref` names to
  `@verify.schema(model, known=[...])` and `@json.document(model, known=[...])`.
  A name that is missing is refused by name rather than treated as "anything",
  because a validator answering about a `$ref` that points nowhere can only
  blame the instance.
- **`unique` is not `distinct`.** `distinct` is one list's items differing
  (`uniqueItems`); `unique` is no two records sharing a value, which only SQL
  can state — the other three drop it.
- **`Stamp` is a moment.** JSON Schema and OpenAPI write it as
  `format: date-time`, which validates a string and converts nothing. Use
  `Check::format` when a date is text being checked rather than a date being
  parsed.
- **`Big` is 64-bit.** JSON numbers past 2^53 do not survive a double, so a
  field that carries one belongs in `Big` and is written by the caller, not
  by whatever produced the float.
- **`Raw(json)` is the last resort.** Nothing reads inside it: a projection
  either passes it through or reports that it cannot carry it.
