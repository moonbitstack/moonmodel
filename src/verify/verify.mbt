// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a description could not be read as a schema.
pub(all) suberror Refused {
  /// A model the description names, which the call did not hand over.
  ///
  /// A reference the document cannot resolve is not an instance that fails to
  /// conform; refusing here keeps the two apart, because a validator asked
  /// about an unresolvable `$ref` can only answer "no" to everything.
  Missing(name~ : String)
}

///|
/// The model as a schema a reader can check instances against.
///
/// A description is not a validator and does not become one here: it is
/// written out as JSON Schema 2020-12 — the form the projections already agree
/// on — and handed to something that knows the specification. What an instance
/// is checked against is therefore the schema this library publishes, not a
/// second opinion about it.
///
/// `known` is where the models a `Ref` names are looked up, and one that is
/// missing is refused by name: a document that points at a model it does not
/// carry cannot be checked, and quietly refusing every instance would blame
/// the instance for it.
///
/// Reading a description that is not a schema at all — a `Raw` that says
/// something no draft defines — raises too. Both are defects in the
/// description, which is a different thing from an instance that does not
/// conform.
pub fn schema(
  model : @moonmodel.Model,
  known~ : Array[@moonmodel.Model] = [],
) -> @moonschema.Schema raise {
  for name in model.mentions() {
    if name == model.name {
      continue
    }
    let mut carried = false
    for one in known {
      if one.name == name {
        carried = true
        break
      }
    }
    if !carried {
      raise Refused::Missing(name~)
    }
  }
  @moonschema.Schema::new(@json.document(model, known~))
}

///|
/// Whether an instance conforms.
///
/// One call reads the schema and checks one instance. Checking many is worth
/// holding the `Schema` from `schema` instead, which reads the description
/// once.
pub fn valid(
  model : @moonmodel.Model,
  instance : Json,
  known~ : Array[@moonmodel.Model] = [],
) -> Bool raise {
  schema(model, known~).valid(instance)
}

///|
/// Every reason the instance does not conform, in the order the walk found
/// them; empty when it does.
///
/// A fault says where in the instance it happened and which keyword refused
/// it, so a caller can answer with the field's name rather than with "no".
pub fn faults(
  model : @moonmodel.Model,
  instance : Json,
  known~ : Array[@moonmodel.Model] = [],
) -> Array[@moonschema.Fault] raise {
  schema(model, known~).faults(instance)
}
