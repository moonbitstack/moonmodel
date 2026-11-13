#!/usr/bin/env python3
"""Write `src/sql/reserved.mbt`: the words SQLite refuses as a bare column name.

    python3 scripts/gen_sql_keywords.py            # rewrite the file
    python3 scripts/gen_sql_keywords.py --check    # fail if it is out of date

The list is not transcribed from documentation: every word in `CANDIDATES` is
offered to the engine as a column name, and the ones the engine refuses are the
ones the library quotes. Running this again against a newer SQLite is therefore
the whole maintenance story.

The candidates are the words that have ever been reserved by the SQL standard,
by SQLite itself, or by MySQL and PostgreSQL, plus the type names the three
dialects spell differently — a word this table misses cannot be found by
guessing, so the table is deliberately generous.
"""

import pathlib
import re
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "sql" / "reserved.mbt"

CANDIDATES = """
abort action add after all alter always analyze and as asc attach autoincrement
before begin between by cascade case cast check collate column commit conflict
constraint create cross current current_date current_time current_timestamp
database default deferrable deferred delete desc detach distinct do drop each
else end escape except exclude exclusive exists explain fail filter first
following for foreign from full generated glob group groups having if ignore
immediate in index indexed initially inner insert instead intersect into is
isnull join key last lateral left like limit match materialized natural no not
nothing notnull null nulls of offset on or order others outer over partition
plan pragma preceding primary query raise range recursive references regexp
reindex release rename replace restrict returning right rollback row rows
savepoint select set table temp temporary then ties to transaction trigger
unbounded union unique update using vacuum values view virtual when where window
with without

add all alter analyze and any array as asc authorization before begin between
bigint binary bit blob boolean both by call cascade case cast char character
check clob close collate column commit connect constraint continue create cross
cube current current_date current_time current_timestamp current_user cursor
date day deallocate dec decimal declare default delete desc describe
deterministic disconnect distinct double drop else end escape except exec
execute exists external false fetch filter float for foreign found free from
full grant group grouping having hour identity if immediate in indicator inner
inout input insensitive insert int integer intersect interval into is isolation
join key language large last lateral leading left like local localtime
localtimestamp match minute module month national natural nchar nclob new no
none not null numeric of old on only open or order out outer output overlaps
overlay parameter partial precision prepare primary procedure range read real
recursive references release result return returns revoke right rollback rollup
row rows savepoint scroll search second select session_user set similar smallint
some space specific sql sqlcode sqlerror sqlexception sqlstate sqlwarning start
substring sum symmetric system_user table temporary then time timestamp
timezone_hour timezone_minute to trailing transaction translate translation
treat trigger trim true union unique unknown update user using value values
varchar varying view when whenever where with year zone

accessible asensitive bigint binary blob call change char condition continue
convert cross current_user cursor database databases day_hour day_microsecond
day_minute day_second dec decimal declare delayed desc describe deterministic
distinct distinctrow div double dual each elseif enclosed escaped exit explain
fetch float float4 float8 force fulltext generated get grant high_priority
hour_microsecond hour_minute hour_second if ignore infile inout insensitive int
int1 int2 int3 int4 int8 integer interval iterate join key keys kill lag last_value
lateral lead leading leave left like limit linear lines load localtime
localtimestamp lock long longblob longtext loop low_priority master_bind match
maxvalue mediumblob mediumint mediumtext middleint minute_microsecond
minute_second mod modifies natural no_write_to_binlog not null numeric of
optimize option optionally out outer outfile over partition precision primary
procedure purge range rank read reads read_write real recursive references
regexp release rename repeat replace require restrict return revoke right rlike
row row_number rows schema schemas second_microsecond select sensitive separator
set show signal smallint spatial specific sql sqlexcept sqlstate sqlwarning
sql_big_result sql_calc_found_rows sql_small_result ssl starting stored
straight_join system table terminated then tinyblob tinyint tinytext to trailing
trigger true undo union unique unlock unsigned update usage use using utc_date
utc_time utc_timestamp values varbinary varchar varcharacter varying virtual when
where while window with write xor year_month zerofill
""".split()


def probe(word: str) -> bool:
    """True when the engine refuses `word` as a bare column name."""
    handle = sqlite3.connect(":memory:")
    try:
        handle.execute(f"CREATE TABLE probe ({word} TEXT)")
        return False
    except sqlite3.OperationalError:
        return True
    finally:
        handle.close()


def keywords() -> list[str]:
    found = sorted({word for word in CANDIDATES if probe(word)})
    if not found:
        sys.exit("the probe found no reserved word at all")
    return found


def render(words: list[str]) -> str:
    body = ",\n".join(f'  "{word}"' for word in words)
    return f'''// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Generated by `scripts/gen_sql_keywords.py`; do not edit.
//
// Every word here is one SQLite refuses as a bare column name, which is what
// makes it a word this package quotes. MySQL and PostgreSQL refuse more of
// their own, and quoting is harmless where a word was not reserved, so the
// table is applied to all three dialects.

///|
let reserved : Array[String] = [
{body},
]
'''


def committed() -> list[str]:
    """The words in the file as it stands. `moon fmt` owns the layout, so the
    check reads the list rather than the bytes."""
    if not OUT.exists():
        return []
    text = OUT.read_text(encoding="utf-8").split("let reserved", 1)[-1]
    return re.findall(r'"([^"]+)"', text)


def main() -> None:
    words = keywords()
    text = render(words)
    check = "--check" in sys.argv
    if check:
        if committed() != words:
            sys.exit(f"{OUT.relative_to(ROOT)} is not what the engine refuses")
        print(f"{len(words)} reserved words, as committed")
        return
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"{len(words)} reserved words -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
