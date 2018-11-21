open Bechamel
open Toolkit

let () = Printexc.record_backtrace true

let block = 50

module Monotonic_clock = struct
  type witness = int
  type value = int64 ref
  type label = string

  let make () = Oclock.monotonic
  let load _witness = ()
  let unload _witness = ()
  let float v = Int64.to_float !v
  let label _witness = "monotonic-clock"
  let diff a b = {contents= Int64.sub !b !a}
  let epsilon () = {contents= 0L}
  let blit witness v = v := Oclock.gettime witness
end

module Realtime_clock = struct
  type witness = int
  type value = int64 ref
  type label = string

  let make () = Oclock.realtime
  let load _witness = ()
  let unload _witness = ()
  let float v = Int64.to_float !v
  let label _witness = "realtime-clock"
  let diff a b = {contents= Int64.sub !b !a}
  let epsilon () = {contents= 0L}
  let blit witness v = v := Oclock.gettime witness
end

module Blocks = struct
  type witness = unit
  type value = unit
  type label = string

  let make () = ()
  let load _witness = ()
  let unload _witness = ()
  let float _v = 0.
  let label _witness = "blocks"
  let diff a _b = a
  let epsilon () = ()
  let blit _witness _v = ()
end

module TimePerRun = struct
  type witness = unit
  type value = unit
  type label = string

  let make () = ()
  let load _witness = ()
  let unload _witness = ()
  let float _v = 0.
  let label _witness = "time-per-run"
  let diff a _b = a
  let epsilon () = ()
  let blit _witness _v = ()
end

module Extension = struct
  include Extension

  let monotonic_clock = Measure.make (module Monotonic_clock)
  let realtime_clock = Measure.make (module Realtime_clock)
  let blocks = Measure.make (module Blocks)
  let time_per_run = Measure.make (module TimePerRun)
end

module Instance = struct
  include Instance

  let monotonic_clock =
    Measure.instance (module Monotonic_clock) Extension.monotonic_clock

  let realtime_clock =
    Measure.instance (module Realtime_clock) Extension.realtime_clock

  let blocks =
    Measure.instance (module Blocks) Extension.blocks

  let time_per_run =
    Measure.instance (module TimePerRun) Extension.time_per_run
end

(** TESTS **)

let () = Random.self_init ()

let random_bytes len =
  let buf = Bytes.create len in
  let ic = open_in "/dev/urandom" in
  really_input ic buf 0 len; close_in ic; buf

let digest_bytes digest len =
  Staged.stage (fun () -> Digestif.digest_bytes digest (random_bytes len))

let len_list = (List.init block (fun i -> (i + 1) * 64 * 10))

let test_md5 =
  Test.make_indexed ~name:"Digestif.md5"
    ~args:len_list (digest_bytes Digestif.MD5)

let test_sha1 =
  Test.make_indexed ~name:"Digestif.sha1"
    ~args:len_list (digest_bytes Digestif.SHA1)

let test_rmd160 =
  Test.make_indexed ~name:"Digestif.rmd160"
    ~args:len_list (digest_bytes Digestif.RMD160)

let test_sha224 =
  Test.make_indexed ~name:"Digestif.sha224"
    ~args:len_list (digest_bytes Digestif.SHA224)

let test_sha256 =
  Test.make_indexed ~name:"Digestif.sha256"
    ~args:len_list (digest_bytes Digestif.SHA256)

let test_sha384 =
  Test.make_indexed ~name:"Digestif.sha384"
    ~args:len_list (digest_bytes Digestif.SHA384)

let test_sha512 =
  Test.make_indexed ~name:"Digestif.sha512"
    ~args:len_list (digest_bytes Digestif.SHA512)

let test_whirlpool =
  Test.make_indexed ~name:"Digestif.whirlpool"
    ~args:len_list (digest_bytes Digestif.WHIRLPOOL)

(* let test_blake2b =
  Test.make_indexed ~name:"Digestif.blake2b"
    ~args:len_list (digest_bytes Digestif.BLAKE2B)

let test_blake2s =
  Test.make_indexed ~name:"Digestif.bake2s"
    ~args:len_list (digest_bytes Digestif.BLAKE2S) *)

(** TESTS **)

let zip l1 l2 =
  let rec go acc = function
    | [], [] -> List.rev acc
    | x1 :: r1, x2 :: r2 -> go ((x1, x2) :: acc) (r1, r2)
    | _, _ -> assert false
  in
  go [] (l1, l2)

