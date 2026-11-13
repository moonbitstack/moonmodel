// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The corpus as one JSON document: every model and its four projections, every
// labelled instance, every probe. This is the only thing the harness reads, so
// what it checks is what this library writes, not a transcription of it.

///|
/// The whole corpus.
fn bundle() -> Json {
  let all = models()
  let by_name : Map[String, @moonmodel.Model] = Map([])
  for one in all {
    by_name[one.name] = one
  }
  let described = []
  for model in all {
    described.push(model_json(model, all))
  }
  let api = Map([])
  for dialect in [@open.Swagger20, @open.OpenApi30, @open.OpenApi31] {
    api[api_dialect(dialect)] = @open.schemas(all, dialect~)
  }
  let rows = cases()
  let cases = []
  for one in rows {
    guard by_name.get(one.model) is Some(model) else { continue }
    let ours = @verify.valid(model, one.data, known=all) catch { _ => false }
    cases.push(
      Json::object(
        Map([
          ("model", Json::string(one.model)),
          ("instance", one.data),
          ("valid", Json::boolean(one.valid)),
          ("ours", Json::boolean(ours)),
          ("why", Json::string(one.why)),
        ]),
      ),
    )
  }
  let checks = probes()
  let probes = []
  for one in checks {
    probes.push(
      Json::object(
        Map([
          ("model", Json::string(one.model)),
          ("sql", Json::string(one.sql)),
          ("valid", Json::boolean(one.valid)),
          ("why", Json::string(one.why)),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      ("models", Json::array(described)),
      ("openapi", Json::object(api)),
      ("sdl", Json::string(@sdl.document(all))),
      ("cases", Json::array(cases)),
      ("probes", Json::array(probes)),
    ]),
  )
}

///|
fn model_json(
  model : @moonmodel.Model,
  known : Array[@moonmodel.Model],
) -> Json {
  let columns = Map([])
  let ddl = Map([])
  let skipped = Map([])
  for dialect in [@sql.Sqlite, @sql.Postgres, @sql.Mysql] {
    let name = sql_dialect(dialect)
    let (written, left) = @sql.of(model, dialect~)
    columns[name] = Json::array(written.map(column_json))
    ddl[name] = Json::string(@sql.table(model, dialect~))
    skipped[name] = Json::array(left.map(sql_skip_json))
  }
  let (sdl, sdl_skipped) = @sdl.of(model)
  Json::object(
    Map([
      ("name", Json::string(model.name)),
      ("schema", @json.document(model, known~)),
      ("columns", Json::object(columns)),
      ("ddl", Json::object(ddl)),
      ("skipped", Json::object(skipped)),
      ("sdl", Json::string(sdl)),
      ("sdl_skipped", Json::array(sdl_skipped.map(skip_json))),
      ("fields", Json::array(model.fields.map(field_json))),
    ]),
  )
}

///|
fn column_json(one : @sql.Column) -> Json {
  Json::object(
    Map([
      ("name", Json::string(one.name)),
      ("kind", Json::string(one.kind)),
      ("null", Json::boolean(one.null)),
      (
        "default",
        match one.default {
          Some(text) => Json::string(text)
          None => Json::null()
        },
      ),
      ("unique", Json::boolean(one.unique)),
      ("check", Json::string(one.check)),
    ]),
  )
}

///|
fn sql_skip_json(one : @sql.Skipped) -> Json {
  Json::object(
    Map([("field", Json::string(one.field)), ("why", Json::string(one.why))]),
  )
}

///|
fn skip_json(one : @sdl.Skipped) -> Json {
  Json::object(
    Map([("field", Json::string(one.field)), ("why", Json::string(one.why))]),
  )
}

///|
fn field_json(one : @moonmodel.Field) -> Json {
  Json::object(
    Map([
      ("name", Json::string(one.name)),
      ("required", Json::boolean(one.required)),
      ("nullable", Json::boolean(one.nullable)),
      ("list", Json::boolean(is_list(one.kind))),
    ]),
  )
}

///|
fn is_list(kind : @moonmodel.Type) -> Bool {
  match kind {
    List(_) => true
    Wire(layout) => is_list(layout.kind)
    _ => false
  }
}

///|
fn api_dialect(dialect : @open.Dialect) -> String {
  match dialect {
    Swagger20 => "swagger20"
    OpenApi30 => "openapi30"
    OpenApi31 => "openapi31"
  }
}

///|
fn sql_dialect(dialect : @sql.Dialect) -> String {
  match dialect {
    Sqlite => "sqlite"
    Postgres => "postgres"
    Mysql => "mysql"
  }
}
