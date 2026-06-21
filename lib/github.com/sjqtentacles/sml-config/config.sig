(* config.sig

   Typed configuration from a pure key/value source. The source is just an
   association list (e.g. parsed from a dotenv string or built from an env
   map at the impure edge), so the whole module is deterministic and
   testable without touching the OS.

   Lookups are typed and accumulate errors: build a `result` describing every
   missing/invalid key at once rather than failing on the first. *)

signature CONFIG =
sig
  (* Result of running a reader: a value, or the list of error messages. *)
  datatype 'a outcome = Ok of 'a | Err of string list

  type source = (string * string) list

  (* Parse a dotenv-style string into a source. Supports `KEY=value` lines,
     `#` comments, blank lines, surrounding whitespace, and single/double
     quoted values. Later duplicate keys win. *)
  val parseDotenv : string -> source

  (* Look up a raw string. *)
  val getStringOpt : source -> string -> string option

  (* A reader produces either a value or a list of error messages. Readers
     compose applicatively so errors accumulate. *)
  type 'a reader

  (* Required typed readers (error if missing or malformed). *)
  val string : string -> string reader
  val int    : string -> int reader
  val bool   : string -> bool reader      (* true/false/1/0/yes/no/on/off *)

  (* Optional / defaulted variants. *)
  val stringOr : string -> string -> string reader
  val intOr    : string -> int -> int reader
  val boolOr   : string -> bool -> bool reader
  val optional : 'a reader -> 'a option reader

  (* Applicative combinators. *)
  val pure : 'a -> 'a reader
  val map  : ('a -> 'b) -> 'a reader -> 'b reader
  val ap   : ('a -> 'b) reader -> 'a reader -> 'b reader
  (* Pairing helper for building records. *)
  val both : 'a reader -> 'b reader -> ('a * 'b) reader

  (* Run a reader against a source: Ok value or Err (all messages). *)
  val run : 'a reader -> source -> 'a outcome
end
