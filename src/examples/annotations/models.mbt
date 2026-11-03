// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The values a role may take: the constructors, as text.
#model.derive
pub enum Role {
  Admin
  Member
  Guest
}

///|
/// A model another one refers to. `name=` is what the projections call it.
#model.derive(name="Address", doc="where somebody lives")
pub struct Home {
  city : String
  #model.field(pattern="^[0-9]{5}$")
  zip : String
}

///|
/// A field without annotations is required, named after itself, and typed by its
/// own type. `T?` may be left out and may be null; a default may be left out.
/// `#model.skip` keeps a field out of the description altogether.
#model.derive(doc="somebody with an account")
pub struct User {
  #model.field(unique=true, doc="assigned by the database")
  id : Int64
  #model.field(shortest="1", longest="64")
  name : String
  #model.field(format="email")
  email : String?
  #model.field(least="0", most="150")
  age : Int32?
  role : Role
  #model.field(default="1.0", over="0")
  weight : Double
  home : Home
  #model.field(distinct=true, longest="8")
  tags : Array[String]
  #model.field(kind="stamp")
  joined : String
  #model.field(kind="uint16-be-ref")
  count : Int32
  #model.skip
  visits : Int32
}
