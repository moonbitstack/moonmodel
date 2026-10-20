// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a value is, in the smallest set all four projections recognise.
///
/// `Ref` names another model rather than nesting it, so two models may point
/// at each other and a projection decides for itself whether to inline or to
/// emit a reference — `$ref` in JSON Schema, a foreign key in SQL, a named
/// type in SDL.
pub(all) enum Type {
  Bool
  /// A 32-bit integer.
  Int
  /// A 64-bit integer. Separate from `Int` because SQL and GraphQL both care
  /// which one, and because JSON numbers past 2^53 do not survive a double.
  Big
  Real
  Text
  Bytes
  /// A moment in time. Only a format that defines one reads into this; see
  /// `Check::format` for the other case, where a date is a string being
  /// checked rather than a date being parsed.
  Stamp
  List(Type)
  /// A mapping with text keys. SQL and GraphQL have no such thing, and say so
  /// in their own way.
  Dict(Type)
  /// Another model, by name.
  Ref(String)
  /// Another model, written here. For the one that has no name of its own and
  /// so cannot be referred to; a named one belongs in `Ref` so that the
  /// projections can hoist it and point at it once.
  Nest(Model)
  /// Anything at all: JSON Schema's empty schema.
  Any
  /// A schema written out in full, for what this vocabulary cannot say —
  /// `allOf`, a vocabulary of one's own, a dialect's extension. Each
  /// projection either passes it through as it stands or reports that it
  /// cannot carry it. Reach for it last: nothing reads inside it.
  Raw(Json)
} derive(Eq, Debug)

///|
pub extend Type with Eq::{equal, not_equal}

///|
pub extend Type with Debug::{to_repr}

///|
/// The bounds a value must satisfy.
///
/// The names avoid `min` and `max`, which mean different things in the four
/// targets: `least` and `most` are the closed bounds, `under` and `over` the
/// open ones (JSON Schema's `exclusiveMinimum` and `exclusiveMaximum`).
/// `shortest` and `longest` bound a string's characters and a list's items
/// alike, which is how every one of the four spells it too.
pub(all) struct Check {
  least : Double?
  most : Double?
  over : Double?
  under : Double?
  /// A multiple the value must be one of (`multipleOf`).
  step : Double?
  shortest : Int32?
  longest : Int32?
  pattern : String?
  /// A named shape a string is checked against — `date-time`, `email`, `uuid`.
  /// Checked, never converted: see the README on when a string becomes a date.
  format : String?
  /// The values allowed, if the set is closed. Json rather than text because
  /// a closed set of numbers is just as ordinary as one of names.
  options : Array[Json]
  /// Whether a list's items must differ (`uniqueItems`).
  distinct : Bool
  /// Whether no two records may carry the same value.
  ///
  /// Separate from `distinct`, which is about one list's own items: this one
  /// is about the collection the records live in, and only SQL can state it.
  /// The other three projections drop it.
  unique : Bool
} derive(Eq, Debug)

///|
pub extend Check with Eq::{equal, not_equal}

///|
pub extend Check with Debug::{to_repr}

///|
/// No bound at all, which is what most fields carry.
pub let check : Check = {
  least: None,
  most: None,
  over: None,
  under: None,
  step: None,
  shortest: None,
  longest: None,
  pattern: None,
  format: None,
  options: [],
  distinct: false,
  unique: false,
}

///|
/// A `Check` by name, so a caller states the one bound it means.
pub fn Check::new(
  least? : Double,
  most? : Double,
  over? : Double,
  under? : Double,
  step? : Double,
  shortest? : Int32,
  longest? : Int32,
  pattern? : String,
  format? : String,
  options~ : Array[Json] = [],
  distinct~ : Bool = false,
  unique~ : Bool = false,
) -> Check {
  {
    least,
    most,
    over,
    under,
    step,
    shortest,
    longest,
    pattern,
    format,
    options,
    distinct,
    unique,
  }
}

///|
/// Whether anything is bounded at all, which is how a projection decides to
/// write nothing rather than an empty object.
pub fn Check::is_empty(self : Check) -> Bool {
  self == check
}

///|
/// One field of a model.
///
/// `required` and `nullable` are two questions, not one. The first asks
/// whether the key has to be there, the second whether its value may be null.
/// JSON Schema keeps them apart (`required` is a list on the object, `null` is
/// a type), SQL's `NOT NULL` is the second alone, and GraphQL's `!` is both at
/// once. Folding them into one field would leave at least one projection
/// guessing.
pub(all) struct Field {
  name : String
  kind : Type
  required : Bool
  nullable : Bool
  doc : String
  default : Json?
  check : Check
} derive(Eq, Debug)

///|
pub extend Field with Eq::{equal, not_equal}

///|
pub extend Field with Debug::{to_repr}

///|
/// A field. Required by default, because a type whose fields are all optional
/// describes almost nothing, and because every one of the four targets treats
/// "present" as the ordinary case.
pub fn Field::new(
  name : String,
  kind : Type,
  required~ : Bool = true,
  nullable~ : Bool = false,
  doc~ : String = "",
  default? : Json,
  check~ : Check = check,
) -> Field {
  { name, kind, required, nullable, doc, default, check, }
}

///|
/// A named type and its fields.
pub(all) struct Model {
  name : String
  doc : String
  fields : Array[Field]
} derive(Eq, Debug)

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with Debug::{to_repr}

///|
pub fn Model::new(
  name : String,
  fields : Array[Field],
  doc~ : String = "",
) -> Model {
  { name, doc, fields, }
}

///|
/// One field by name, for a projection that needs to look one up.
pub fn Model::field(self : Model, name : String) -> Field? {
  for one in self.fields {
    if one.name == name {
      return Some(one)
    }
  }
  None
}

///|
/// The names of the fields that must be present, in declaration order —
/// JSON Schema's `required` array, and the test every projection applies.
pub fn Model::required(self : Model) -> Array[String] {
  let out = []
  for one in self.fields {
    if one.required {
      out.push(one.name)
    }
  }
  out
}

///|
/// Every model named by a `Ref` anywhere in this one, in the order met and
/// without repeats.
///
/// A projection that writes a document rather than a fragment needs this: it
/// has to emit the models this one points at, and the ones those point at.
pub fn Model::mentions(self : Model) -> Array[String] {
  let out = []
  for one in self.fields {
    names(one.kind, out)
  }
  out
}

///|
fn names(kind : Type, out : Array[String]) -> Unit {
  match kind {
    Ref(name) => if !out.contains(name) { out.push(name) }
    List(inner) | Dict(inner) => names(inner, out)
    // A nested model has no name of its own, but what it refers to counts.
    Nest(model) =>
      for one in model.fields {
        names(one.kind, out)
      }
    _ => ()
  }
}
