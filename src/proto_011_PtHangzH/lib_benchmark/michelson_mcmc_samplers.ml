(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** MCMC-based Michelson data and code samplers. *)

open Protocol
open StaTz

type michelson_code = {
  term : Script_repr.expr;
  bef : Script_repr.expr list;
  aft : Script_repr.expr list;
}

type michelson_data = {term : Script_repr.expr; typ : Script_repr.expr}

type michelson_sample = Code of michelson_code | Data of michelson_data

let michelson_sample_list_encoding =
  let open Data_encoding in
  let e = Script_repr.expr_encoding in
  list
  @@ union
       [
         case
           ~title:"Code"
           (Tag 0)
           (tup3 e (list e) (list e))
           (function
             | Code {term; bef; aft} -> Some (term, bef, aft) | _ -> None)
           (fun (term, bef, aft) -> Code {term; bef; aft});
         case
           ~title:"Data"
           (Tag 1)
           (tup2 e e)
           (function Data {term; typ} -> Some (term, typ) | _ -> None)
           (fun (term, typ) -> Data {term; typ});
       ]

let save ~filename ~terms =
  let bytes =
    match
      Data_encoding.Binary.to_bytes michelson_sample_list_encoding terms
    with
    | Error err ->
        Format.eprintf
          "Michelson_mcmc_samplers.save: encoding failed (%a); exiting"
          Data_encoding.Binary.pp_write_error
          err ;
        exit 1
    | Ok res -> res
  in
  try
    Lwt_main.run
    @@ Tezos_stdlib_unix.Lwt_utils_unix.create_file
         filename
         (Bytes.unsafe_to_string bytes)
  with exn ->
    Format.eprintf
      "Michelson_mcmc_samplers.save: create_file failed (%s); exiting"
      (Printexc.to_string exn) ;
    exit 1

let load ~filename =
  let open TzPervasives in
  let string =
    try Lwt_main.run @@ Tezos_stdlib_unix.Lwt_utils_unix.read_file filename
    with exn ->
      Format.eprintf
        "Michelson_mcmc_samplers.load: read_file failed (%s); exiting"
        (Printexc.to_string exn) ;
      exit 1
  in
  let bytes = Bytes.of_string string in
  match Data_encoding.Binary.of_bytes michelson_sample_list_encoding bytes with
  | Ok result -> result
  | Error err ->
      Format.eprintf
        "Michelson_mcmc_samplers.load: decoding failed (%a); exiting"
        Data_encoding.Binary.pp_read_error
        err ;
      exit 1

(* Helpers *)

let base_type_to_michelson_type (typ : Type.Base.t) =
  let typ = Mikhailsky.map_var (fun _ -> Mikhailsky.unit_ty) typ in
  Mikhailsky.to_michelson typ

