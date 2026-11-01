// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The same two models written by hand, which `main` holds the annotated ones to.
fn hand_home() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "Address",
    [
      @moonmodel.Field::new("city", Text),
      @moonmodel.Field::new(
        "zip",
        Text,
        check=@moonmodel.Check::new(pattern="^[0-9]{5}$"),
      ),
    ],
    doc="where somebody lives",
  )
}

///|
fn hand_user() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "User",
    [
      @moonmodel.Field::new(
        "id",
        Big,
        doc="assigned by the database",
        check=@moonmodel.Check::new(unique=true),
      ),
      @moonmodel.Field::new(
        "name",
        Text,
        check=@moonmodel.Check::new(shortest=1, longest=64),
      ),
      @moonmodel.Field::new(
        "email",
        Text,
        required=false,
        nullable=true,
        check=@moonmodel.Check::new(format="email"),
      ),
      @moonmodel.Field::new(
        "age",
        Int,
        required=false,
        nullable=true,
        check=@moonmodel.Check::new(least=0.0, most=150.0),
      ),
      @moonmodel.Field::new(
        "role",
        Text,
        check=@moonmodel.Check::new(options=["Admin", "Member", "Guest"]),
      ),
      @moonmodel.Field::new(
        "weight",
        Real,
        required=false,
        default=1.0,
        check=@moonmodel.Check::new(over=0.0),
      ),
      @moonmodel.Field::new("home", Ref("Address")),
      @moonmodel.Field::new(
        "tags",
        List(Text),
        check=@moonmodel.Check::new(longest=8, distinct=true),
      ),
      @moonmodel.Field::new("joined", Stamp),
    ],
    doc="somebody with an account",
  )
}
