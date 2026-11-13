"""The corpus written a second time, as pydantic models.

The point of writing them again is that the second author is a different
library: nothing here is derived from `src/cmd/conformance`, so a difference in
what the two call a field's type, its bounds or its required set is a real
disagreement about the same description rather than a copy of it.

Two things pydantic states differently on purpose, and the harness does not
hold it to:

* a key that may be absent but may not be null. pydantic spells both as
  `Optional[T] = None`; this library keeps `required` and `nullable` apart, so
  the harness compares the value's type and not whether null is one of them.
* `uniqueItems`, and every bound in `Check` that GraphQL cannot carry. pydantic
  has no field for a list whose items differ, so no twin states it.

`format` is left out for the same reason: pydantic's spelling of `int64` is
`int`, and this library writes the width instead.
"""

from typing import Literal, Optional

from pydantic import BaseModel, Field


class Geo(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class Address(BaseModel):
    city: str
    zip: Optional[str] = Field(default=None, pattern=r"[0-9]{5}")
    labels: Optional[dict[str, str]] = None
    geo: Optional[Geo] = None


class Account(BaseModel):
    id: int
    name: str = Field(min_length=1, max_length=64)
    email: Optional[str] = None
    age: Optional[int] = Field(default=None, ge=0, le=150)
    role: Literal["admin", "member"]
    weight: Optional[float] = Field(default=1.5, gt=0, lt=10)
    tags: Optional[list[str]] = Field(default=None, min_length=1, max_length=5)
    home: Address
    created: str
    active: Optional[bool] = True


class Post(BaseModel):
    id: int
    title: str = Field(min_length=1, max_length=120)
    parent: Optional["Post"] = None


class Order(BaseModel):
    id: int
    buyer: Account
    total: float = Field(ge=0)
    placed: str


class Invoice(BaseModel):
    number: str = Field(max_length=32)
    order: str = Field(max_length=32)
    group: str
    total: float


Post.model_rebuild()

TWINS = {
    "Account": Account,
    "Address": Address,
    "Post": Post,
    "Order": Order,
    "Invoice": Invoice,
}
