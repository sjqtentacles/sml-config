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
  val real   : string -> real reader
  val char   : string -> char reader      (* exactly one character *)

  (* Enum reader: value must be one of the given allowed strings. *)
  val oneOf  : string -> string list -> string reader

  (* List readers: split a value on a separator (listOf) or on commas (csv);
     surrounding whitespace on each element is trimmed. *)
  val listOf : char -> string -> string list reader
  val csv    : string -> string list reader

  (* Optional / defaulted variants. *)
  val stringOr : string -> string -> string reader
  val intOr    : string -> int -> int reader
  val boolOr   : string -> bool -> bool reader
  val realOr   : string -> real -> real reader
  val charOr   : string -> char -> char reader
  val optional : 'a reader -> 'a option reader
  (* Recover from any error with a fixed default. *)
  val withDefault : 'a -> 'a reader -> 'a reader

  (* Applicative combinators. *)
  val pure : 'a -> 'a reader
  val map  : ('a -> 'b) -> 'a reader -> 'b reader
  val ap   : ('a -> 'b) reader -> 'a reader -> 'b reader
  (* Pairing helper for building records. *)
  val both : 'a reader -> 'b reader -> ('a * 'b) reader

  (* Monadic sequencing. NOTE: andThen/bind short-circuit on the first error,
     so they do NOT accumulate errors the way ap/both do. *)
  val andThen : 'a reader -> ('a -> 'b reader) -> 'b reader
  val bind    : 'a reader -> ('a -> 'b reader) -> 'b reader

  (* Validation: fail with a message unless the produced value satisfies a
     predicate. (satisfy is an alias for ensure.) *)
  val satisfy : ('a -> bool) -> string -> 'a reader -> 'a reader
  val ensure  : ('a -> bool) -> string -> 'a reader -> 'a reader

  (* Scope a reader to a key prefix: prefixed "db." r runs r against a source in
     which only keys starting with "db." appear, with that prefix stripped.
     section is an alias reading "name." (a trailing dot is added if absent). *)
  val prefixed : string -> 'a reader -> 'a reader
  val section  : string -> 'a reader -> 'a reader

  (* Schema-based: given the list of keys you expect to consume, report any keys
     in the source that are not in that list (useful to catch typos). *)
  val unusedKeys : string list -> source -> string list

  (* Run a reader against a source: Ok value or Err (all messages). *)
  val run : 'a reader -> source -> 'a outcome
end
