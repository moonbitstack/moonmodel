// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Building the sheet: every field read four times, and the reason wherever a
// projection had nothing to say.

///|
struct Note {
  letter : String
  field : String
  reading : String
  why : String
}

///|
/// Record what a projection could not carry, and answer with the letter the
/// cell prints beside it.
fn note(
  notes : Array[Note],
  field : String,
  reading : String,
  why : String,
) -> String {
  for existing in notes {
    if existing.field == field && existing.why == why {
      return existing.letter
    }
  }
  let letter = if notes.length() < 26 {
    (notes.length() + 97).unsafe_to_char().to_string()
  } else {
    "?"
  }
  notes.push({ letter, field, reading, why, })
  letter
}

///|
fn properties_of(document : Json) -> Json? {
  match document {
    Object(map) => map.get("properties")
    _ => None
  }
}

///|
/// The `properties.<name>` schema of a one-field model.
fn field_schema(properties : Json?, name : String) -> Json? {
  match properties {
    Some(Object(map)) => map.get(name)
    _ => None
  }
}

///|
/// The column lines of a `CREATE TABLE`, without the statement around them.
fn table_lines(statement : String, name : String) -> Array[String] {
  let rows = statement.split("\n").collect()
  let out = []
  let mut seen = false
  for row in rows {
    let line = row.trim(chars=" ").to_owned()
    if line.has_prefix(name + " ") {
      seen = true
      out.push(
        if line.has_suffix(",") {
          line.exact_view(end=line.length() - 1).to_owned()
        } else {
          line
        },
      )
      continue
    }
    let continues = seen &&
      !line.has_prefix(")") &&
      (line.has_prefix("CHECK") || line.has_prefix("REFERENCES"))
    if continues {
      out.push(
        if line.has_suffix(",") {
          line.exact_view(end=line.length() - 1).to_owned()
        } else {
          line
        },
      )
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
/// The field's own line in a GraphQL type, and the type word on it.
fn sdl_line(text : String, name : String) -> (String, String) {
  for row in text.split("\n") {
    let line = row.trim(chars=" ").to_owned()
    if line.has_prefix(name + ":") {
      let rest = line
        .exact_view(start=name.length() + 1)
        .trim(chars=" ")
        .to_owned()
      return (line, rest)
    }
  }
  ("", "—")
}

///|
/// Whether a layout's numbers are wider than GraphQL's 32-bit `Int`.
fn too_wide_for_graphql(kind : @moonmodel.Type) -> Bool {
  match kind {
    Big => true
    Wire(layout) =>
      match layout.bits {
        Some(bits) => bits > 32 || (layout.unsigned && bits >= 32)
        None => false
      }
    _ => false
  }
}

///|
fn boolean(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn lost_json(lost : String?) -> String {
  match lost {
    Some(letter) => quoted(letter)
    None => "null"
  }
}

///|
fn cell_json(cell : Cell) -> String {
  "{\"lines\": " +
  string_array(cell.lines) +
  ", \"spell\": " +
  quoted(cell.spell) +
  ", \"lost\": " +
  lost_json(cell.lost) +
  "}"
}

///|
/// The whole sheet, as the JSON a page typesets.
fn sheet() -> String {
  let model = user()
  let notes : Array[Note] = []
  let fields : Array[String] = []
  let mut required = 0
  for field in model.fields {
    if field.required {
      required = required + 1
    }
    let name = field.name
    let one = @moonmodel.Model::new("", [field])

    // --- JSON Schema ------------------------------------------------------
    let json_cell = match field_schema(properties_of(@json.of(one)), name) {
      Some(fragment) => {
        let lost = if field.check.unique {
          Some(
            note(
              notes, name, "json", "unique reaches SQL only: JSON Schema keeps that on the collection, not on the value.",
            ),
          )
        } else {
          None
        }
        Cell::new(schema_lines(fragment), schema_spell(fragment), lost)
      }
      None => Cell::new([], "—", None)
    }

    // --- OpenAPI ----------------------------------------------------------
    let openapi_cell = match
      field_schema(properties_of(@open.of(one, dialect=@open.OpenApi30)), name) {
      Some(fragment) => {
        let lost = if field.check.unique {
          Some(
            note(
              notes, name, "openapi", "unique reaches SQL only: JSON Schema keeps that on the collection, not on the value.",
            ),
          )
        } else {
          None
        }
        Cell::new(schema_lines(fragment), schema_spell(fragment), lost)
      }
      None => Cell::new([], "—", None)
    }

    // --- SQL --------------------------------------------------------------
    let (columns, skipped) = @sql.of(one, dialect=@sql.Postgres)
    let sql_cell = if skipped.length() > 0 {
      Cell::new([], "—", Some(note(notes, name, "sql", skipped[0].why)))
    } else if columns.length() > 0 {
      let column = columns[0]
      let mut spell = column.kind
      if column.unique {
        spell = spell + " UNIQUE"
      }
      if column.check != "" {
        spell = spell + " + CHECK"
      }
      Cell::new(
        table_lines(@sql.table(one, dialect=@sql.Postgres), name),
        spell,
        None,
      )
    } else {
      Cell::new([], "—", None)
    }

    // --- GraphQL SDL ------------------------------------------------------
    let (sdl_text, sdl_skipped) = @sdl.of(one)
    let sdl_cell = if sdl_skipped.length() > 0 {
      Cell::new([], "—", Some(note(notes, name, "sdl", sdl_skipped[0].why)))
    } else {
      let (line, spell) = sdl_line(sdl_text, name)
      let why = if too_wide_for_graphql(field.kind) {
        Some(
          "GraphQL's Int is 32 bits, so a 64-bit integer is carried as a String.",
        )
      } else if field.kind is Stamp {
        Some(
          "GraphQL has no date; the document declares the DateTime scalar once.",
        )
      } else if field.kind is Bytes {
        Some("GraphQL has no byte string; it is carried as a String.")
      } else if !field.check.options.is_empty() {
        Some(
          "a closed set of values has no GraphQL form here; the enum reaches JSON and SQL only.",
        )
      } else {
        None
      }
      let lost = match why {
        Some(text) => Some(note(notes, name, "sdl", text))
        None => None
      }
      Cell::new([line], spell, lost)
    }

    // --- the station itself -----------------------------------------------
    let station_lost = match field.kind {
      Wire(layout) =>
        if layout.order is @moonmodel.Order::Big || layout.reference {
          Some(
            note(
              notes, name, "station", "the width of a layout becomes a format word; its byte order and its reference mark reach no document at all.",
            ),
          )
        } else {
          None
        }
      _ => None
    }

    let row = StringBuilder()
    row.write_string("    { \"name\": ")
    row.write_string(quoted(name))
    row.write_string(", \"type\": ")
    row.write_string(quoted(display(field.kind, field.nullable)))
    row.write_string(", \"doc\": ")
    row.write_string(quoted(field.doc))
    row.write_string(", \"required\": ")
    row.write_string(boolean(field.required))
    row.write_string(", \"station_lost\": ")
    row.write_string(lost_json(station_lost))
    row.write_string(", \"cells\": {\n")
    row.write_string("        \"json\": " + cell_json(json_cell) + ",\n")
    row.write_string("        \"openapi\": " + cell_json(openapi_cell) + ",\n")
    row.write_string("        \"sql\": " + cell_json(sql_cell) + ",\n")
    row.write_string("        \"sdl\": " + cell_json(sdl_cell) + " } }")
    fields.push(row.to_string())
  }

  let note_rows = []
  for item in notes {
    let row = StringBuilder()
    row.write_string("    { \"n\": " + quoted(item.letter))
    row.write_string(", \"field\": " + quoted(item.field))
    row.write_string(", \"reading\": " + quoted(item.reading))
    row.write_string(", \"why\": " + quoted(item.why) + " }")
    note_rows.push(row.to_string())
  }

  let out = StringBuilder()
  out.write_string("{\n")
  out.write_string("  \"model\": " + quoted(model.name) + ",\n")
  out.write_string("  \"doc\": " + quoted(model.doc) + ",\n")
  out.write_string(
    "  \"stat\": { \"fields\": " +
    fields.length().to_string() +
    ", \"required\": " +
    required.to_string() +
    ", \"lost\": " +
    notes.length().to_string() +
    " },\n",
  )
  out.write_string("  \"fields\": [\n")
  out.write_string(fields.join(",\n"))
  out.write_string("\n  ],\n")
  out.write_string("  \"notes\": [\n")
  out.write_string(note_rows.join(",\n"))
  out.write_string("\n  ]\n")
  out.write_string("}\n")
  out.to_string()
}
