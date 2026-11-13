// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What an instance is supposed to do, stated once and read three ways: the
// harness asks an independent validator, `cases_wbtest.mbt` asks this
// library's entry, and the labels are what both are held to. A label is
// therefore written from the description, never from what the library happens
// to answer — otherwise the three would agree on the same mistake.

///|
/// One instance and the verdict the description calls for.
struct Case {
  model : String
  data : Json
  valid : Bool
  why : String
}

///|
fn Case::new(model : String, data : Json, valid : Bool, why : String) -> Case {
  { model, data, valid, why, }
}

///|
/// Every instance the harness reads.
fn cases() -> Array[Case] {
  let out = []
  for
    group in [
      account_cases(),
      address_cases(),
      post_cases(),
      order_cases(),
      invoice_cases(),
      packet_cases(),
    ] {
    for one in group {
      out.push(one)
    }
  }
  out
}

///|
/// `base` with one key replaced or added, so a case can say what it changes
/// and leave the rest of a good instance alone.
fn replacing(base : Json, key : String, value : Json) -> Json {
  match base {
    Object(map) => {
      let out : Map[String, Json] = Map([])
      for name, one in map {
        out[name] = one
      }
      out[key] = value
      Json::object(out)
    }
    other => other
  }
}

///|
/// `n` copies of one character, for a bound stated as a count.
fn filler(c : Char, n : Int32) -> String {
  let out = StringBuilder()
  for _ in 0..<n {
    out.write_char(c)
  }
  out.to_string()
}

///|
/// `Account`: the required seven, the nullable pair, the closed set, the two
/// open bounds, the list's own bounds, and a reference that has to resolve.
fn account_cases() -> Array[Case] {
  let model = "Account"
  let good : Json = {
    "id": 1,
    "name": "ada",
    "role": "admin",
    "home": { "city": "Kyoto" },
    "created": "2026-01-02T03:04:05Z",
  }
  [
    Case::new(model, good, true, "an instance that meets every bound"),
    Case::new(
      model,
      {
        "name": "ada",
        "role": "admin",
        "home": { "city": "Kyoto" },
        "created": "2026-01-02T03:04:05Z",
      },
      false,
      "id is required",
    ),
    Case::new(
      model,
      replacing(good, "id", Json::number(1.5)),
      false,
      "id is an integer",
    ),
    Case::new(
      model,
      replacing(good, "name", Json::string(filler('a', 65))),
      false,
      "name is longer than 64",
    ),
    Case::new(
      model,
      replacing(good, "name", Json::string("")),
      false,
      "name is shorter than 1",
    ),
    Case::new(
      model,
      replacing(good, "name", Json::string(filler('a', 64))),
      true,
      "64 characters is the longest name",
    ),
    Case::new(
      model,
      replacing(good, "age", Json::number(150.0)),
      true,
      "150 is the most",
    ),
    Case::new(
      model,
      replacing(good, "age", Json::number(151.0)),
      false,
      "151 is past the most",
    ),
    Case::new(
      model,
      replacing(good, "age", Json::number(-1.0)),
      false,
      "a negative age is below the least",
    ),
    Case::new(
      model,
      replacing(good, "age", Json::null()),
      true,
      "age may be null",
    ),
    Case::new(
      model,
      replacing(good, "email", Json::null()),
      true,
      "email may be null",
    ),
    Case::new(
      model,
      replacing(good, "email", Json::string("ada@example.com")),
      true,
      "email may be present",
    ),
    Case::new(
      model,
      replacing(good, "role", Json::string("member")),
      true,
      "member is in the closed set",
    ),
    Case::new(
      model,
      replacing(good, "role", Json::string("guest")),
      false,
      "guest is not in the closed set",
    ),
    Case::new(
      model,
      replacing(good, "role", Json::number(1.0)),
      false,
      "the closed set is of strings",
    ),
    Case::new(
      model,
      replacing(good, "weight", Json::number(0.5)),
      true,
      "half a unit is inside both bounds",
    ),
    Case::new(
      model,
      replacing(good, "weight", Json::number(0.0)),
      false,
      "zero is not over zero",
    ),
    Case::new(
      model,
      replacing(good, "weight", Json::number(10.0)),
      false,
      "ten is not under ten",
    ),
    Case::new(
      model,
      replacing(
        good,
        "tags",
        Json::array([Json::string("a"), Json::string("b")]),
      ),
      true,
      "two distinct tags",
    ),
    Case::new(
      model,
      replacing(good, "tags", Json::array([])),
      false,
      "the list is shorter than 1",
    ),
    Case::new(
      model,
      replacing(
        good,
        "tags",
        Json::array(["a", "b", "c", "d", "e", "f"].map(Json::string)),
      ),
      false,
      "the list is longer than 5",
    ),
    Case::new(
      model,
      replacing(
        good,
        "tags",
        Json::array([Json::string("a"), Json::string("a")]),
      ),
      false,
      "the items do not differ",
    ),
    Case::new(
      model,
      replacing(
        good,
        "tags",
        Json::array([Json::string("a"), Json::number(1.0)]),
      ),
      false,
      "the items are text",
    ),
    Case::new(
      model,
      replacing(good, "home", Json::object(Map([]))),
      false,
      "city is required",
    ),
    Case::new(
      model,
      replacing(good, "home", Json::string("Kyoto")),
      false,
      "home is an object",
    ),
    Case::new(
      model,
      replacing(good, "active", Json::string("yes")),
      false,
      "active is a boolean",
    ),
    Case::new(
      model,
      replacing(good, "created", Json::number(1.0)),
      false,
      "created is a string",
    ),
    Case::new(
      model,
      replacing(good, "nickname", Json::string("ada")),
      true,
      "an unknown key is allowed",
    ),
  ]
}

