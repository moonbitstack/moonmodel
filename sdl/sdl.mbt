// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A field GraphQL has no type for, and why.
pub(all) struct Skipped {
  field : String
  why : String
} derive(Eq, Debug)

///|
pub extend Skipped with Eq::{equal, not_equal}

///|
pub extend Skipped with Debug::{to_repr}

///|
/// The scalar a `Stamp` is written as.
///
/// GraphQL has five built-in scalars and no date among them, so every schema
/// that carries one declares a custom scalar. `DateTime` is what the
/// ecosystem settled on; a schema using another name says so here.
pub let stamp : String = "DateTime"

///|
/// The scalar bytes are written as, for the same reason.
pub let bytes : String = "Base64"

///|
/// A model as a GraphQL object type.
///
/// `input` writes `input` instead of `type`, which is the same shape under a
/// different keyword and the one GraphQL requires for arguments.
pub fn of(
  model : @moonmodel.Model,
  input~ : Bool = false,
  stamp~ : String = stamp,
  bytes~ : String = bytes,
) -> (String, Array[Skipped]) {
  let skipped = []
  let out = StringBuilder()
  if model.doc != "" {
    out.write_string("\"\"\"\n")
    out.write_string(model.doc)
    out.write_string("\n\"\"\"\n")
  }
  out.write_string(if input { "input " } else { "type " })
  out.write_string(model.name)
  out.write_string(" {\n")
  for field in model.fields {
    match written(field.kind, stamp, bytes) {
      None => skipped.push({ field: field.name, why: untypeable(field.kind), })
      Some(kind) => {
        if field.doc != "" {
          out.write_string("  \"\{field.doc}\"\n")
        }
        out.write_string("  ")
        out.write_string(field.name)
        out.write_string(": ")
        out.write_string(kind)
        // `!` is the one place GraphQL folds two questions into one: a field
        // is non-null when it must be there and may not be null.
        if field.required && !field.nullable {
          out.write_string("!")
        }
        out.write_string("\n")
      }
    }
  }
  out.write_string("}")
  (out.to_string(), skipped)
}

///|
/// Several models, and every scalar they need declared, in one document.
pub fn document(
  models : ArrayView[@moonmodel.Model],
  stamp~ : String = stamp,
  bytes~ : String = bytes,
) -> String {
  let scalars = []
  for model in models {
    for field in model.fields {
      if uses(field.kind, Stamp) && !scalars.contains(stamp) {
        scalars.push(stamp)
      }
      if uses(field.kind, Bytes) && !scalars.contains(bytes) {
        scalars.push(bytes)
      }
    }
  }
  let out = StringBuilder()
  for one in scalars {
    out.write_string("scalar \{one}\n")
  }
  if scalars.length() > 0 {
    out.write_string("\n")
  }
  for i = 0; i < models.length(); i = i + 1 {
    let (text, _skipped) = of(models[i], stamp~, bytes~)
    out.write_string(text)
    out.write_string("\n")
    if i + 1 < models.length() {
      out.write_string("\n")
    }
  }
  out.to_string()
}

///|
/// Whether a type contains `want`, at any depth.
fn uses(kind : @moonmodel.Type, want : @moonmodel.Type) -> Bool {
  if kind == want {
    return true
  }
  match kind {
    List(inner) | Dict(inner) => uses(inner, want)
    _ => false
  }
}

///|
/// A type as GraphQL writes it, or nothing when GraphQL has no way to.
///
/// A list's element carries its own `!`: `[String!]` is a list of non-null
/// strings, which is what a description with no nullable element means. The
/// outer `!` is the field's and is added by the caller.
fn written(kind : @moonmodel.Type, stamp : String, bytes : String) -> String? {
  match kind {
    Bool => Some("Boolean")
    Int => Some("Int")
    // GraphQL's Int is 32-bit by specification, so a 64-bit one cannot be it.
    // Every schema that needs one declares a custom scalar; the convention is
    // to carry it as a String, which is what Relay and the major servers do.
    Big => Some("String")
    Real => Some("Float")
    Text => Some("String")
    Bytes => Some(bytes)
    Stamp => Some(stamp)
    List(inner) =>
      match written(inner, stamp, bytes) {
        Some(inner) => Some("[" + inner + "!]")
        None => None
      }
    Ref(name) => Some(name)
    // There is no map type: a mapping with open keys has to become a list of
    // pairs, and inventing that shape here would put a type in the schema
    // nobody declared.
    Dict(_) => None
    // GraphQL has no anonymous object type either: every type is declared and
    // named, so a nested model has to be given a name before it can be used.
    Nest(_) => None
    Any => None
    Raw(_) => None
  }
}

///|
fn untypeable(kind : @moonmodel.Type) -> String {
  match kind {
    Dict(_) =>
      "a mapping with open keys has no GraphQL type; declare a list of pairs"
    Nest(_) =>
      "every GraphQL type is named; give this model a name and refer to it"
    Any => "anything at all has no GraphQL type"
    Raw(_) => "a schema written out by hand has no GraphQL type"
    List(_) => "the element has no GraphQL type"
    _ => "no GraphQL type"
  }
}
