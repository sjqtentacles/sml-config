# sml-config

[![CI](https://github.com/sjqtentacles/sml-config/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-config/actions/workflows/ci.yml)

Typed, error-accumulating configuration for Standard ML from a pure
key/value source.

The source is just an association list -- parsed from a dotenv string, or
built from an environment map at the impure edge -- so the whole module is
deterministic and testable without touching the OS. Readers are typed and
compose applicatively, so a single run reports **every** missing or
malformed key at once instead of failing on the first.

Pure Standard ML over the Basis library -- no dependencies. Verified on
**MLton** and **Poly/ML**.

## API

```sml
structure Config : sig
  datatype 'a outcome = Ok of 'a | Err of string list
  type source = (string * string) list
  val parseDotenv  : string -> source
  val getStringOpt : source -> string -> string option
  type 'a reader
  val string : string -> string reader
  val int    : string -> int reader
  val bool   : string -> bool reader
  val real   : string -> real reader
  val char   : string -> char reader
  val oneOf  : string -> string list -> string reader
  val listOf : char -> string -> string list reader
  val csv    : string -> string list reader
  val stringOr : string -> string -> string reader
  val intOr    : string -> int -> int reader
  val boolOr   : string -> bool -> bool reader
  val realOr   : string -> real -> real reader
  val charOr   : string -> char -> char reader
  val optional : 'a reader -> 'a option reader
  val withDefault : 'a -> 'a reader -> 'a reader
  val pure : 'a -> 'a reader
  val map  : ('a -> 'b) -> 'a reader -> 'b reader
  val ap   : ('a -> 'b) reader -> 'a reader -> 'b reader
  val both : 'a reader -> 'b reader -> ('a * 'b) reader
  val andThen : 'a reader -> ('a -> 'b reader) -> 'b reader
  val bind    : 'a reader -> ('a -> 'b reader) -> 'b reader
  val satisfy : ('a -> bool) -> string -> 'a reader -> 'a reader
  val ensure  : ('a -> bool) -> string -> 'a reader -> 'a reader
  val prefixed : string -> 'a reader -> 'a reader
  val section  : string -> 'a reader -> 'a reader
  val unusedKeys : string list -> source -> string list
  val run  : 'a reader -> source -> 'a outcome
end
```

`bool` accepts `true/false`, `1/0`, `yes/no`, `on/off` (case-insensitive).
`int`/`real` are strict: an optional sign followed by a valid number with no
trailing junk (`"12ab"` and `"1.2x"` are rejected). `char` requires exactly one
character. `oneOf key allowed` is an enum reader. `listOf sep`/`csv` split a
value and trim each element (an empty value yields `[]`).

`int` produces a machine `int`, whose width is fixed but compiler-dependent
(32-bit under MLton's default, 63-bit under Poly/ML). To keep behaviour
identical on both compilers, `int` parses through arbitrary-precision `IntInf`
and bounds-checks against the fixed 32-bit signed range `[-2147483648,
2147483647]`: a numeral outside that range is reported as a malformed `int`
(never crashing), so a value like `"9999999999"` fails gracefully everywhere
rather than raising `Overflow` on MLton.

### Combinators

- **Applicative** (`pure`/`map`/`ap`/`both`): error-**accumulating** -- a single
  `run` reports *every* missing or malformed key at once.
- **Monadic** (`andThen`/`bind`): short-circuits on the first error, so it does
  **not** accumulate. Use it when a later reader depends on an earlier value.
- **Validation** (`ensure pred msg r` / `satisfy`): turns a successful value into
  `Err [msg]` unless it satisfies `pred`.
- **Defaults** (`withDefault d r`): recovers from *any* error with `d`;
  `stringOr`/`intOr`/`boolOr`/`realOr`/`charOr` default only on a *missing* key.
- **Scoping** (`prefixed pfx r` / `section name r`): runs `r` against a sub-source
  containing only keys under the prefix, with the prefix stripped. `section "db"`
  is `prefixed "db."`.
- **Schema check** (`unusedKeys expected src`): lists distinct source keys not in
  `expected` (handy for catching typos), since readers do not track consumed keys.

### Example

```sml
val env = Config.parseDotenv "PORT=8080\nHOST=localhost\nDEBUG=yes\n"

(* Build a record; all field errors accumulate. *)
val mk = fn h => fn p => fn d => { host = h, port = p, debug = d }
val reader =
  Config.ap (Config.ap (Config.ap (Config.pure mk)
    (Config.string "HOST")) (Config.int "PORT")) (Config.boolOr "DEBUG" false)

val cfg =
  case Config.run reader env of
      Config.Ok c => c
    | Config.Err errs => raise Fail (String.concatWith "; " errs)
```

### Validation, scoping, and enums

```sml
(* Port must be in range; oneOf restricts to an enum. *)
val portR = Config.ensure (fn p => p > 0 andalso p < 65536) "port out of range"
              (Config.int "PORT")
val modeR = Config.oneOf "MODE" ["debug", "release"]

(* Scope a reader to a "db." section of the source. *)
val dbHost = Config.section "db" (Config.string "host")
val src = [("db.host", "localhost"), ("db.port", "5432")]
val Config.Ok host = Config.run dbHost src    (* "localhost" *)

(* Catch typos: keys present but not expected. *)
val typos = Config.unusedKeys ["PORT", "HOST"] env
```

## Example

`make example` builds and runs [`examples/demo.sml`](examples/demo.sml), which
parses a dotenv-style source and exercises the typed readers, the applicative
combinators (`both`/`map`/`ap`), and error accumulation over a missing and a
malformed key (output is byte-identical under MLton and Poly/ML):

```
sml-config demo

Basic typed readers:
  HOST  (string) = localhost
  PORT  (int)    = 8080
  DEBUG (bool)   = true
  RATIO (real)   = 0.50
  MODE  (oneOf)  = release
  TAGS  (csv)    = [a,b,c]

Applicative composition (both/ap/map):
  both HOST PORT = (localhost, 8080)
  map (address)  = localhost:8080
  ap (record)    = localhost:8080 debug=true

Error accumulation (missing key + malformed key together):
  - missing required key: MISSING
  - key HOST is not a valid int: "localhost"
```

## Build & test

```sh
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make clean
```

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-config
smlpkg sync
```

Reference `lib/github.com/sjqtentacles/sml-config/sml-config.mlb` from your
own `.mlb`, or feed `sources.mlb` to `tools/polybuild` (Poly/ML).

## Tests

60 deterministic checks: dotenv parsing (comments, blanks, trimming,
quoting, last-duplicate-wins), strict typed readers (`int`/`real`/`char`),
signed/negative ints, integer bounds (oversized numerals rejected without
raising, identically on both compilers), defaults/`optional`/`withDefault`,
applicative error accumulation building a record, `oneOf` enums,
`listOf`/`csv` splitting, `ensure`/`satisfy` validation, `andThen`
short-circuiting, `prefixed`/`section` scoping, and `unusedKeys` schema
checks. Run `make all-tests`.

## License

MIT. See [LICENSE](LICENSE).