///|
/// `Address`: the pattern, the mapping with open keys, and the model written
/// where it stands.
fn address_cases() -> Array[Case] {
  let model = "Address"
  [
    Case::new(model, { "city": "Kyoto" }, true, "the one required field"),
    Case::new(model, { "city": "Kyoto", "zip": "12345" }, true, "five digits"),
    Case::new(
      model,
      { "city": "Kyoto", "zip": "1234" },
      false,
      "the zip is not five digits",
    ),
    Case::new(
      model,
      { "city": "Kyoto", "zip": "abcde" },
      false,
      "the zip is not digits",
    ),
    Case::new(
      model,
      { "city": "Kyoto", "labels": { "ward": "Sakyo" } },
      true,
      "a mapping whose values are text",
    ),
    Case::new(
      model,
      { "city": "Kyoto", "labels": { "ward": 7 } },
      false,
      "a mapping whose value is not text",
    ),
    Case::new(
      model,
      { "city": "Kyoto", "geo": { "lat": 35.0, "lon": 135.0 } },
      true,
      "the nested model as an object",
    ),
    Case::new(
      model,
      { "city": "Kyoto", "geo": { "lat": 91.0, "lon": 0.0 } },
      false,
      "a latitude past the pole",
    ),
    Case::new(
      model,
      { "city": "Kyoto", "geo": { "lat": 35.0 } },
      false,
      "the nested model needs both its fields",
    ),
    Case::new(model, { "city": 7 }, false, "the city is text"),
  ]
}

///|
/// `Post`: a model that points at itself, one level down.
fn post_cases() -> Array[Case] {
  let model = "Post"
  let good : Json = { "id": 1, "title": "hello" }
  [
    Case::new(model, good, true, "a post with no parent"),
    Case::new(
      model,
      replacing(good, "parent", { "id": 2, "title": "there" }),
      true,
      "a post whose parent is a post",
    ),
    Case::new(
      model,
      replacing(good, "parent", { "id": 2 }),
      false,
      "the parent is missing its title",
    ),
    Case::new(
      model,
      replacing(good, "parent", Json::null()),
      true,
      "no parent is null",
    ),
    Case::new(
      model,
      replacing(good, "title", Json::string("")),
      false,
      "an empty title",
    ),
  ]
}

///|
/// `Order`: a reference two models deep, and a bound on a real number.
fn order_cases() -> Array[Case] {
  let model = "Order"
  let buyer : Json = {
    "id": 2,
    "name": "grace",
    "role": "member",
    "home": { "city": "Kyoto" },
    "created": "2026-01-02T03:04:05Z",
  }
  let good : Json = {
    "id": 1,
    "buyer": buyer,
    "total": 9.5,
    "placed": "2026-01-02T03:04:05Z",
  }
  [
    Case::new(model, good, true, "an order and the account that placed it"),
    Case::new(
      model,
      replacing(good, "total", Json::number(0.0)),
      true,
      "a free order is still an order",
    ),
    Case::new(
      model,
      replacing(good, "total", Json::number(-1.0)),
      false,
      "a negative total",
    ),
    Case::new(
      model,
      { "id": 1, "total": 1, "placed": "2026-01-02T03:04:05Z" },
      false,
      "an order with no buyer",
    ),
    Case::new(
      model,
      replacing(good, "buyer", replacing(buyer, "role", Json::string("owner"))),
      false,
      "the account's own closed set still applies",
    ),
  ]
}

///|
/// `Invoice`: field names that are reserved words in SQL, which the document
/// projections have no quarrel with.
fn invoice_cases() -> Array[Case] {
  let model = "Invoice"
  let good : Json = {
    "number": "A-1",
    "order": "PO-1",
    "group": "g",
    "total": 1.5,
  }
  [
    Case::new(model, good, true, "three text fields and a total"),
    Case::new(
      model,
      replacing(good, "number", Json::string(filler('A', 33))),
      false,
      "the number is longer than 32",
    ),
    Case::new(
      model,
      replacing(good, "number", Json::string(filler('A', 32))),
      true,
      "32 characters is the longest number",
    ),
    Case::new(
      model,
      { "number": "A-1", "order": "PO-1", "total": 1.5 },
      false,
      "the group is required",
    ),
    Case::new(
      model,
      replacing(good, "total", Json::string("1.5")),
      false,
      "the total is a number",
    ),
  ]
}