module type Sampler_parameters_sig = sig
  val initial : State_space.t

  val energy : State_space.t -> float

  val rules : Rules.rule_set list

  val infer : Mikhailsky.node -> Inference.state

  val verbosity : [`Silent | `Progress | `Trace]
end

(** Generic MCMC michelson sampler (can be used for code and data) *)
module Make_generic (P : Sampler_parameters_sig) = struct
  module MH_params : MH.MH_parameters with type t = State_space.t = struct
    let uniform (l : State_space.t list) : State_space.t Stats.fin_prb =
      match l with
      | [] -> assert false
      | _ ->
          let arr = Array.of_list l in
          let emp = Stats.empirical_of_raw_data arr in
          Stats.fin_prb_of_empirical (module State_space) emp

    let trace state =
      match P.verbosity with
      | `Silent | `Progress -> ()
      | `Trace ->
          Format.eprintf "@." ;
          Format.eprintf "%a" State_space.pp state ;
          Format.eprintf "energy:@." ;
          Format.eprintf "%f:@." (P.energy state)

    let unrecoverable_failure err current result =
      Format.eprintf "Error when typechecking term:@." ;
      Format.eprintf "%a@." Inference.pp_inference_error err ;
      Format.eprintf "Original state: @[%a@]@." State_space.pp current ;
      Format.eprintf "Erroneous term: %a@." Mikhailsky.pp result ;
      Stdlib.failwith "in sampler.ml: unrecoverable failure."

    let rec proposal ({State_space.term; _} as current) =
      trace current ;
      let rewriting_options = Rules.rewriting current P.rules in
      let rewritings =
        List.fold_left
          (fun rewritings (path, replacement) ->
            let result = Kernel.Rewriter.subst ~term ~path ~replacement in
            let typing =
              Lazy.from_fun (fun () ->
                  try P.infer result
                  with Inference.Ill_typed_script err ->
                    unrecoverable_failure err current result)
            in
            {State_space.typing; term = result} :: rewritings)
          []
          rewriting_options
      in
      match rewritings with [] -> proposal current | _ -> uniform rewritings

    let log_weight state = -.P.energy state

    include State_space
  end

  module Sampler = MH.Make (MH_params)

  let generator ~burn_in = P.(Sampler.mcmc ~verbosity ~initial ~burn_in)
end

module Make_code_sampler
    (Michelson_base : Michelson_samplers_base.S)
    (Crypto_samplers : Crypto_samplers.Finite_key_pool_S) (X : sig
      val rng_state : Random.State.t

      val target_size : int

      val verbosity : [`Silent | `Progress | `Trace]
    end) =
struct
  module Autocomp = Autocomp.Make (Michelson_base) (Crypto_samplers)

  module MCMC = Make_generic (struct
    let initial =
      let term = Mikhailsky.Instructions.hole in
      let typing = Lazy.from_val @@ snd (Inference.infer_with_state term) in
      {State_space.term; typing}

    let energy state =
      let stats = State_space.statistics state in
      let size_deficit =
        abs_float
          (float_of_int X.target_size -. float_of_int stats.State_space.size)
      in
      let holes_proportion = float stats.holes /. float stats.size in
      let holes_deficit =
        (* we want at least 1% of holes, above is ok *)
        if holes_proportion < 0.01 then
          (0.01 -. holes_proportion) *. size_deficit
        else 0.0
      in
      size_deficit +. holes_deficit

    let rules = Rules.Instruction.rules

    let infer term = snd (Inference.infer_with_state term)

    let verbosity = X.verbosity
  end)

  let to_michelson ({typing; term} : State_space.t) =
    let typing = Lazy.force typing in
    let (node, (bef, aft), state) =
      Autocomp.complete_code typing term X.rng_state
    in
    let node =
      Micheline.strip_locations @@ Mikhailsky_to_michelson.convert node state
    in
    {
      term = node;
      bef = Type_helpers.stack_type_to_michelson_type_list bef;
      aft = Type_helpers.stack_type_to_michelson_type_list aft;
    }

  let generator ~burn_in =
    let open StaTz in
    Stats.map_gen to_michelson (MCMC.generator ~burn_in)
end

module Make_data_sampler
    (Michelson_base : Michelson_samplers_base.S)
    (Crypto_samplers : Crypto_samplers.Finite_key_pool_S) (X : sig
      val rng_state : Random.State.t

      val target_size : int

      val verbosity : [`Silent | `Progress | `Trace]
    end) =
struct
  module Autocomp = Autocomp.Make (Michelson_base) (Crypto_samplers)
  module Rewrite_rules =
    Rules.Data_rewrite_leaves (Michelson_base) (Crypto_samplers)

  module MCMC = Make_generic (struct
    let initial =
      let term = Mikhailsky.Data.hole in
      let typing =
        Lazy.from_val @@ snd (Inference.infer_data_with_state term)
      in
      {State_space.term; typing}

    let energy state =
      let stats = State_space.statistics state in
      let size_deficit =
        abs_float
          (float_of_int X.target_size -. float_of_int stats.State_space.size)
      in
      let holes_proportion =
        float_of_int stats.holes /. float_of_int stats.size
      in
      let holes_deficit =
        (* we want at least 10% of holes, above is ok *)
        if holes_proportion < 0.5 then (0.5 -. holes_proportion) *. size_deficit
        else 0.0
      in
      let depth_deficit =
        abs_float
          ((0.1 *. float_of_int X.target_size) -. float_of_int stats.depth)
      in
      size_deficit +. holes_deficit +. depth_deficit

    let rules = Rewrite_rules.rules X.rng_state

    let infer term = snd (Inference.infer_data_with_state term)

    let verbosity = X.verbosity
  end)

  let to_michelson ({typing; term} : State_space.t) =
    let typing = Lazy.force typing in
    let (node, _) = Autocomp.complete_data typing term X.rng_state in
    let (typ, state) =
      try Inference.infer_data_with_state node
      with _ ->
        Format.eprintf "Bug found!@." ;
        Format.eprintf "Ill-typed autocompletion. Resulting term:@." ;
        Format.eprintf "%a@." Mikhailsky.pp node ;
        Stdlib.failwith "in generators.ml: unrecoverable failure"
    in
    let node =
      Micheline.strip_locations @@ Mikhailsky_to_michelson.convert node state
    in
    {term = node; typ = base_type_to_michelson_type typ}

  let generator ~burn_in =
    let open StaTz in
    Stats.map_gen to_michelson (MCMC.generator ~burn_in)
end
