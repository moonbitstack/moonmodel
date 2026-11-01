// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Models declared with `#model` annotations. `models.g.mbt` is generated from
/// `models.mbt` by `cmd/derive`; a project wires the generator as a dev_build rule
/// (see the README). The program checks that the generated descriptions equal the
/// hand-written ones in `hand.mbt`, then prints the projections.
///
///     moon run src/examples/annotations
fn main {
  if User::describe() != hand_user() || Home::describe() != hand_home() {
    abort("the annotated models differ from the hand-written ones")
  }
  let roles = [Role::Admin, Member, Guest]
  let ada : User = {
    id: 1,
    name: "ada",
    email: None,
    age: Some(36),
    role: roles[0],
    weight: 1.0,
    home: { city: "London", zip: "12345", },
    tags: ["maths"],
    joined: "1842-01-01T00:00:00Z",
    visits: 0,
  }
  println("\{ada.name} of \{ada.home.city}")
  let user = User::describe()
  println(@sdl.document([user, Home::describe()][:]))
  println(@sql.table(user, dialect=Postgres))
  println(@json.of(user).stringify(indent=2))
  println(@open.of(user, dialect=OpenApi30).stringify(indent=2))
}
