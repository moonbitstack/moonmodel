// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `#model.derive` on a struct, with `#model.field` or `#model.skip` on its
/// fields, turned into `T::describe()`. On an enum it names the values a field of
/// that type may take.
priv struct Derive {}

///|
impl @gen.Generator for Derive with fn name(_) {
  "moonmodel"
}

///|
let derive_spec : @attr.Spec = @attr.Spec::new("model.derive")
  .optional("name", Str)
  .optional("doc", Str)

///|
let field_spec : @attr.Spec = @attr.Spec::new("model.field")
  .optional("name", Str)
  .optional("kind", Str)
  .optional("model", Str)
  .optional("doc", Str)
  .optional("required", Bool)
  .optional("nullable", Bool)
  .optional("default", Str)
  .optional("least", Str)
  .optional("most", Str)
  .optional("over", Str)
  .optional("under", Str)
  .optional("step", Str)
  .optional("shortest", Str)
  .optional("longest", Str)
  .optional("pattern", Str)
  .optional("format", Str)
  .many("option", Str)
  .optional("distinct", Bool)
  .optional("unique", Bool)

///|
let skip_spec : @attr.Spec = @attr.Spec::new("model.skip")

///|
/// The types annotated in these files, which is what a field may refer to by
/// its bare name.
priv struct Known {
  structs : Map[String, String]
  enums : Map[String, Array[String]]
}

///|
/// Where `attr` is written, as `file:line:column`.
fn at(attr : @attribute.Attribute, file : String) -> String {
  "\{file}:\{attr.loc.start.lnum}:\{attr.loc.start.column()}"
}

///|
/// The `#model.*` attributes among `attrs`. One that does not parse is refused
/// here rather than passed over, since `@attr.under` sees only those that parse.
fn model_attrs(
  attrs : @list.List[@attribute.Attribute],
  file : String,
) -> Array[@attribute.Attribute] raise {
  for attr in attrs {
    if @attr.name_of(attr) is None && attr.raw.has_prefix("#model.") {
      fail("\{at(attr, file)}: `\{attr.raw}` does not parse as an annotation")
    }
  }
  @attr.under(attrs, "model")
}

///|
fn quoted(text : String) -> String {
  @quote.string(text).to_string()
}

///|
fn text_of(args : @attr.Args?, key : String) -> String? {
  args.bind(a => a.str(key))
}

///|
fn flag_of(args : @attr.Args?, key : String) -> Bool? {
  args.bind(a => a.bool(key))
}

///|
/// The bounds written on a field, as the arguments of `Check::new`.
fn bounds(
  args : @attr.Args?,
  kind : String,
  where_ : String,
) -> Array[String] raise {
  let out = []
  let numeric = kind is ("Int" | "Big" | "Real")
  let sized = kind == "Text" || kind.has_prefix("List(")
  for key in ["least", "most", "over", "under", "step"] {
    if text_of(args, key) is Some(text) {
      if !numeric {
        fail("\{where_}: `\{key}` bounds a number, and this is \{kind}")
      }
      out.push("\{key}=\{real(text, where_)}")
    }
  }
  for key in ["shortest", "longest"] {
    if text_of(args, key) is Some(text) {
      if !sized {
        fail("\{where_}: `\{key}` bounds text or a list, and this is \{kind}")
      }
      out.push("\{key}=\{whole(text, where_)}")
    }
  }
  for key in ["pattern", "format"] {
    if text_of(args, key) is Some(text) {
      if kind != "Text" {
        fail("\{where_}: `\{key}` is for text, and this is \{kind}")
      }
      out.push("\{key}=\{quoted(text)}")
    }
  }
  if flag_of(args, "distinct") is Some(true) {
    if !kind.has_prefix("List(") {
      fail("\{where_}: `distinct` is for a list, and this is \{kind}")
    }
    out.push("distinct=true")
  }
  if flag_of(args, "unique") is Some(true) {
    out.push("unique=true")
  }
  out
}

