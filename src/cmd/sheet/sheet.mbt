// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The sheet, as data. One model is projected four times; what comes out is the
// text of each cell, the one-word summary a reader compares across a row, and
// what each projection had to leave out — so a page can typeset all of it and
// reflow when a field is added.

///|
/// The model the sheet prints. It is the one in `src/examples/annotations`,
/// written out as calls, so the sheet and the example cannot drift.
fn user() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "User",
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
          Json::string("Admin"),
          Json::string("Member"),
          Json::string("Guest"),
        ]),
      ),
      @moonmodel.Field::new(
        "weight",
        @moonmodel.Real,
        required=false,
        default=Json::number(1.0),
        check=@moonmodel.Check::new(over=0.0),
      ),
      @moonmodel.Field::new("home", @moonmodel.Ref("Address")),
      @moonmodel.Field::new(
        "tags",
        @moonmodel.List(@moonmodel.Text),
        check=@moonmodel.Check::new(longest=8, distinct=true),
      ),
      @moonmodel.Field::new("joined", @moonmodel.Stamp),
      @moonmodel.Field::new(
        "count",
        @moonmodel.Wire(
          @moonmodel.Layout::new(
            @moonmodel.Int,
            bits=16,
            unsigned=true,
            order=@moonmodel.Order::Big,
            reference=true,
          ),
        ),
      ),
    ],
    doc="somebody with an account",
  )
}

///|
/// One cell: the lines as they are printed, the one-word summary, and the note
/// letter when the projection left something out.
struct Cell {
  lines : Array[String]
  spell : String
  lost : String?
}

///|
fn Cell::new(lines : Array[String], spell : String, lost : String?) -> Cell {
  { lines, spell, lost, }
}

///|
/// A quoted JSON string.
fn quoted(text : String) -> String {
  @moonjson.dumps(Json::string(text))
}

///|
fn string_array(items : Array[String]) -> String {
  "[" + items.map(quoted).join(", ") + "]"
}

///|
/// A value on one line, which is how a cell prints it.
fn inline(json : Json) -> String {
  match json {
    Null => "null"
    True => "true"
    False => "false"
    Number(n, ..) => n.to_string()
    String(s) => quoted(s)
    Array(items) => "[" + items.map(inline).join(", ") + "]"
    Object(map) if map.is_empty() => "{}"
    Object(map) => {
      let pairs = map
        .iter()
        .map(p => quoted(p.0) + ": " + inline(p.1))
        .collect()
      "{ " + pairs.join(", ") + " }"
    }
  }
}

///|
/// The order a schema's keys are read in: what a value is, then what it is
/// checked against, then its name. Any other key follows alphabetically, so two
/// runs produce the same sheet.
fn key_order(map : Map[String, Json]) -> Array[String] {
  let priority = [
    "type", "format", "$ref", "items", "enum", "minLength", "maxLength", "minimum",
    "maximum", "exclusiveMinimum", "minItems", "maxItems", "uniqueItems", "default",
    "nullable", "description",
  ]
  let out = []
  for key in priority {
    if map.contains(key) {
      out.push(key)
    }
  }
  let rest = map.keys().filter(k => !out.contains(k)).collect()
  rest.sort()
  out..append(rest)
}

///|
/// A line broken at spaces, the continuation indented, so a cell never runs
/// into the column beside it.
fn wrap(text : String, width : Int32) -> Array[String] {
  let out = []
  let mut line = ""
  for word in text.split(" ").collect() {
    let w = word.to_owned()
    let next = if line == "" { w } else { line + " " + w }
    if next.length() > width && line != "" {
      out.push(line)
      line = "  " + w
    } else {
      line = next
    }
  }
  if line != "" {
    out.push(line)
  }
  out
}