///|
/// `Packet`: the two escapes, where a width is a format and nothing more.
fn packet_cases() -> Array[Case] {
  let model = "Packet"
  [
    Case::new(model, { "counter": 1 }, true, "the width is not a bound"),
    Case::new(
      model,
      { "counter": 70000 },
      true,
      "a number past 16 bits is still a number",
    ),
    Case::new(model, { "counter": "1" }, false, "the counter is a number"),
    Case::new(
      model,
      {
        "counter": 1,
        "ratio": 0.25,
        "payload": "AA==",
        "note": { "anything": [1, 2] },
        "flags": "AB",
      },
      true,
      "every field at once",
    ),
    Case::new(
      model,
      { "counter": 1, "flags": "ab" },
      false,
      "the hand-written pattern",
    ),
    Case::new(
      model,
      { "counter": 1, "payload": 5 },
      false,
      "bytes are a string",
    ),
    Case::new(
      model,
      { "counter": 1, "ratio": "0.25" },
      false,
      "the ratio is a number",
    ),
  ]
}

///|
/// A statement the engine must refuse or accept, and why.
struct Probe {
  model : String
  sql : String
  valid : Bool
  why : String
}

///|
fn Probe::new(
  model : String,
  sql : String,
  valid : Bool,
  why : String,
) -> Probe {
  { model, sql, valid, why, }
}

///|
/// Statements run against the tables the SQLite dialect declares. A bound that
/// only exists in the schema the library writes is not a bound an engine
/// enforces, so these check the engine's answer, not the text.
fn probes() -> Array[Probe] {
  let at = "2026-01-02T03:04:05Z"
  let long = filler('a', 65)
  [
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created) VALUES (1, 'ada', 'admin', '\{at}')",
      true,
      "the columns that are required",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created) VALUES (2, '\{long}', 'admin', '\{at}')",
      false,
      "the length bound is a CHECK",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created, age) VALUES (3, 'ada', 'admin', '\{at}', 151)",
      false,
      "the upper bound is a CHECK",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created, age) VALUES (4, 'ada', 'admin', '\{at}', 150)",
      true,
      "the bound is closed",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created) VALUES (5, 'ada', 'guest', '\{at}')",
      false,
      "the closed set is an IN list",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created, weight) VALUES (6, 'ada', 'admin', '\{at}', 0.5)",
      true,
      "inside the open bounds",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created, weight) VALUES (7, 'ada', 'admin', '\{at}', 0)",
      false,
      "an open bound excludes its own value",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created) VALUES (1, 'ada', 'admin', '\{at}')",
      false,
      "the id is UNIQUE",
    ),
    Probe::new(
      "Account",
      "INSERT INTO Account (id, name, role, created) VALUES (8, NULL, 'admin', '\{at}')",
      false,
      "a required field is NOT NULL",
    ),
    Probe::new(
      "Address", "INSERT INTO Address (city, zip) VALUES ('Kyoto', '12345')", true,
      "a table with no bound at all",
    ),
    Probe::new(
      "Address", "INSERT INTO Address (zip) VALUES ('12345')", false, "the city is NOT NULL",
    ),
    Probe::new(
      "Post", "INSERT INTO Post (id, title) VALUES (1, 'hello')", true, "a title of one character",
    ),
    Probe::new(
      "Post", "INSERT INTO Post (id, title) VALUES (2, '')", false, "an empty title",
    ),
    // The table and two of its columns are words every dialect reserves.
    Probe::new(
      "Order",
      "INSERT INTO \"Order\" (id, total, placed) VALUES (1, 9.5, '\{at}')",
      true,
      "the table is quoted",
    ),
    Probe::new(
      "Order",
      "INSERT INTO \"Order\" (id, total, placed) VALUES (2, -1, '\{at}')",
      false,
      "the total is not negative",
    ),
    Probe::new(
      "Invoice", "INSERT INTO Invoice (number, \"order\", \"group\", total) VALUES ('A-1', 'PO-1', 'g', 1.5)",
      true, "quoted column names",
    ),
    Probe::new(
      "Invoice",
      "INSERT INTO Invoice (number, \"order\", \"group\") VALUES ('\{filler('A', 33)}', 'PO-1', 'g')",
      false,
      "the number is too long",
    ),
    Probe::new(
      "Packet", "INSERT INTO Packet (counter, ratio, payload) VALUES (1, 0.5, x'00')",
      true, "a counter, a ratio and a blob",
    ),
  ]
}
