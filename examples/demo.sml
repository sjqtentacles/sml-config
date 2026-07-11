(* demo.sml - typed, error-accumulating config reads from a dotenv-style
   source. Deterministic: identical output on every run and both compilers. *)

structure C = Config

val () = print "sml-config demo\n"

val src =
  C.parseDotenv
    ("HOST=localhost\n" ^
     "PORT=8080\n" ^
     "DEBUG=yes\n" ^
     "RATIO=0.5\n" ^
     "MODE=release\n" ^
     "TAGS=a, b, c\n")

fun fmtReal r =
  let val r = if Real.== (r, 0.0) then 0.0 else r
  in Real.fmt (StringCvt.FIX (SOME 2)) r end

fun report label outcome tos =
  case outcome of
      C.Ok v => print ("  " ^ label ^ " = " ^ tos v ^ "\n")
    | C.Err es => print ("  " ^ label ^ " error: " ^ String.concatWith "; " es ^ "\n")

val () = print "\nBasic typed readers:\n"
val () = report "HOST  (string)" (C.run (C.string "HOST") src) (fn s => s)
val () = report "PORT  (int)   " (C.run (C.int "PORT") src) Int.toString
val () = report "DEBUG (bool)  " (C.run (C.bool "DEBUG") src) Bool.toString
val () = report "RATIO (real)  " (C.run (C.real "RATIO") src) fmtReal
val () = report "MODE  (oneOf) " (C.run (C.oneOf "MODE" ["debug", "release"]) src) (fn s => s)
val () = report "TAGS  (csv)   " (C.run (C.csv "TAGS") src)
           (fn ts => "[" ^ String.concatWith "," ts ^ "]")

val () = print "\nApplicative composition (both/ap/map):\n"
val pairR = C.both (C.string "HOST") (C.int "PORT")
val () = report "both HOST PORT" (C.run pairR src)
           (fn (h, p) => "(" ^ h ^ ", " ^ Int.toString p ^ ")")

val addrR = C.map (fn (h, p) => h ^ ":" ^ Int.toString p) pairR
val () = report "map (address) " (C.run addrR src) (fn s => s)

val mk = fn h => fn p => fn d => h ^ ":" ^ Int.toString p ^ " debug=" ^ Bool.toString d
val apR = C.ap (C.ap (C.map mk (C.string "HOST")) (C.int "PORT")) (C.bool "DEBUG")
val () = report "ap (record)   " (C.run apR src) (fn s => s)

val () = print "\nError accumulation (missing key + malformed key together):\n"
val badR = C.both (C.int "MISSING") (C.int "HOST")
val () =
  case C.run badR src of
      C.Ok _ => print "  unexpected success\n"
    | C.Err es => List.app (fn e => print ("  - " ^ e ^ "\n")) es
