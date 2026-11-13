// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The corpus the conformance harness reads. Between them these models use
// every `Type` and every member of `Check`, so a projection that drops one
// shows up as a difference in an engine that knows the format, not as a line
// in a comment.

///|
/// The models, in the order the harness reads them. References travel in one
/// direction so a reader can follow them: an `Order` names an `Account`, which
/// names an `Address`.
fn models() -> Array[@moonmodel.Model] {
  [account(), address(), post(), order(), invoice(), packet()]
}

///|
/// The model every other one is shaped after: a closed set, two open-ended
/// bounds, an optional-and-nullable pair, a list with both of its own bounds,
/// a reference, and a default on each side of the wire.
fn account() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "Account",
    [
      @moonmodel.Field::new(
        "id",
        @moonmodel.Big,
        doc="assigned by the database",
        check=@moonmodel.Check::new(unique=true),
      ),
      @moonmodel.Field::new(
        "name",
        @moonmodel.Text,
        check=@moonmodel.Check::new(shortest=1, longest=64),
      ),
      @moonmodel.Field::new(
        "email",
        @moonmodel.Text,
        required=false,
        nullable=true,
        check=@moonmodel.Check::new(format="email"),
      ),
      @moonmodel.Field::new(
        "age",
        @moonmodel.Int,
        required=false,
        nullable=true,
        check=@moonmodel.Check::new(least=0.0, most=150.0),
      ),
      @moonmodel.Field::new(
        "role",
        @moonmodel.Text,
        check=@moonmodel.Check::new(options=[
          Json::string("admin"),
          Json::string("member"),
        ]),
      ),
      @moonmodel.Field::new(
        "weight",
        @moonmodel.Real,
        required=false,
        default=Json::number(1.5),
        check=@moonmodel.Check::new(over=0.0, under=10.0),
      ),
      @moonmodel.Field::new(
        "tags",
        @moonmodel.List(@moonmodel.Text),
        required=false,
        check=@moonmodel.Check::new(shortest=1, longest=5, distinct=true),
      ),
      @moonmodel.Field::new("home", @moonmodel.Ref("Address")),
      @moonmodel.Field::new("created", @moonmodel.Stamp),
      @moonmodel.Field::new(
        "active",
        @moonmodel.Bool,
        required=false,
        default=Json::boolean(true),
      ),
    ],
    doc="somebody with an account",
  )
}

///|
/// A mapping with open keys and a model written where it stands, which are the
/// two shapes only the JSON family can carry.
fn address() -> @moonmodel.Model {
  @moonmodel.Model::new("Address", [
    @moonmodel.Field::new("city", @moonmodel.Text),
    @moonmodel.Field::new(
      "zip",
      @moonmodel.Text,
      required=false,
      check=@moonmodel.Check::new(pattern="[0-9]{5}"),
    ),
    @moonmodel.Field::new(
      "labels",
      @moonmodel.Dict(@moonmodel.Text),
      required=false,
    ),
    @moonmodel.Field::new("geo", @moonmodel.Nest(geo()), required=false),
  ])
}

///|
/// The model with no name of its own, written inside `Address`.
fn geo() -> @moonmodel.Model {
  @moonmodel.Model::new("", [
    @moonmodel.Field::new(
      "lat",
      @moonmodel.Real,
      check=@moonmodel.Check::new(least=-90.0, most=90.0),
    ),
    @moonmodel.Field::new(
      "lon",
      @moonmodel.Real,
      check=@moonmodel.Check::new(least=-180.0, most=180.0),
    ),
  ])
}

///|
/// A model that refers to itself, so a document has to write it twice: once at
/// the top and once where its own reference resolves.
fn post() -> @moonmodel.Model {
  @moonmodel.Model::new("Post", [
    @moonmodel.Field::new(
      "id",
      @moonmodel.Big,
      check=@moonmodel.Check::new(unique=true),
    ),
    @moonmodel.Field::new(
      "title",
      @moonmodel.Text,
      check=@moonmodel.Check::new(shortest=1, longest=120),
    ),
    @moonmodel.Field::new(
      "parent",
      @moonmodel.Ref("Post"),
      required=false,
      nullable=true,
    ),
  ])
}

///|
/// A name and a reference, where the name is one every SQL dialect reserves:
/// a table called `Order` is a syntax error until something quotes it.
fn order() -> @moonmodel.Model {
  @moonmodel.Model::new("Order", [
    @moonmodel.Field::new(
      "id",
      @moonmodel.Big,
      check=@moonmodel.Check::new(unique=true),
    ),
    @moonmodel.Field::new("buyer", @moonmodel.Ref("Account")),
    @moonmodel.Field::new(
      "total",
      @moonmodel.Real,
      check=@moonmodel.Check::new(least=0.0),
    ),
    @moonmodel.Field::new("placed", @moonmodel.Stamp),
  ])
}

///|
/// Columns whose names are reserved words, which is the other half of the same
/// problem: `order` and `group` are legal field names and illegal bare column
/// names. GraphQL has no quarrel with either.
fn invoice() -> @moonmodel.Model {
  @moonmodel.Model::new("Invoice", [
    @moonmodel.Field::new(
      "number",
      @moonmodel.Text,
      check=@moonmodel.Check::new(longest=32),
    ),
    @moonmodel.Field::new(
      "order",
      @moonmodel.Text,
      check=@moonmodel.Check::new(longest=32),
    ),
    @moonmodel.Field::new("group", @moonmodel.Text),
    @moonmodel.Field::new("total", @moonmodel.Real),
  ])
}

///|
/// Values a byte format lays out, and the two escapes: anything at all, and a
/// schema written out by hand.
fn packet() -> @moonmodel.Model {
  @moonmodel.Model::new("Packet", [
    @moonmodel.Field::new(
      "counter",
      @moonmodel.Wire(
        @moonmodel.Layout::new(
          @moonmodel.Int,
          bits=16,
          unsigned=true,
          order=@moonmodel.Order::Big,
        ),
      ),
    ),
    @moonmodel.Field::new(
      "ratio",
      @moonmodel.Wire(@moonmodel.Layout::new(@moonmodel.Real, bits=32)),
      required=false,
    ),
    @moonmodel.Field::new("payload", @moonmodel.Bytes, required=false),
    @moonmodel.Field::new("note", @moonmodel.Any, required=false),
    @moonmodel.Field::new("flags", flags(), required=false),
  ])
}

///|
/// A schema written out in full, which no projection reads inside.
fn flags() -> @moonmodel.Type {
  @moonmodel.Raw(
    Json::object(
      Map([
        ("type", Json::string("string")),
        ("pattern", Json::string("^[A-Z]+$")),
      ]),
    ),
  )
}