///|
/// The entries of a schema object as printed lines, a trailing comma on every
/// one but the last. A description is an ellipsis: the text belongs on the
/// spine, and a cell is thirty characters wide.
fn schema_lines(fragment : Json) -> Array[String] {
  let out = []
  if fragment is Object(map) {
    let keys = key_order(map)
    for i, key in keys {
      let shown = match map.get(key) {
        Some(String(text)) if key == "$ref" => quoted(last_segment(text))
        Some(String(text)) if text.length() > 18 => "\"…\""
        Some(value) => inline(value)
        None => "\"\""
      }
      let comma = if i == keys.length() - 1 { "" } else { "," }
      out.push(quoted(key) + ": " + shown + comma)
    }
  }
  let wrapped = []
  for line in out {
    for one in wrap(line, 34) {
      wrapped.push(one)
    }
  }
  wrapped
}

///|
/// The one-word summary of a schema: what a reader compares across a row.
fn number_text(n : Double) -> String {
  let whole = n.to_int()
  if n == whole.to_double() {
    whole.to_string()
  } else {
    n.to_string()
  }
}

///|
fn last_segment(path : String) -> String {
  match path.rev_find("/") {
    Some(at) => "…" + path.exact_view(start=at).to_owned()
    None => path
  }
}

///|
fn number_at(map : Map[String, Json], key : String) -> String? {
  match map.get(key) {
    Some(Number(n, ..)) => Some(number_text(n))
    _ => None
  }
}

///|
/// The one-word summary of a schema: what a reader compares across a row.
fn schema_spell(fragment : Json) -> String {
  let out = StringBuilder()
  if fragment is Object(map) {
    if map.get("$ref") is Some(String(path)) {
      out.write_string(
        "ref " + last_segment(path).exact_view(start=2).to_owned(),
      )
      return out.to_string()
    }
    let mut nullable = false
    let names = []
    match map.get("type") {
      Some(String(one)) => names.push(one)
      Some(Array(items)) =>
        for item in items {
          match item {
            String(one) =>
              if one == "null" {
                nullable = true
              } else {
                names.push(one)
              }
            _ => ()
          }
        }
      _ => ()
    }
    out.write_string(names.join("|"))
    if map.get("format") is Some(String(one)) {
      out.write_string(" " + one)
    }
    let least = number_at(map, "minimum")
    let most = number_at(map, "maximum")
    let shortest = number_at(map, "minLength")
    let longest = number_at(map, "maxLength")
    if least is Some(one) {
      if most is Some(two) {
        out.write_string(" " + one + "…" + two)
      } else {
        out.write_string(" ≥" + one)
      }
    } else if most is Some(two) {
      out.write_string(" ≤" + two)
    }
    if shortest is Some(one) {
      if longest is Some(two) {
        out.write_string(" " + one + "…" + two)
      } else {
        out.write_string(" ≥" + one + " chars")
      }
    } else if longest is Some(two) {
      out.write_string(" ≤" + two)
    }
    if map.get("exclusiveMinimum") is Some(Number(n, ..)) {
      out.write_string(" >" + number_text(n))
    } else if map.get("exclusiveMinimum") is Some(True) {
      out.write_string(" open")
    }
    match map.get("enum") {
      Some(Array(items)) =>
        out.write_string(" enum " + items.length().to_string())
      _ => ()
    }
    match map.get("default") {
      Some(value) => out.write_string(" =" + inline(value))
      _ => ()
    }
    if map.get("nullable") is Some(True) {
      nullable = true
    }
    if nullable {
      out.write_string("|null")
    }
  }
  out.to_string()
}

///|
/// The type as the spine writes it: `Big`, `Text?`, `List[Text]`, a layout's own
/// word.
fn display(kind : @moonmodel.Type, nullable : Bool) -> String {
  let name = match kind {
    Bool => "Bool"
    Int => "Int"
    Big => "Big"
    Real => "Real"
    Text => "Text"
    Bytes => "Bytes"
    Stamp => "Stamp"
    Any => "Any"
    List(inner) => "List[" + display(inner, false) + "]"
    Dict(inner) => "Map[String, " + display(inner, false) + "]"
    Ref(_) => "Ref"
    Nest(_) => "Nest"
    Wire(layout) => layout_word(layout)
    Raw(_) => "Raw"
  }
  if nullable {
    name + "?"
  } else {
    name
  }
}

///|
fn layout_word(layout : @moonmodel.Layout) -> String {
  @moonmodel.Type::Wire(layout).word().unwrap_or("wire")
}
