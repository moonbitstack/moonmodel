# moonmodel

One field description; JSON Schema, OpenAPI, SQL and GraphQL SDL are its
projections.

MoonBit already turns a struct into JSON and back — `derive(ToJson)`,
`derive(FromJson)`, `@json`'s `JsonPath`. That is not what this is for.

The same concept is currently written four times over: moonapi's schema
fields, moonorm's model columns, moongql's SDL fields, moonschema's documents.
Write it once instead:

```moonbit
let user = @moonmodel.Model::new(
  "User",
  [
    @moonmodel.Field::new("id", Big, check=@moonmodel.Check::new(unique=true)),
    @moonmodel.Field::new("name", Text, check=@moonmodel.Check::new(longest=64)),
    @moonmodel.Field::new("age", Int, required=false),
    @moonmodel.Field::new("home", Ref("Address")),
  ],
  doc="somebody with an account",
)

// JSON Schema 2020-12, an OpenAPI Schema Object, CREATE TABLE, type User { … }
println(@json.of(user).stringify(indent=2))
println(@open.of(user, dialect=OpenApi30).stringify(indent=2))
println(@sql.table(user, dialect=Postgres))
println(@sdl.document([user][:]))
```

`moon run src/examples/tour` runs all four on one description that uses every
part of the vocabulary.

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
| `moonmodel/open` | an OpenAPI Schema Object, three dialects | the root package |
| `moonmodel/sql` | columns and `CREATE TABLE`, three dialects | the root package |
| `moonmodel/sdl` | GraphQL SDL | the root package |

A program that wants OpenAPI does not link the SQL writer.

## The description

A `Field` carries a name, a `Type`, two separate flags, documentation, a
default and a `Check`.

|  Type  | Means |
|:--:|:--|
| `Bool` `Int` `Big` `Real` `Text` `Bytes` `Stamp` | the scalars; `Big` is 64-bit, `Stamp` an instant |
| `List(Type)` `Dict(Type)` | a sequence, and a mapping with open keys |
| `Ref(String)` | another model, by name, so descriptions refer to each other without nesting |
| `Nest(Model)` | a model written where it stands, for the one with no name of its own |
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

## What each projection cannot carry

Every projection reports what it dropped rather than inventing a shape for it
or failing. `sql.of` and `sdl.of` return the fields they skipped along with
the reason; the JSON Schema and OpenAPI writers drop nothing but `unique`.

`Raw` is the escape hatch, and it is the last thing to reach for: nothing
reads inside it, so a projection can only pass it through or report that it
cannot.

|  | Cannot carry |
|:--:|:--|
| JSON Schema | `unique`, which is about the collection and not the value |
| OpenAPI 2.0 | nullable has no keyword — written as `x-nullable`, which is what its tooling reads |
| OpenAPI 2.0 / 3.0 | an open bound is a boolean beside the closed one, not a number |
| SQL | `Dict`, `Nest` and `Ref` need their own table; `List` is a column only in Postgres; `Any` and `Raw` have no type; `pattern` is spelled three different ways |
| GraphQL | `Dict`, `Nest`, `Any` and `Raw` have no type; no bound of any kind reaches the schema |

GraphQL has no date and no byte string, so both are custom scalars —
`DateTime` and `Base64` by default, and `document` declares them once. A
64-bit integer is not GraphQL's `Int`, which the specification fixes at 32
bits, so it is carried as a `String`.

## Configuration priority

Every parameter has a public preset, so changing one is a parameter away:
`@sdl.stamp`, `@sdl.bytes`, `@json.defs`, `@moonmodel.check`.

## Where a description comes from

Written by hand today. `mctl` generating one from a struct definition comes
next, and `moonast` — annotations at the declaration, read at build time —
after that. The description has to accept all three, so it is plain data with
no builder hidden behind it.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
