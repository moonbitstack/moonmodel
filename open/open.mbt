// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which OpenAPI a document is written for.
pub(all) enum Dialect {
  /// Swagger 2.0, whose Schema Object is a draft-4 subset.
  Swagger20
  /// OpenAPI 3.0.3, still draft-4 shaped but with a `nullable` flag.
  OpenApi30
  /// OpenAPI 3.1.0, which is JSON Schema 2020-12 exactly.
  OpenApi31
} derive(Eq, Debug)

///|
pub extend Dialect with Eq::{equal, not_equal}

///|
pub extend Dialect with Debug::{to_repr}

///|
/// Where a named schema lives, which is the one thing 2.0 moved.
pub fn Dialect::at(self : Dialect) -> String {
  match self {
    Swagger20 => "#/definitions/"
    _ => "#/components/schemas/"
  }
}

///|
/// The key a document stores its named schemas under.
pub fn Dialect::holder(self : Dialect) -> String {
  match self {
    Swagger20 => "definitions"
    _ => "components"
  }
}

///|
/// A model as an OpenAPI Schema Object.
///
/// 3.1 is 2020-12, so it is `json`'s output with the reference prefix moved.
/// The two older dialects are that output walked once more, undoing the three
/// things they cannot say.
pub fn of(model : @moonmodel.Model, dialect~ : Dialect = OpenApi31) -> Json {
  let schema = @json.of(model, at=dialect.at())
  match dialect {
    OpenApi31 => schema
    _ => older(schema, model, dialect)
  }
}

///|
/// Everything the model reaches, under the key the dialect keeps them in.
///
/// The envelope differs: 2.0 puts them at the top level under `definitions`,
/// 3.x one level down under `components.schemas`.
pub fn schemas(
  models : ArrayView[@moonmodel.Model],
  dialect~ : Dialect = OpenApi31,
) -> Json {
  let named : Map[String, Json] = Map([])
  for model in models {
    named[model.name] = of(model, dialect~)
  }
  match dialect {
    Swagger20 => Json::object(Map([("definitions", Json::object(named))]))
    _ =>
      Json::object(
        Map([
          ("components", Json::object(Map([("schemas", Json::object(named))]))),
        ]),
      )
  }
}

///|
/// 2020-12 rewritten for a draft-4-shaped dialect.
///
/// Three differences, each of them the older dialect failing to say
/// something:
///
/// * `type: [t, "null"]` is 2020-12's. 3.0 has a `nullable` flag instead, and
///   2.0 has nothing in the specification proper — `x-nullable` is the
///   extension its tooling reads, and writing nothing at all would silently
///   turn an optional value into a required one.
/// * `exclusiveMinimum` and `exclusiveMaximum` are numbers in 2020-12 and
///   booleans beside `minimum` / `maximum` in draft 4.
/// * `$defs` does not exist; the holder is named by the dialect.
fn older(schema : Json, model : @moonmodel.Model, dialect : Dialect) -> Json {
  guard schema is Object(fields) else { return schema }
  guard fields.get("properties") is Some(Object(properties)) else {
    return schema
  }
  for field in model.fields {
    guard properties.get(field.name) is Some(Object(one)) else { continue }
    exclusive(one)
    if field.nullable {
      // The type came back as a two-element list; put the single type back
      // and say nullable the way this dialect says it.
      match one.get("type") {
        Some(Array(both)) => if both.length() > 0 { one["type"] = both[0] }
        _ => ()
      }
      match dialect {
        Swagger20 => one["x-nullable"] = Json::boolean(true)
        _ => one["nullable"] = Json::boolean(true)
      }
    }
    properties[field.name] = Json::object(one)
  }
  fields["properties"] = Json::object(properties)
  Json::object(fields)
}

///|
/// Draft 4 writes an open bound as a boolean next to the closed one.
fn exclusive(one : Map[String, Json]) -> Unit {
  match one.get("exclusiveMinimum") {
    Some(Number(value, ..)) => {
      one.remove("exclusiveMinimum")
      one["minimum"] = Json::number(value)
      one["exclusiveMinimum"] = Json::boolean(true)
    }
    _ => ()
  }
  match one.get("exclusiveMaximum") {
    Some(Number(value, ..)) => {
      one.remove("exclusiveMaximum")
      one["maximum"] = Json::number(value)
      one["exclusiveMaximum"] = Json::boolean(true)
    }
    _ => ()
  }
}
