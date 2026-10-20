// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where `Ref` points when a schema is written as a fragment of a larger
/// document (`$defs` is 2020-12's; older drafts said `definitions`).
pub let defs : String = "#/$defs/"

///|
/// A model as a JSON Schema object.
///
/// `at` is the prefix a `Ref` is resolved against, so the same model can be
/// written into a bare document or into one component of an OpenAPI file by
/// changing one argument rather than by rewriting the schema.
///
/// `draft` writes the `$schema` line. Left out there is none, which is what a
/// fragment wants; a whole document should say which dialect it is.
pub fn of(
  model : @moonmodel.Model,
  at~ : String = defs,
  draft? : String,
  title~ : Bool = true,
) -> Json {
  let out : Map[String, Json] = Map([])
  match draft {
    Some(draft) => out["$schema"] = Json::string(draft)
    None => ()
  }
  out["type"] = Json::string("object")
  // A schema filed under its own name needs no title saying the same thing;
  // a standalone one does.
  if title && model.name != "" {
    out["title"] = Json::string(model.name)
  }
  if model.doc != "" {
    out["description"] = Json::string(model.doc)
  }
  let properties : Map[String, Json] = Map([])
  for field in model.fields {
    properties[field.name] = property(field, at)
  }
  out["properties"] = Json::object(properties)
  let required = model.required()
  if required.length() > 0 {
    out["required"] = Json::array(required.map(Json::string))
  }
  Json::object(out)
}

///|
/// A whole document: the model, and every model it mentions, under `$defs`.
///
/// `known` is where the referenced models are looked up. One that is missing
/// is left as a dangling `$ref` rather than refused — a schema that names a
/// type defined elsewhere is ordinary, and this package cannot know whether
/// the reader has it.
pub fn document(
  model : @moonmodel.Model,
  known~ : Array[@moonmodel.Model] = [],
  draft~ : String = "https://json-schema.org/draft/2020-12/schema",
) -> Json {
  let root = of(model, draft~)
  let wanted = reachable(model, known)
  if wanted.length() == 0 {
    return root
  }
  let defined : Map[String, Json] = Map([])
  for one in wanted {
    defined[one.name] = of(one)
  }
  match root {
    Object(fields) => {
      fields["$defs"] = Json::object(defined)
      Json::object(fields)
    }
    other => other
  }
}

///|
/// Every model this one reaches, directly or through another, without
/// repeats and without itself.
fn reachable(
  model : @moonmodel.Model,
  known : Array[@moonmodel.Model],
) -> Array[@moonmodel.Model] {
  let out = []
  let seen = [model.name]
  let pending = model.mentions()
  while pending.length() > 0 {
    let name = pending.remove(0)
    if seen.contains(name) {
      continue
    }
    seen.push(name)
    for one in known {
      if one.name == name {
        out.push(one)
        for next in one.mentions() {
          pending.push(next)
        }
        break
      }
    }
  }
  out
}

///|
/// One field: its type, its bounds, whatever was said about it.
fn property(field : @moonmodel.Field, at : String) -> Json {
  let out = shape(field.kind, at)
  match out {
    Object(fields) => {
      if field.nullable {
        // 2020-12 says a nullable value by listing both types, which is the
        // form OpenAPI 3.1 adopted too. Draft 4 and OpenAPI 3.0 need a
        // keyword of their own, which is `open`'s problem, not this one's.
        match fields.get("type") {
          Some(String(one)) =>
            fields["type"] = Json::array([
              Json::string(one),
              Json::string("null"),
            ])
          _ => ()
        }
      }
      if field.doc != "" {
        fields["description"] = Json::string(field.doc)
      }
      match field.default {
        Some(value) => fields["default"] = value
        None => ()
      }
      bounds(field.check, fields)
      Json::object(fields)
    }
    other => other
  }
}

///|
/// A type as the keywords that describe it.
fn shape(kind : @moonmodel.Type, at : String) -> Json {
  match kind {
    Bool => Json::object(Map([("type", Json::string("boolean"))]))
    Int =>
      Json::object(
        Map([
          ("type", Json::string("integer")),
          ("format", Json::string("int32")),
        ]),
      )
    Big =>
      Json::object(
        Map([
          ("type", Json::string("integer")),
          ("format", Json::string("int64")),
        ]),
      )
    Real => Json::object(Map([("type", Json::string("number"))]))
    Text => Json::object(Map([("type", Json::string("string"))]))
    // There is no byte type in JSON, so the convention every schema follows
    // is a base64 string wearing a format.
    Bytes =>
      Json::object(
        Map([("type", Json::string("string")), ("format", Json::string("byte"))]),
      )
    Stamp =>
      Json::object(
        Map([
          ("type", Json::string("string")),
          ("format", Json::string("date-time")),
        ]),
      )
    List(inner) =>
      Json::object(
        Map([("type", Json::string("array")), ("items", shape(inner, at))]),
      )
    Dict(inner) =>
      Json::object(
        Map([
          ("type", Json::string("object")),
          ("additionalProperties", shape(inner, at)),
        ]),
      )
    Ref(name) => Json::object(Map([("$ref", Json::string(at + name))]))
    // A model with no name of its own is written where it stands; there is
    // nothing to hoist it under and nothing to point at it.
    Nest(model) => of(model, at~)
    // The empty schema, which accepts anything. Not `"type": "any"`, which no
    // draft has ever had.
    Any => Json::object(Map([]))
    Raw(written) => written
  }
}

///|
/// The bounds, written under the names JSON Schema gives them.
fn bounds(check : @moonmodel.Check, out : Map[String, Json]) -> Unit {
  if check.is_empty() {
    return
  }
  number(check.least, "minimum", out)
  number(check.most, "maximum", out)
  number(check.over, "exclusiveMinimum", out)
  number(check.under, "exclusiveMaximum", out)
  number(check.step, "multipleOf", out)
  // One pair of names covers strings and arrays alike, and which pair applies
  // is read off the type that is already written here.
  let array = out.get("type") is Some(String("array"))
  count(check.shortest, if array { "minItems" } else { "minLength" }, out)
  count(check.longest, if array { "maxItems" } else { "maxLength" }, out)
  match check.pattern {
    Some(pattern) => out["pattern"] = Json::string(pattern)
    None => ()
  }
  match check.format {
    // A type that already named its own format keeps it: Stamp is
    // `date-time`, and a check saying otherwise is the caller contradicting
    // the type.
    Some(format) =>
      if out.get("format") is None {
        out["format"] = Json::string(format)
      }
    None => ()
  }
  if check.options.length() > 0 {
    out["enum"] = Json::array(check.options)
  }
  if check.distinct {
    out["uniqueItems"] = Json::boolean(true)
  }
}

///|
fn number(value : Double?, name : String, out : Map[String, Json]) -> Unit {
  match value {
    Some(value) => out[name] = Json::number(value)
    None => ()
  }
}

///|
fn count(value : Int32?, name : String, out : Map[String, Json]) -> Unit {
  match value {
    Some(value) => out[name] = Json::number(value.to_double())
    None => ()
  }
}
