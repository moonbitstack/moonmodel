// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Print the corpus and its four projections as one JSON document, for
/// `scripts/conformance/check.py` to read.
fn main {
  println(@moonjson.dumps(bundle(), indent=2, sort=true))
}
