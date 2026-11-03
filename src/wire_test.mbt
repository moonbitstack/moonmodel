// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A layout has one word and a word has one layout, which is what lets an
// annotation state what a byte format needs and lets a reader of the
// description check that the two agree.

///|
/// Every word the vocabulary has, the plain kinds and the widths alike.
fn words() -> Array[String] {
  [
    "bool", "int", "big", "real", "text", "bytes", "stamp", "any", "int8", "int16",
    "int32", "int64", "uint8", "uint16", "uint32", "uint64", "float32", "float64",
  ]
}

///|
test "every word names a type, and that type names the word" {
  for word in words() {
    let kind = @moonmodel.Type::of_word(word).unwrap()
    assert_eq(kind.word().unwrap(), word)
  }
}

///|
/// A word is read as written: the case and the spaces around it are the
/// caller's habit, not part of the name.
test "a word is read whatever case it was typed in" {
  assert_eq(
    @moonmodel.Type::of_word(" UInt16 "),
    Some(
      @moonmodel.Type::Wire(@moonmodel.Layout::new(Int, bits=16, unsigned=true)),
    ),
  )
  assert_eq(@moonmodel.Type::of_word("Text"), Some(Text))
}

///|
/// The four facts a document has no word for, each of them carried by a
/// layout and each of them coming back out of the word unchanged.
test "a layout round-trips through its word" {
  let layouts = [
    @moonmodel.Layout::new(Int, bits=8),
    @moonmodel.Layout::new(Int, bits=16, unsigned=true),
    @moonmodel.Layout::new(Big, bits=64, unsigned=true),
    @moonmodel.Layout::new(Real, bits=32),
    @moonmodel.Layout::new(Int, order=@moonmodel.Order::Big),
    @moonmodel.Layout::new(Text, reference=true),
    @moonmodel.Layout::new(
      Int,
      bits=32,
      unsigned=true,
      order=@moonmodel.Order::Big,
      reference=true,
    ),
  ]
  for layout in layouts {
    let kind = @moonmodel.Type::Wire(layout)
    let word = kind.word().unwrap()
    assert_eq(@moonmodel.Type::of_word(word), Some(kind))
  }
}

///|
/// The suffixes are read from the right: `-ref` last, then `-be`. Anything
/// else is not a word this vocabulary has, which is what keeps a typo in an
/// annotation from becoming a type nobody meant.
test "a word that is not one of these is refused" {
  for
    word in ["", "list", "dict", "ref", "uint24", "int-ref-be", "float", "wire"] {
    assert_eq(@moonmodel.Type::of_word(word), None)
  }
}

///|
/// Only a number has a width, and only the widths the vocabulary names. A
/// layout that fixes none leaves the format's own word in place, which is the
/// same word a plain `Int` or `Big` already carries.
test "the width is a format word where one is fixed" {
  assert_eq(@moonmodel.Layout::new(Int, bits=8).format(), Some("int8"))
  assert_eq(
    @moonmodel.Layout::new(Int, bits=16, unsigned=true).format(),
    Some("uint16"),
  )
  assert_eq(
    @moonmodel.Layout::new(Big, bits=64, unsigned=true).format(),
    Some("uint64"),
  )
  assert_eq(@moonmodel.Layout::new(Real, bits=32).format(), Some("float32"))
  assert_eq(@moonmodel.Layout::new(Int).format(), None)
  // A width on something that is not a number is not a width.
  assert_eq(@moonmodel.Layout::new(Text, bits=8).format(), None)
  assert_eq(@moonmodel.Layout::new(Int, bits=24).format(), None)
}

///|
/// A type with parts inside has no single word: one word cannot carry what is
/// in it, and the description already states it as a structure.
test "a type with parts inside has no word" {
  let node = @moonmodel.Model::new("", [@moonmodel.Field::new("x", Int)])
  let kinds : Array[@moonmodel.Type] = [
    List(Text),
    Dict(Int),
    Ref("User"),
    Nest(node),
    Raw(Json::object(Map([]))),
  ]
  for kind in kinds {
    assert_eq(kind.word(), None)
  }
}

///|
/// The reference a layout carries is still a reference: a document writer has
/// to know to emit the model, even when the field is written by a byte format.
test "a layout is seen through when the references are collected" {
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new(
      "home",
      Wire(@moonmodel.Layout::new(Ref("Address"), reference=true)),
    ),
    @moonmodel.Field::new(
      "tags",
      List(Wire(@moonmodel.Layout::new(Ref("Tag")))),
    ),
  ])
  assert_eq(model.mentions(), ["Address", "Tag"])
}

///|
/// The common answer is the default: a format whose numbers are little-endian
/// and written in place says only the width, and it gets the same value as one
/// that says everything.
test "a layout's defaults are the common case" {
  assert_eq(@moonmodel.Layout::new(Int, bits=16, unsigned=true), {
    kind: Int,
    bits: Some(16),
    unsigned: true,
    order: @moonmodel.Order::Little,
    reference: false,
  })
}
