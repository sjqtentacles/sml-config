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
  val stringOr : string -> string -> string reader
  val intOr    : string -> int -> int reader
  val boolOr   : string -> bool -> bool reader
  val optional : 'a reader -> 'a option reader
  val pure : 'a -> 'a reader
  val map  : ('a -> 'b) -> 'a reader -> 'b reader
  val ap   : ('a -> 'b) reader -> 'a reader -> 'b reader
  val both : 'a reader -> 'b reader -> ('a * 'b) reader
  val run  : 'a reader -> source -> 'a outcome
end
```

`bool` accepts `true/false`, `1/0`, `yes/no`, `on/off` (case-insensitive).
`int` is strict: an optional sign followed by digits only.

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

26 deterministic checks: dotenv parsing (comments, blanks, trimming,
quoting, last-duplicate-wins), strict typed readers, signed/negative ints,
defaults and `optional`, and applicative error accumulation building a
record. Run `make all-tests`.

## License

MIT. See [LICENSE](LICENSE).
