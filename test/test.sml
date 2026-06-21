(* Tests for sml-config. *)

structure ConfigTests =
struct
  open Harness
  open Config  (* brings Ok / Err and the readers into scope *)

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
    in
      ()
    end
end
