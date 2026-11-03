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
/// The description type of a field written as `ty`, `None` when nothing says.
/// A name from another package is taken to be a model of the same name there:
/// nothing here can look, and a `Ref` is only a name.
fn kind_of(ty : String, known : Known) -> @moonmodel.Type? {
  let ty = ty.trim(chars=" ").to_owned()
  match ty {
    "Bool" => return Some(@moonmodel.Bool)
    "Int" | "Int32" | "Int16" | "UInt16" | "Byte" => return Some(@moonmodel.Int)
    "Int64" | "UInt" | "UInt32" | "UInt64" => return Some(@moonmodel.Big)
    "Double" | "Float" => return Some(@moonmodel.Real)
    "String" => return Some(@moonmodel.Text)
    "Bytes" => return Some(@moonmodel.Bytes)
    "Json" => return Some(@moonmodel.Any)
    _ => ()
  }
  for head in ["Array[", "FixedArray[", "ArrayView["] {
    if inside(ty, head) is Some(item) {
      return kind_of(item, known).map(k => @moonmodel.List(k))
    }
  }
  if inside(ty, "Map[") is Some(args) {
    return map_value(args)
      .bind(v => kind_of(v, known))
      .map(k => @moonmodel.Dict(k))
  }
  // An annotated enum is the set of its constructors, written as text.
  if known.enums.contains(ty) {
    return Some(@moonmodel.Text)
  }
  if known.structs.get(ty) is Some(name) {
    return Some(@moonmodel.Ref(name))
  }
  if ty.has_prefix("@") {
    match ty.rev_find(".") {
      Some(at) => {
        let name = ty.exact_view(start=at + 1).to_owned()
        return Some(@moonmodel.Ref(name))
      }
      None => ()
    }
  }
  None
}

///|
/// What a type is for the sake of a bound and of a default's spelling.
///
/// Finer than "is it a number" and coarser than the type itself: a whole
/// number's default is written as one and a real's with a decimal point, and
/// the bounds differ in which of the two they may be written on.
priv enum Family {
  Flag
  Integer
  Real
  Textual
  Sequence
  Mapping
  Opaque
}

///|
fn family(kind : @moonmodel.Type) -> Family {
  match kind {
    Bool => Flag
    Int | Big => Integer
    Real => Real
    // A layout is about how a value is written, not about what it is, so a
    // bound and a default follow the kind inside it.
    Wire(layout) => family(layout.kind)
    Text => Textual
    List(_) => Sequence
    Dict(_) => Mapping
    _ => Opaque
  }
}

///|
/// A description type as the code that builds it, in the package the
/// generated file lives in.
fn code_of(kind : @moonmodel.Type) -> String raise {
  match kind {
    Bool => "Bool"
    Int => "Int"
    Big => "Big"
    Real => "Real"
    Text => "Text"
    Bytes => "Bytes"
    Stamp => "Stamp"
    Any => "Any"
    List(inner) => "List(\{code_of(inner)})"
    Dict(inner) => "Dict(\{code_of(inner)})"
    Ref(name) => "Ref(\{quoted(name)})"
    Wire(layout) => {
      let parts = ["@moonmodel.Layout::new(\{code_of(layout.kind)}"]
      match layout.bits {
        Some(bits) => parts.push("bits=\{bits}")
        None => ()
      }
      if layout.unsigned {
        parts.push("unsigned=true")
      }
      if layout.order == @moonmodel.Order::Big {
        parts.push("order=@moonmodel.Order::Big")
      }
      if layout.reference {
        parts.push("reference=true")
      }
      "Wire(\{parts.join(", ")}))"
    }
    Nest(_) => fail("moonmodel: an annotation cannot state a nested model")
    Raw(_) => fail("moonmodel: an annotation cannot state a schema by hand")
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
/// A value written in a string, as the `Json` literal for a field of this
/// family. The field's type says how to read it, so a text field's `"0"` stays
/// text.
fn value(text : String, kind : Family, where_ : String) -> String raise {
  match kind {
    Textual => quoted(text)
    Integer => whole(text, where_)
    Real => real(text, where_)
    Flag => {
      guard text is ("true" | "false") else {
        fail("\{where_}: `\{text}` is not true or false")
      }
      text
    }
    // A list, a mapping and a value of no shape at all are written as the
    // JSON they are: an attribute has no syntax of its own for them.
    Sequence | Mapping | Opaque => {
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
