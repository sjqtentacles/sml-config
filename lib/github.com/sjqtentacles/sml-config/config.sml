(* config.sml *)

structure Config :> CONFIG =
struct
  datatype 'a outcome = Ok of 'a | Err of string list

  type source = (string * string) list

  (* ---- dotenv parsing ---- *)

  fun trim s =
    let
      val cs = Substring.full s
      val cs = Substring.dropl Char.isSpace cs
      val cs = Substring.dropr Char.isSpace cs
    in
      Substring.string cs
    end

  fun unquote s =
    let val n = String.size s in
      if n >= 2
         andalso ((String.sub (s, 0) = #"\"" andalso String.sub (s, n-1) = #"\"")
                  orelse (String.sub (s, 0) = #"'" andalso String.sub (s, n-1) = #"'"))
      then String.substring (s, 1, n - 2)
      else s
    end

  fun parseLine line =
    let
      val t = trim line
    in
      if t = "" orelse String.isPrefix "#" t then NONE
      else
        case Substring.position "=" (Substring.full t) of
            (key, rest) =>
              if Substring.isEmpty rest then NONE  (* no '=' present *)
              else
                let
                  val k = trim (Substring.string key)
                  val v = unquote (trim (Substring.string (Substring.triml 1 rest)))
                in
                  if k = "" then NONE else SOME (k, v)
                end
    end

  fun parseDotenv text =
    let
      val lines = String.fields (fn c => c = #"\n") text
    in
      List.mapPartial parseLine lines
    end

  (* Later duplicates win: fold so last assignment is returned first on lookup. *)
  fun getStringOpt (src : source) key =
    let
      fun loop [] acc = acc
        | loop ((k, v) :: rest) acc =
            loop rest (if k = key then SOME v else acc)
    in
      loop src NONE
    end

  (* ---- typed readers (applicative, error-accumulating) ---- *)

  type 'a reader = source -> 'a outcome

  fun pure x = fn _ => Ok x

  fun map f r =
    fn src => (case r src of Ok x => Ok (f x) | Err e => Err e)

  fun ap rf rx =
    fn src =>
      (case (rf src, rx src) of
           (Ok f, Ok x) => Ok (f x)
         | (Err e1, Err e2) => Err (e1 @ e2)
         | (Err e1, Ok _) => Err e1
         | (Ok _, Err e2) => Err e2)

  fun both ra rb = ap (map (fn a => fn b => (a, b)) ra) rb

  fun missing key = Err ["missing required key: " ^ key]
  fun malformed key ty raw =
    Err ["key " ^ key ^ " is not a valid " ^ ty ^ ": \"" ^ raw ^ "\""]

  fun string key =
    fn src => (case getStringOpt src key of SOME v => Ok v | NONE => missing key)

  fun parseBool raw =
    case String.map Char.toLower raw of
        "true" => SOME true | "1" => SOME true | "yes" => SOME true | "on" => SOME true
      | "false" => SOME false | "0" => SOME false | "no" => SOME false | "off" => SOME false
      | _ => NONE

  (* Strict integer: optional leading sign then all digits, non-empty. *)
  fun parseIntStrict raw =
    let
      val s = trim raw
      val (sign, digits) =
        if String.isPrefix "-" s then (~1, String.extract (s, 1, NONE))
        else if String.isPrefix "+" s then (1, String.extract (s, 1, NONE))
        else (1, s)
    in
      if digits <> "" andalso CharVector.all Char.isDigit digits
      then (case Int.fromString digits of SOME n => SOME (sign * n) | NONE => NONE)
      else NONE
    end

  fun int key =
    fn src =>
      (case getStringOpt src key of
           NONE => missing key
         | SOME v => (case parseIntStrict v of SOME n => Ok n | NONE => malformed key "int" v))

  fun bool key =
    fn src =>
      (case getStringOpt src key of
           NONE => missing key
         | SOME v => (case parseBool (trim v) of SOME b => Ok b | NONE => malformed key "bool" v))

  fun stringOr key default =
    fn src => (case getStringOpt src key of SOME v => Ok v | NONE => Ok default)

  fun intOr key default =
    fn src =>
      (case getStringOpt src key of
           NONE => Ok default
         | SOME _ => int key src)

  fun boolOr key default =
    fn src =>
      (case getStringOpt src key of
           NONE => Ok default
         | SOME _ => bool key src)

  fun optional r =
    fn src => (case r src of Ok x => Ok (SOME x) | Err _ => Ok NONE)

  fun run r src = r src
end
