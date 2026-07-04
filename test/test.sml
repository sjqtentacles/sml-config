(* Tests for sml-config. *)

structure ConfigTests =
struct
  open Config  (* brings Ok / Err and the readers into scope *)
  open Harness

  fun checkResultInt name (expected, actual) =
    case (expected, actual) of
        (Ok a, Ok b) => checkInt name (a, b)
      | (Err _, Err _) => check name true
      | _ => check name false

  fun run () =
    let
      val () = section "dotenv parsing"
      val env = Config.parseDotenv
        ("# a comment\n" ^
         "PORT=8080\n" ^
         "\n" ^
         "  HOST = localhost  \n" ^
         "NAME=\"My App\"\n" ^
         "SQUOTE='single'\n" ^
         "DEBUG=true\n" ^
         "PORT=9090\n")   (* duplicate: later wins *)
      val () = checkBool "PORT (last wins)" (true, Config.getStringOpt env "PORT" = SOME "9090")
      val () = checkBool "HOST trimmed" (true, Config.getStringOpt env "HOST" = SOME "localhost")
      val () = checkBool "double-quoted value" (true, Config.getStringOpt env "NAME" = SOME "My App")
      val () = checkBool "single-quoted value" (true, Config.getStringOpt env "SQUOTE" = SOME "single")
      val () = checkBool "comment ignored" (true, Config.getStringOpt env "a comment" = NONE)
      val () = checkBool "missing key NONE" (true, Config.getStringOpt env "NOPE" = NONE)

      val () = section "typed required readers"
      val src = [("PORT", "8080"), ("HOST", "localhost"), ("DEBUG", "yes"), ("BAD", "x")]
      val () = checkResultInt "int ok" (Ok 8080, Config.run (Config.int "PORT") src)
      val () = checkResultInt "int missing -> error" (Err [], Config.run (Config.int "MISSING") src)
      val () = checkResultInt "int malformed -> error" (Err [], Config.run (Config.int "HOST") src)
      val () = checkBool "string ok"
                 (true, (case Config.run (Config.string "HOST") src of Ok "localhost" => true | _ => false))
      val () = checkBool "bool yes -> true"
                 (true, (case Config.run (Config.bool "DEBUG") src of Ok true => true | _ => false))
      val () = checkBool "bool malformed -> error"
                 (true, (case Config.run (Config.bool "BAD") src of Err _ => true | _ => false))

      val () = section "negative + signed ints"
      val () = checkResultInt "negative" (Ok (~5), Config.run (Config.int "X") [("X", "-5")])
      val () = checkResultInt "plus sign" (Ok 42, Config.run (Config.int "X") [("X", "+42")])
      val () = checkResultInt "trailing garbage rejected" (Err [], Config.run (Config.int "X") [("X", "12ab")])

      val () = section "integer bounds (cross-compiler overflow safety)"
      (* A machine `int` is 32-bit under MLton's default and 63-bit under
         Poly/ML. `Int.fromString` on an oversized numeral raises Overflow on
         MLton (a crash, not NONE) and would diverge between compilers. The
         bounded reader must instead reject out-of-range values gracefully as a
         malformed `int` -- and NEVER raise -- identically on both compilers. *)
      val () = check "oversized int never raises"
                 (let val _ = Config.run (Config.int "X") [("X", "9999999999")] in true end
                  handle _ => false)
      val () = checkResultInt "oversized int -> error"
                 (Err [], Config.run (Config.int "X") [("X", "9999999999")])
      val () = checkResultInt "20-digit int -> error"
                 (Err [], Config.run (Config.int "X") [("X", "99999999999999999999")])
      val () = checkResultInt "Int32 max boundary parses"
                 (Ok 2147483647, Config.run (Config.int "X") [("X", "2147483647")])
      val () = checkResultInt "just past Int32 max -> error"
                 (Err [], Config.run (Config.int "X") [("X", "2147483648")])
      val () = checkResultInt "Int32 min boundary parses"
                 (Ok (~2147483648), Config.run (Config.int "X") [("X", "-2147483648")])
      val () = checkResultInt "just past Int32 min -> error"
                 (Err [], Config.run (Config.int "X") [("X", "-2147483649")])

      val () = section "defaults / optional"
      val () = checkBool "stringOr uses default"
                 (true, (case Config.run (Config.stringOr "MISSING" "fallback") src of Ok "fallback" => true | _ => false))
      val () = checkResultInt "intOr uses default" (Ok 3000, Config.run (Config.intOr "MISSING" 3000) src)
      val () = checkResultInt "intOr uses present value" (Ok 8080, Config.run (Config.intOr "PORT" 3000) src)
      val () = checkBool "boolOr default"
                 (true, (case Config.run (Config.boolOr "MISSING" false) src of Ok false => true | _ => false))
      val () = checkBool "optional present"
                 (true, (case Config.run (Config.optional (Config.int "PORT")) src of Ok (SOME 8080) => true | _ => false))
      val () = checkBool "optional missing -> NONE"
                 (true, (case Config.run (Config.optional (Config.int "MISSING")) src of Ok NONE => true | _ => false))

      val () = section "applicative error accumulation"
      val reader = Config.both (Config.int "A") (Config.int "B")
      val () = (case Config.run reader [] of
                    Err errs => checkInt "two errors accumulated" (2, List.length errs)
                  | Ok _ => check "two errors accumulated" false)
      val () = (case Config.run (Config.both (Config.int "PORT") (Config.int "B")) src of
                    Err errs => checkInt "one error when one ok" (1, List.length errs)
                  | Ok _ => check "one error when one ok" false)

      val () = section "map / pure / ap build a record"
      val mk = fn h => fn p => fn d => { host = h, port = p, debug = d }
      val cfgReader =
        Config.ap (Config.ap (Config.ap (Config.pure mk)
                     (Config.string "HOST")) (Config.int "PORT")) (Config.bool "DEBUG")
      val () = (case Config.run cfgReader src of
                    Ok { host, port, debug } =>
                      (checkString "record host" ("localhost", host);
                       checkInt "record port" (8080, port);
                       checkBool "record debug" (true, debug))
                  | Err _ => check "record built" false)

      val () = section "real / char readers"
      val rsrc = [("RATE", "0.25"), ("PI", "3.14159"), ("NEG", "-2.5"),
                  ("BADR", "1.2x"), ("FLAG", "Y"), ("MULTI", "ab")]
      val () = checkBool "real ok"
                 (true, (case Config.run (Config.real "RATE") rsrc of
                             Ok r => Real.abs (r - 0.25) < 1E~9 | _ => false))
      val () = checkBool "real negative"
                 (true, (case Config.run (Config.real "NEG") rsrc of
                             Ok r => Real.abs (r - ~2.5) < 1E~9 | _ => false))
      val () = checkBool "real trailing junk rejected"
                 (true, (case Config.run (Config.real "BADR") rsrc of Err _ => true | _ => false))
      val () = checkBool "real missing -> error"
                 (true, (case Config.run (Config.real "MISSING") rsrc of Err _ => true | _ => false))
      val () = checkBool "realOr default"
                 (true, (case Config.run (Config.realOr "MISSING" 1.5) rsrc of
                             Ok r => Real.abs (r - 1.5) < 1E~9 | _ => false))
      val () = checkBool "char ok"
                 (true, (case Config.run (Config.char "FLAG") rsrc of Ok #"Y" => true | _ => false))
      val () = checkBool "char multi -> error"
                 (true, (case Config.run (Config.char "MULTI") rsrc of Err _ => true | _ => false))
      val () = checkBool "charOr default"
                 (true, (case Config.run (Config.charOr "MISSING" #"?") rsrc of Ok #"?" => true | _ => false))

      val () = section "oneOf enum reader"
      val esrc = [("MODE", "fast"), ("LVL", "warn")]
      val () = checkBool "oneOf accepts allowed"
                 (true, (case Config.run (Config.oneOf "MODE" ["slow","fast"]) esrc of
                             Ok "fast" => true | _ => false))
      val () = checkBool "oneOf rejects disallowed"
                 (true, (case Config.run (Config.oneOf "LVL" ["debug","info"]) esrc of Err _ => true | _ => false))
      val () = checkBool "oneOf missing -> error"
                 (true, (case Config.run (Config.oneOf "X" ["a"]) esrc of Err _ => true | _ => false))

      val () = section "listOf / csv readers"
      val lsrc = [("TAGS", "a, b ,c"), ("PIPES", "x|y|z"), ("EMPTY", "")]
      val () = checkStringList "csv trims elements"
                 (["a","b","c"], (case Config.run (Config.csv "TAGS") lsrc of Ok xs => xs | _ => ["FAIL"]))
      val () = checkStringList "listOf custom separator"
                 (["x","y","z"], (case Config.run (Config.listOf #"|" "PIPES") lsrc of Ok xs => xs | _ => ["FAIL"]))
      val () = checkBool "listOf empty -> []"
                 (true, (case Config.run (Config.csv "EMPTY") lsrc of Ok [] => true | _ => false))

      val () = section "ensure / satisfy validation"
      val vsrc = [("PORT", "8080"), ("LOW", "10"), ("NAME", "ok")]
      val () = checkResultInt "ensure passes"
                 (Ok 8080, Config.run (Config.ensure (fn p => p > 0) "port>0" (Config.int "PORT")) vsrc)
      val () = checkBool "ensure fails"
                 (true, (case Config.run (Config.ensure (fn p => p > 1000) "port>1000" (Config.int "LOW")) vsrc of
                             Err ["port>1000"] => true | _ => false))
      val () = checkBool "satisfy passes"
                 (true, (case Config.run (Config.satisfy (fn s => s <> "") "nonempty" (Config.string "NAME")) vsrc of
                             Ok "ok" => true | _ => false))

      val () = section "andThen / withDefault"
      val () = checkResultInt "andThen chains"
                 (Ok 8081,
                  Config.run (Config.andThen (Config.int "PORT") (fn p => Config.pure (p + 1))) vsrc)
      val () = checkBool "andThen short-circuits on error"
                 (true, (case Config.run (Config.andThen (Config.int "MISSING") (fn p => Config.pure p)) vsrc of
                             Err _ => true | _ => false))
      val () = checkResultInt "withDefault recovers"
                 (Ok 99, Config.run (Config.withDefault 99 (Config.int "MISSING")) vsrc)
      val () = checkResultInt "withDefault keeps value"
                 (Ok 8080, Config.run (Config.withDefault 99 (Config.int "PORT")) vsrc)

      val () = section "prefixed / section scoping"
      val psrc = [("db.host", "localhost"), ("db.port", "5432"), ("web.port", "80")]
      val () = checkResultInt "prefixed strips prefix"
                 (Ok 5432, Config.run (Config.prefixed "db." (Config.int "port")) psrc)
      val () = checkBool "prefixed string"
                 (true, (case Config.run (Config.prefixed "db." (Config.string "host")) psrc of
                             Ok "localhost" => true | _ => false))
      val () = checkResultInt "section adds trailing dot"
                 (Ok 80, Config.run (Config.section "web" (Config.int "port")) psrc)
      val () = checkBool "section isolates scope (db.host not visible in web)"
                 (true, (case Config.run (Config.section "web" (Config.string "host")) psrc of
                             Err _ => true | _ => false))

      val () = section "unusedKeys schema check"
      val usrc = [("PORT", "8080"), ("HOST", "x"), ("TYPO", "?"), ("EXTRA", "!")]
      val () = checkStringList "reports unused keys in order"
                 (["TYPO","EXTRA"], Config.unusedKeys ["PORT","HOST"] usrc)
      val () = checkBool "no unused when all expected"
                 (true, Config.unusedKeys ["PORT","HOST","TYPO","EXTRA"] usrc = [])
    in
      ()
    end
end