///|
/// A field as the `Field::new` call it declares, `None` for a skipped one.
fn field_call(
  field : @gen.Field,
  known : Known,
  fallback : String,
  file : String,
) -> String? raise {
  let mut note = None
  let mut skip = None
  for attr in model_attrs(field.attrs, file) {
    match @attr.name_of(attr) {
      Some("model.field") if note is None => note = Some(attr)
      Some("model.skip") if skip is None => skip = Some(attr)
      Some("model.field" | "model.skip" as name) =>
        fail("\{at(attr, file)}: `#\{name}` is written twice")
      Some(name) =>
        fail(
          "\{at(attr, file)}: `#\{name}` is not a moonmodel field annotation",
        )
      None => fail("\{at(attr, file)}: unnamed")
    }
  }
  if skip is Some(s) {
    ignore(skip_spec.bind(s))
    if note is Some(n) {
      fail("\{at(n, file)}: a skipped field takes no `#model.field`")
    }
    return None
  }
  let where_ = match note {
    Some(n) => at(n, file)
    None => fallback
  }
  let what = "\{where_}: field `\{field.name}`"
  let args = match note {
    Some(n) => Some(field_spec.bind(n))
    None => None
  }
  let (base, optional) = match inner_option(field.ty) {
    Some(inner) => (inner, true)
    None => (field.ty, false)
  }
  if text_of(args, "kind") is Some(_) && text_of(args, "model") is Some(_) {
    fail("\{what}: give `kind` or `model`, not both")
  }
  let kind = match (text_of(args, "kind"), text_of(args, "model")) {
    (Some(name), _) =>
      match kind_named(name) {
        Some(k) => k
        None => fail("\{what}: `kind=\{quoted(name)}` is not a type")
      }
    (_, Some(name)) => "Ref(\{quoted(name)})"
    _ =>
      match kind_of(base, known) {
        Some(k) => k
        None =>
          fail(
            "\{what}: `\{field.ty}` has no type of its own; annotate it, or give `#model.field(kind=...)` or `model=`",
          )
      }
  }
  let parts = [quoted(text_of(args, "name").unwrap_or(field.name)), kind]
  let default = text_of(args, "default")
  let required = flag_of(args, "required").unwrap_or(
    !optional && default is None,
  )
  if !required {
    parts.push("required=false")
  }
  if flag_of(args, "nullable").unwrap_or(optional) {
    parts.push("nullable=true")
  }
  if text_of(args, "doc") is Some(doc) {
    parts.push("doc=\{quoted(doc)}")
  }
  if default is Some(text) {
    parts.push("default=\{value(text, kind, where_)}")
  }
  let check = bounds(args, kind, what)
  let options = args.map(a => a.strs("option")).unwrap_or([])
  let options = if options.is_empty() {
    known.enums.get(base.trim(chars=" ").to_owned()).unwrap_or([])
  } else {
    options
  }
  if !options.is_empty() {
    let values = options.map(v => value(v, kind, where_))
    check.push("options=[\{values.join(", ")}]")
  }
  if !check.is_empty() {
    parts.push("check=@moonmodel.Check::new(\{check.join(", ")})")
  }
  Some("@moonmodel.Field::new(\{parts.join(", ")})")
}

///|
/// The description of one `#model.derive` struct: a private `let` holding it, and
/// `T::describe()` returning it.
fn describe(
  note : @attribute.Attribute,
  name : String,
  fields : Array[@gen.Field],
  public : Bool,
  known : Known,
  file : String,
) -> String raise {
  let where_ = at(note, file)
  let args = derive_spec.bind(note)
  let model_name = args.str("name").unwrap_or(name)
  let calls = []
  let names : Map[String, Unit] = Map([])
  for field in fields {
    if field_call(field, known, where_, file) is Some(call) {
      calls.push(call)
      let key = wire_name(field, file)
      if names.contains(key) {
        fail("\{where_}: `\{name}` declares field `\{key}` twice")
      }
      names.set(key, ())
    }
  }
  if calls.is_empty() {
    fail("\{where_}: `\{name}` declares no field")
  }
  let doc_arg = match args.str("doc") {
    Some(doc) => "\n  doc=\{quoted(doc)},"
    None => ""
  }
  let vis = if public { "pub " } else { "" }
  let holder = snake(name) + "_description"
  (
    $|let \{holder} : @moonmodel.Model = @moonmodel.Model::new(
    $|  \{quoted(model_name)},
    $|  [\{calls.join(", ")}],\{doc_arg}
    $|)
    $|
    $|\{vis}fn \{name}::describe() -> @moonmodel.Model {
    $|  \{holder}
    $|}
  )
}

///|
/// The name a field goes by in its model.
fn wire_name(field : @gen.Field, file : String) -> String raise {
  for attr in model_attrs(field.attrs, file) {
    if @attr.name_of(attr) is Some("model.field") {
      return field_spec.bind(attr).str("name").unwrap_or(field.name)
    }
  }
  field.name
}

///|
/// The one `#model.derive` among `attrs`, refusing a second and anything else
/// that does not belong on a declaration.
fn derive_note(
  attrs : @list.List[@attribute.Attribute],
  file : String,
) -> @attribute.Attribute? raise {
  let found = []
  for attr in model_attrs(attrs, file) {
    match @attr.name_of(attr) {
      Some("model.derive") => found.push(attr)
      Some(name) =>
        fail("\{at(attr, file)}: `#\{name}` goes on a field, not a declaration")
      None => ()
    }
  }
  match found {
    [] => None
    [one] => Some(one)
    [_, second, ..] =>
      fail("\{at(second, file)}: `#model.derive` is written twice")
  }
}

///|
impl @gen.Generator for Derive with fn generate(_, decls) {
  let known = { structs: Map([]), enums: Map([]), }
  for decl in decls {
    match decl {
      Struct(name~, attrs~, file~, ..) =>
        if derive_note(attrs, file) is Some(note) {
          let args = derive_spec.bind(note)
          known.structs[name] = args.str("name").unwrap_or(name)
        }
      Enum(name~, constructors~, attrs~, file~, ..) =>
        if derive_note(attrs, file) is Some(_) {
          known.enums[name] = constructors
        }
      _ => ()
    }
  }
  let out = []
  for decl in decls {
    match decl {
      Struct(name~, fields~, attrs~, public~, file~, ..) =>
        match derive_note(attrs, file) {
          Some(note) =>
            out.push(describe(note, name, fields, public, known, file))
          None =>
            for field in fields {
              if model_attrs(field.attrs, file) is [first, ..] {
                fail(
                  "\{at(first, file)}: `\{name}` has no `#model.derive`, so its fields take no `#model.*`",
                )
              }
            }
        }
      Func(attrs~, file~, ..) =>
        if model_attrs(attrs, file) is [first, ..] {
          fail("\{at(first, file)}: `#model.*` goes on a struct or an enum")
        }
      _ => ()
    }
  }
  @quote.items(out.join("\n\n")).render()
}
