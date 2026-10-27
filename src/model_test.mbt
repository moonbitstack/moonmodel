// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The description answers three questions on its own. Everything else about
// it is checked by the four projections, which is the point of having it.

///|
fn user() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "User",
    [
      @moonmodel.Field::new("id", Big, check=@moonmodel.Check::new(unique=true)),
      @moonmodel.Field::new("name", Text),
      @moonmodel.Field::new("age", Int, required=false),
      @moonmodel.Field::new("avatar", Bytes, nullable=true),
      @moonmodel.Field::new("home", Ref("Address")),
      @moonmodel.Field::new("posts", List(Ref("Post"))),
      @moonmodel.Field::new("seen", Dict(Ref("Address"))),
    ],
    doc="somebody with an account",
  )
}

///|
/// Only the fields whose key has to be there. A nullable one is still
/// required — the two questions stay apart, which is the whole reason the
/// description keeps both.
test "required lists the keys that must be present" {
  assert_eq(user().required(), ["id", "name", "avatar", "home", "posts", "seen"])
}

///|
/// Every name a reference points at, at any depth and without repeats. A
/// document writer needs it to know what else to carry.
test "mentions finds references at any depth" {
  assert_eq(user().mentions(), ["Address", "Post"])
  let flat = @moonmodel.Model::new("Flat", [@moonmodel.Field::new("n", Int)])
  assert_eq(flat.mentions(), [])
}

///|
test "a field is found by name" {
  let model = user()
  assert_eq(model.field("age").unwrap().kind, Int)
  assert_eq(model.field("nothing"), None)
}

///|
/// The preset is empty and anything given makes it not. A projection reads
/// this to decide between writing nothing and writing an empty object.
test "the empty bound is the preset" {
  assert_true(@moonmodel.check.is_empty())
  assert_true(@moonmodel.Check::new().is_empty())
  assert_false(@moonmodel.Check::new(least=0.0).is_empty())
  assert_false(@moonmodel.Check::new(options=["a"]).is_empty())
  assert_false(@moonmodel.Check::new(distinct=true).is_empty())
  assert_false(@moonmodel.Check::new(unique=true).is_empty())
}

///|
/// Both ways of writing one give the same value, which is what makes the
/// record and its named constructor interchangeable.
test "the constructor and the record update agree" {
  assert_eq(@moonmodel.Check::new(least=1.0, longest=8), {
    ..@moonmodel.check,
    least: Some(1.0),
    longest: Some(8),
  })
}

///|
/// Same for a field: the defaults are the common case, so one written with
/// none of them equals one written with all of them spelled out.
test "a field's defaults are the common case" {
  assert_eq(@moonmodel.Field::new("n", Int), {
    name: "n",
    kind: Int,
    required: true,
    nullable: false,
    doc: "",
    default: None,
    check: @moonmodel.check,
  })
}
