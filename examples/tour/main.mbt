// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// One description of a customer, projected four ways. The same `Model` values
// reach every projection; nothing below is written twice.

///|
/// Everything a description can say, in one type.
///
/// Every variant of `Type` appears, and every field of `Check`, so the four
/// projections below each have to answer for all of them — including the
/// three none of them can carry.
fn customer() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "Customer",
    [
      @moonmodel.Field::new(
        "id",
        Big,
        doc="assigned at sign-up, never reused",
        check=@moonmodel.Check::new(unique=true),
      ),
      @moonmodel.Field::new(
        "name",
        Text,
        doc="what to call them",
        check=@moonmodel.Check::new(shortest=1, longest=64),
      ),
      @moonmodel.Field::new(
        "email",
        Text,
        check=@moonmodel.Check::new(format="email", pattern="^[^@]+@[^@]+$"),
      ),
      @moonmodel.Field::new(
        "age",
        Int,
        required=false,
        check=@moonmodel.Check::new(least=0.0, under=150.0),
      ),
      @moonmodel.Field::new(
        "balance",
        Real,
        default=Json::number(0.0),
        check=@moonmodel.Check::new(over=-1000.0, step=0.01),
      ),
      @moonmodel.Field::new("active", Bool, default=Json::boolean(true)),
      @moonmodel.Field::new("joined", Stamp),
      @moonmodel.Field::new("avatar", Bytes, required=false, nullable=true),
      @moonmodel.Field::new(
        "tier",
        Text,
        default=Json::string("free"),
        check=@moonmodel.Check::new(options=[
          Json::string("free"),
          Json::string("paid"),
          Json::string("staff"),
        ]),
      ),
      @moonmodel.Field::new(
        "tags",
        List(Text),
        check=@moonmodel.Check::new(distinct=true, longest=10),
      ),
      @moonmodel.Field::new("labels", Dict(Text)),
      @moonmodel.Field::new("home", Ref("Address")),
      @moonmodel.Field::new(
        "billed_to",
        Nest(
          @moonmodel.Model::new("", [
            @moonmodel.Field::new("name", Text),
            @moonmodel.Field::new("vat", Text, required=false),
          ]),
        ),
      ),
      @moonmodel.Field::new("notes", Any, required=false),
      @moonmodel.Field::new(
        "either",
        Raw({ "oneOf": [{ "type": "string" }, { "type": "integer" }] }),
      ),
    ],
    doc="somebody with an account",
  )
}

///|
fn address() -> @moonmodel.Model {
  @moonmodel.Model::new("Address", [
    @moonmodel.Field::new("line", Text),
    @moonmodel.Field::new("city", Text),
    @moonmodel.Field::new(
      "country",
      Text,
      check=@moonmodel.Check::new(shortest=2, longest=2),
    ),
  ])
}

///|
fn heading(text : String) -> Unit {
  println("")
  println("── " + text + " " + "─".repeat(70 - text.length()))
}

///|
fn main {
  let customer = customer()
  let address = address()

  // The description answers questions of its own, which is what makes it
  // worth having rather than four hand-written schemas.
  heading("the description")
  println("model      \{customer.name} — \{customer.doc}")
  println("fields     \{customer.fields.length()}")
  println("required   \{customer.required().join(", ")}")
  println("mentions   \{customer.mentions().join(", ")}")
  match customer.field("email") {
    Some(field) =>
      println("email      format \{field.check.format.unwrap_or("none")}")
    None => println("email      absent")
  }
  println("preset     empty: \{@moonmodel.check.is_empty()}")

  heading("JSON Schema 2020-12")
  let order = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("buyer", Ref("Customer")),
    @moonmodel.Field::new("total", Real),
  ])
  println(@json.of(order).stringify(indent=2))

  // A document carries what it refers to. `known` is where the referenced
  // descriptions come from; anything left unresolved stays a bare `$ref`.
  heading("one document, references resolved")
  println(@json.document(customer, known=[address]).stringify(indent=2))

  // The three OpenAPI dialects differ in three places, and this probe hits
  // all three: a nullable value, an open bound, and a reference.
  heading("the three OpenAPI dialects")
  let probe = @moonmodel.Model::new("Probe", [
    @moonmodel.Field::new(
      "score",
      Real,
      nullable=true,
      check=@moonmodel.Check::new(over=0.0),
    ),
    @moonmodel.Field::new("home", Ref("Address")),
  ])
  for
    one in [
      ("OpenAPI 3.1", @open.Dialect::OpenApi31),
      ("OpenAPI 3.0", @open.Dialect::OpenApi30),
      ("Swagger 2.0", @open.Dialect::Swagger20),
    ] {
    let (label, dialect) = one
    println("")
    println("\{label} — references point at \{dialect.at()}")
    println(@open.of(probe, dialect~).stringify(indent=2))
  }
  println("")
  let envelope = @open.schemas([address][:], dialect=Swagger20)
  println("2.0 keeps them under \{@open.Dialect::Swagger20.holder()}:")
  println(envelope.stringify(indent=2))

  // SQL loses the most, so it returns both halves: the columns it wrote and
  // the fields it could not.
  heading("SQL, three dialects")
  for
    one in [
      ("SQLite  ", @sql.Dialect::Sqlite),
      ("Postgres", @sql.Dialect::Postgres),
      ("MySQL   ", @sql.Dialect::Mysql),
    ] {
    let (label, dialect) = one
    let (columns, missing) = @sql.of(customer, dialect~)
    println(
      "\{label}  \{columns.length()} columns, \{missing.length()} fields without one",
    )
  }
  println("")
  println(@sql.table(customer, dialect=Postgres, name="customers"))
  println("")
  let (_columns, unstorable) = @sql.of(customer, dialect=Postgres)
  for one in unstorable {
    println("no column for \{one.field}: \{one.why}")
  }

  // GraphQL marks non-null with `!`, which folds required and nullable into
  // one mark, and has no type at all for two of these fields.
  heading("GraphQL SDL")
  let (text, untypeable) = @sdl.of(customer)
  println(text)
  println("")
  for one in untypeable {
    println("no type for \{one.field}: \{one.why}")
  }
  println("")
  println("an argument type is the same shape under the other keyword:")
  let (input, _) = @sdl.of(address, input=true)
  println(input)

  // The two scalars GraphQL lacks are declared once per document, and both
  // names are parameters for a schema that chose others.
  heading("a document declares its scalars")
  println(@sdl.document([address, customer][:], stamp="Timestamp"))
  println("the presets are \{@sdl.stamp} and \{@sdl.bytes}")
}