let pp_result ppf result =
  let style_by_r_square =
    match Analyze.OLS.r_square result with
    | Some r_square ->
        if r_square >= 0.95 then `Green
        else if r_square >= 0.90 then `Yellow
        else `Red
    | None -> `None
  in
  match Analyze.OLS.estimates result with
  | Some estimates ->
      Fmt.pf ppf "%a per %a = %a [%a%%]" Label.pp
        (Analyze.OLS.responder result)
        Fmt.(Dump.list Label.pp)
        (Analyze.OLS.predictors result)
        Fmt.(styled style_by_r_square (Dump.list float))
        estimates
        Fmt.(option float)
        (Analyze.OLS.r_square result)
  | None ->
      Fmt.pf ppf "%a per %a = #unable-to-compute" Label.pp
        (Analyze.OLS.responder result)
        Fmt.(Dump.list Label.pp)
        (Analyze.OLS.predictors result)

let pad n x =
  if String.length x > n then x else x ^ String.make (n - String.length x) ' '

let pp ppf (test, results) =
  let tests = Test.set test in
  List.iter
    (fun results ->
      List.iter
        (fun (test, result) ->
          Fmt.pf ppf "@[<hov>%s = %a@]@\n"
            (pad 30 @@ Test.Elt.name test)
            pp_result result )
        (zip tests results) )
    results

let reporter ppf =
  let report src level ~over k msgf =
    let k _ = over () ; k () in
    let with_src_and_stamp h _ k fmt =
      let dt = Mtime.Span.to_us (Mtime_clock.elapsed ()) in
      Fmt.kpf k ppf
        ("%s %a %a: @[" ^^ fmt ^^ "@]@.")
        (pad 20 (Fmt.strf "%+04.0fus" dt))
        Logs_fmt.pp_header (level, h)
        Fmt.(styled `Magenta string)
        (pad 20 @@ Logs.Src.name src)
    in
    msgf @@ fun ?header ?tags fmt -> with_src_and_stamp header tags k fmt
  in
  {Logs.report}

let setup_logs style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer () ;
  Logs.set_level level ;
  Logs.set_reporter (reporter Fmt.stdout) ;
  let quiet = match style_renderer with Some _ -> true | None -> false in
  (quiet, Fmt.stdout)

let _, _ = setup_logs (Some `Ansi_tty) (Some Logs.Debug)

let () =
  let ols =
    Analyze.ols ~r_square:true ~bootstrap:0 ~predictors:Measure.[|run|]
  in
  let instances =
    Instance.
      [minor_allocated; major_allocated; monotonic_clock; realtime_clock]
  in
  let tests =
    match Sys.argv with
    | [|_|] -> []
    | [|_; "md5"|] -> [test_md5]
    | [|_; "sha1"|] -> [test_sha1]
    | [|_; "rmd160"|] -> [test_rmd160]
    | [|_; "sha224"|] -> [test_sha224]
    | [|_; "sha256"|] -> [test_sha256]
    | [|_; "sha384"|] -> [test_sha384]
    | [|_; "sha512"|] -> [test_sha512]
    | [|_; "whirlpool"|] -> [test_whirlpool]
    (* | [|_; "blake2b"|] -> [test_blake2b]
    | [|_; "blake2s"|] -> [test_blake2s] *)
    | [|_; "all"|] -> [test_md5; test_sha1; test_rmd160; test_sha224; test_sha256; test_sha384; test_sha512; test_whirlpool; (*test_blake2b; test_blake2s*)]
    | _ -> Fmt.invalid_arg "%s {create|set|unsafe_set|all}" Sys.argv.(1)
  in
  let measure_and_analyze test =
    let results =
      Benchmark.all ~stabilize:true ~quota:(Benchmark.s 1.) ~run:3000 instances
        test
    in
    List.map
      (fun x -> List.map (fun result -> Analyze.analyze ols (Measure.label x) result) results)
      instances
  in
  let results = List.map measure_and_analyze tests in
  List.iter
    (fun (test, result) ->
      Fmt.pr "---------- %s ----------\n%!" (Test.name test) ;
      Fmt.pr "%a\n%!" pp (test, result) )
    (zip tests results);
  let reduced_results = List.nth results 0 in
  (* let ols =
    Analyze.ols ~r_square:true ~bootstrap:0 ~predictors:Measure.[|label Instance.blocks|]
  in *)
  let ransac = Analyze.ransac ~filter_outliers:true ~predictor:(Measure.label Instance.blocks)
  in
  let fct blocks =
    let raw =
      List.mapi
        (fun i data ->
          let est =
          match Analyze.OLS.estimates data with
            | Some estimates -> List.nth estimates 0
            | None -> 0.
          in
          Measurement_raw.make ~measures:[|float_of_int i; est|] ~labels:[|Measure.label Instance.blocks; Measure.label Instance.time_per_run|] 1.0
        ) blocks in
    Analyze.analyze ransac (Measure.label Instance.time_per_run) (Array.of_list raw)
  in
  (* Fmt.pr "%a\n%!"
    pp_result (fct reduced_results) *)
  List.iter (fun r ->
    Fmt.pr "%f %f\n%!" 
      (Analyze.RANSAC.mean r)
      (Analyze.RANSAC.error r)
  ) (List.map fct reduced_results)