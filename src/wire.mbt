// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which end of a number comes first.
pub(all) enum Order {
  Little
  /// Most significant byte first, which is what a network order is.
  Big
} derive(Eq, Debug)

///|
pub extend Order with Eq::{equal, not_equal}

///|
pub extend Order with Debug::{to_repr}

///|
/// A value as a byte format lays it out.
///
/// A document says what a value is. A format that writes bytes also fixes how
/// wide it is, whether it carries a sign, which byte comes first, and whether
/// it is written where it stands or as an offset to somewhere else. The four
/// belong to the type rather than to the value: every value of the type is
/// laid out the same way, and a reader has to know before it looks at one.
///
/// A projection that writes a document reads `kind` and says nothing about the
/// rest, because a document has no width and no offset. The width alone is
/// still worth writing as a `format`, which is how the JSON family already
/// distinguishes `int32` from `int64`.
pub(all) struct Layout {
  /// The value's own kind.
  kind : Type
  /// The width a format fixes, in bits — 8, 16, 32 or 64. Absent leaves the
  /// width to the format's own table, which is what a plain `Int` says.
  ///
  /// It agrees with `kind` where `kind` has a width of its own: `Int` is 32
  /// bits and `Big` 64. A layout that says otherwise is written at the width
  /// it states; the word and the projections trust `bits` over `kind`.
  bits : Int32?
  /// Whether the value has no sign bit.
  unsigned : Bool
  /// Which byte of a number comes first.
  order : Order
  /// Whether the value is written as an offset into the buffer rather than
  /// where it stands — which a format that sends a shared value once and
  /// points at it twice has to know before it reads.
  reference : Bool
} derive(Eq, Debug)

///|
pub extend Layout with Eq::{equal, not_equal}

///|
pub extend Layout with Debug::{to_repr}

///|
/// A layout: the kind, and how a format writes it.
///
/// Every part but the kind has the common answer as its default, so a format
/// whose numbers are little-endian and written in place says only the width.
pub fn Layout::new(
  kind : Type,
  bits? : Int32,
  unsigned~ : Bool = false,
  order~ : Order = Little,
  reference~ : Bool = false,
) -> Layout {
  { kind, bits, unsigned, order, reference, }
}

///|
/// The `format` this layout asks for: `int8`, `uint16`, `float32`.
///
/// `None` when the layout fixes no width of its own, or when the kind is not
/// a number — a width on anything else is not a width, and writing one would
/// make a reader think the format had said something it did not.
pub fn Layout::format(self : Layout) -> String? {
  match self.bits {
    Some(bits) =>
      match self.kind {
        Real =>
          match bits {
            32 => Some("float32")
            64 => Some("float64")
            _ => None
          }
        Int | Big => width_word(bits, self.unsigned)
        _ => None
      }
    None => None
  }
}

///|
/// The word for a width, which is the one every schema family already uses for
/// the two widths it has: `int32` and `int64`.
fn width_word(bits : Int32, unsigned : Bool) -> String? {
  match bits {
    8 => Some(if unsigned { "uint8" } else { "int8" })
    16 => Some(if unsigned { "uint16" } else { "int16" })
    32 => Some(if unsigned { "uint32" } else { "int32" })
    64 => Some(if unsigned { "uint64" } else { "int64" })
    _ => None
  }
}

///|
/// The word a scalar type is written with: what `#model.field(kind=…)` takes,
/// and what a report calls it.
///
/// `None` for a type with parts inside — a list, a mapping, a model, a schema
/// written out — because one word cannot carry what is in it. A layout's word
/// adds `-be` for a big-endian number and `-ref` for one written by reference;
/// both are read back by `of_word`, so a word and a type round-trip.
pub fn Type::word(self : Type) -> String? {
  match self {
    Bool => Some("bool")
    Int => Some("int")
    Big => Some("big")
    Real => Some("real")
    Text => Some("text")
    Bytes => Some("bytes")
    Stamp => Some("stamp")
    Any => Some("any")
    Wire(layout) => {
      let base = match layout.bits {
        Some(bits) =>
          match layout.kind {
            Real =>
              match bits {
                32 => Some("float32")
                64 => Some("float64")
                _ => None
              }
            Int | Big => width_word(bits, layout.unsigned)
            other => other.word()
          }
        None => layout.kind.word()
      }
      base.map(word => {
        let mut word = word
        if layout.order is Big {
          word = word + "-be"
        }
        if layout.reference {
          word = word + "-ref"
        }
        word
      })
    }
    _ => None
  }
}

///|
/// The type a word stands for, when it is one of the words `word` writes.
///
/// Read the suffixes from the right first: `uint16-be-ref` is a `uint16` in
/// big-endian order, written by reference. A word is a type's whole spelling,
/// so two words name two types and no two types share a word.
pub fn Type::of_word(word : String) -> Type? {
  let mut rest = word.trim(chars=" ").to_lower()
  let reference = rest.has_suffix("-ref")
  if reference {
    rest = rest.exact_view(end=rest.length() - 4).to_owned()
  }
  let order = if rest.has_suffix("-be") {
    rest = rest.exact_view(end=rest.length() - 3).to_owned()
    Order::Big
  } else {
    Order::Little
  }
  let base = match rest {
    "bool" => Some(Bool)
    "int" => Some(Int)
    "big" => Some(Big)
    "real" => Some(Real)
    "text" => Some(Text)
    "bytes" => Some(Bytes)
    "stamp" => Some(Stamp)
    "any" => Some(Any)
    "int8" => Some(Wire(Layout::new(Int, bits=8)))
    "int16" => Some(Wire(Layout::new(Int, bits=16)))
    "int32" => Some(Wire(Layout::new(Int, bits=32)))
    "int64" => Some(Wire(Layout::new(Big, bits=64)))
    "uint8" => Some(Wire(Layout::new(Int, bits=8, unsigned=true)))
    "uint16" => Some(Wire(Layout::new(Int, bits=16, unsigned=true)))
    "uint32" => Some(Wire(Layout::new(Int, bits=32, unsigned=true)))
    "uint64" => Some(Wire(Layout::new(Big, bits=64, unsigned=true)))
    "float32" => Some(Wire(Layout::new(Real, bits=32)))
    "float64" => Some(Wire(Layout::new(Real, bits=64)))
    _ => None
  }
  match base {
    None => None
    Some(inner) =>
      match inner {
        Wire(layout) => Some(Wire({ ..layout, order, reference, }))
        // A plain scalar takes a layout only when one of the two says
        // something the plain kind does not.
        plain =>
          if order is Little && !reference {
            Some(plain)
          } else {
            Some(Wire(Layout::new(plain, order~, reference~)))
          }
      }
  }
}
