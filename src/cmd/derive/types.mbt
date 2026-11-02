// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The type inside `T?` or `Option[T]`, or `None` when `ty` is not optional.
fn inner_option(ty : String) -> String? {
  let ty = ty.trim(chars=" ")
  if ty.has_suffix("?") {
    Some(ty.exact_view(end=ty.length() - 1).trim(chars=" ").to_owned())
  } else {
    inside(ty.to_owned(), "Option[")
  }
}

///|
/// What sits between `head` and the closing bracket of `ty`.
fn inside(ty : String, head : String) -> String? {
  if ty.has_prefix(head) && ty.has_suffix("]") {
    Some(
      ty
      .exact_view(start=head.length(), end=ty.length() - 1)
      .trim(chars=" ")
      .to_owned(),
    )
  } else {
    None
  }
}

///|
/// The value type of a `Map[String, T]`. A key other than `String` has no description.
fn map_value(args : String) -> String? {
  guard args.find(",") is Some(comma) else { return None }
  guard args.exact_view(end=comma).trim(chars=" ") == "String" else {
    return None
  }
  Some(args.exact_view(start=comma + 1).trim(chars=" ").to_owned())
}

///|
/// The `Type` constructor a field of type `ty` takes, `None` when nothing says.
/// A name from another package is taken to be a model of the same name there:
/// nothing here can look, and a `Ref` is only a name.
fn kind_of(ty : String, known : Known) -> String? {
  let ty = ty.trim(chars=" ").to_owned()
  match ty {
    "Bool" => return Some("Bool")
    "Int" | "Int32" | "Int16" | "UInt16" | "Byte" => return Some("Int")
    "Int64" | "UInt" | "UInt32" | "UInt64" => return Some("Big")
    "Double" | "Float" => return Some("Real")
    "String" => return Some("Text")
    "Bytes" => return Some("Bytes")
    "Json" => return Some("Any")
    _ => ()
  }
  for head in ["Array[", "FixedArray[", "ArrayView["] {
    if inside(ty, head) is Some(item) {
      return kind_of(item, known).map(k => "List(\{k})")
    }
  }
  if inside(ty, "Map[") is Some(args) {
    return map_value(args).bind(v => kind_of(v, known)).map(k => "Dict(\{k})")
  }
  if known.enums.contains(ty) {
    return Some("Text")
  }
  if known.structs.get(ty) is Some(name) {
    return Some("Ref(\{quoted(name)})")
  }
  if ty.has_prefix("@") {
    match ty.rev_find(".") {
      Some(at) => {
        let name = ty.exact_view(start=at + 1).to_owned()
        return Some("Ref(\{quoted(name)})")
      }
      None => ()
    }
  }
  None
}

///|
/// The `Type` constructor a `kind=` names.
fn kind_named(name : String) -> String? {
  match name.trim(chars=" ").to_lower() {
    "bool" => Some("Bool")
    "int" => Some("Int")
    "big" => Some("Big")
    "real" => Some("Real")
    "text" => Some("Text")
    "bytes" => Some("Bytes")
    "stamp" => Some("Stamp")
    "any" => Some("Any")
    _ => None
  }
}

///|
/// A number written in a string, as a `Double` literal: an attribute has no
/// numbers of its own.
fn real(text : String, where_ : String) -> String raise {
  let number = @string.parse_double(text) catch {
    _ => fail("\{where_}: `\{text}` is not a number")
  }
  let shown = number.to_string()
  if shown.contains(".") || shown.contains("e") {
    shown
  } else {
    shown + ".0"
  }
}

///|
/// A whole number written in a string.
fn whole(text : String, where_ : String) -> String raise {
  let number : Int32 = @string.parse_int(text) catch {
    _ => fail("\{where_}: `\{text}` is not a whole number")
  }
  number.to_string()
}

///|
/// A value written in a string, as the `Json` literal for a field of `kind`. The
/// field's type says how to read it, so a text field's `"0"` stays text.
fn value(text : String, kind : String, where_ : String) -> String raise {
  match kind {
    "Text" => quoted(text)
    "Int" | "Big" => whole(text, where_)
    "Real" => real(text, where_)
    "Bool" => {
      guard text is ("true" | "false") else {
        fail("\{where_}: `\{text}` is not true or false")
      }
      text
    }
    _ => {
      let parsed = @json.parse(text) catch {
        _ => fail("\{where_}: `\{text}` is not JSON")
      }
      literal(parsed)
    }
  }
}

///|
/// A `Json` as the literal that builds it where a `Json` is expected.
fn literal(json : Json) -> String {
  match json {
    Null => "null"
    True => "true"
    False => "false"
    Number(n, ..) => n.to_string()
    String(s) => quoted(s)
    Array(items) => "[\{items.map(literal).join(", ")}]"
    Object(map) if map.is_empty() => "Json::object(Map([]))"
    Object(map) => {
      let pairs = map.iter().map(p => "\{quoted(p.0)}: \{literal(p.1)}")
      "{ \{pairs.collect().join(", ")} }"
    }
  }
}

///|
/// `HeroTeam` as `hero_team`, for the name of the `let` that holds a description.
fn snake(name : String) -> String {
  let out = StringBuilder()
  for i, c in name.to_array() {
    if c >= 'A' && c <= 'Z' {
      if i > 0 {
        out.write_char('_')
      }
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}
