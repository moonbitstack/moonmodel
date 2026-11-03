// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The sheet is data for a page, so what matters is that every field is in it
/// and that the counts agree with the fields.
test "the sheet carries every field and its counts" {
  let text = sheet()
  assert_true(text.contains("\"model\": \"User\""))
  assert_true(text.contains("\"fields\": 10"))
  assert_true(text.contains("\"name\": \"count\""))
  assert_true(text.contains("\"spell\": \"integer uint16\""))
  assert_true(text.contains("\"why\": \"GraphQL's Int is 32 bits"))
}

///|
/// A field a projection had nothing to say about is told apart from one it
/// described: the first carries a note letter, the second does not.
test "what a projection could not carry is marked" {
  let text = sheet()
  assert_true(text.contains("\"sql\": {\"lines\": [], \"spell\": \"—\""))
  assert_true(text.contains("\"station_lost\": \"f\""))
}
