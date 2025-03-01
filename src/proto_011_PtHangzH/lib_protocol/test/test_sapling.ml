(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** Testing
    -------
    Component:  Protocol (Sapling)
    Invocation: cd src/proto_alpha/lib_protocol/test
                dune exec ./main.exe -- test "^sapling$"
    Subject:    On the privacy-preserving library Sapling
*)

open Protocol

let ( >>??= ) x y =
  match x with
  | Ok s -> y s
  | Error err -> Lwt.return @@ Error (Environment.wrap_tztrace err)

module Raw_context_tests = struct
  open Sapling_helpers.Common

  (* This test adds to the first 100 positions in the commitments tree the
     constant value `uncommitted` for which we know the corresponding root and
     tests that the returned root is as expected. *)
  let commitments_add_uncommitted () =
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    let module H = Tezos_sapling.Core.Client.Hash in
    let cm = H.uncommitted ~height:0 in
    let expected_root = H.uncommitted ~height:32 in
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id) ->
    Sapling_storage.init ctx id ~memo_size:0 >>= wrap >>=? fun ctx ->
    List.fold_left_es
      (fun ctx pos ->
        Sapling_storage.Commitments.get_root ctx id >>= wrap
        >>=? fun (ctx, root) ->
        assert (root = expected_root) ;
        Sapling_storage.Commitments.add
          ctx
          id
          [H.to_commitment cm]
          (Int64.of_int pos)
        >>= wrap
        >>=? fun (ctx, _size) ->
        Sapling_storage.Commitments.get_root ctx id >>= wrap
        >|=? fun (ctx, root) ->
        assert (root = expected_root) ;
        ctx)
      ctx
      (0 -- 99)
    >>=? fun _ctx -> return_unit

  (* Nullifiers don't check for duplicates are it's done by verify_update,
     however committing to disk twice the same nf causes a storage error by
     trying to initialize the same key twice. *)
  let nullifier_double () =
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id) ->
    Sapling_storage.init ctx id ~memo_size:0 >>= wrap >>=? fun ctx ->
    let nf = gen_nf () in
    let open Sapling_storage in
    let state =
      {id = Some id; diff = Sapling_storage.empty_diff; memo_size = 0}
    in
    let state = nullifiers_add state nf in
    let state = nullifiers_add state nf in
    assert (List.length state.diff.nullifiers = 2) ;
    Sapling_storage.Nullifiers.size ctx id >>= wrap >>=? fun disk_size ->
    assert (disk_size = 0L) ;
    Sapling_storage.apply_diff ctx id state.diff |> assert_error

  (* In this test we add two lists of nullifiers to the state, one is applied to
     the context (committed to disk) and one is kept in kept in a diff (only in
     memory). We then check that nullifier_mem answers true for those two lists
     and false for a third one. *)
  let nullifier_test () =
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id) ->
    Sapling_storage.init ctx id ~memo_size:0 >>= wrap >>=? fun ctx ->
    let nf_list_ctx =
      List.init ~when_negative_length:() 10 (fun _ -> gen_nf ()) |> function
      | Error () -> assert false (* 10 > 0 *)
      | Ok nf_list_ctx -> nf_list_ctx
    in
    let state =
      List.fold_left
        (fun state nf -> Sapling_storage.nullifiers_add state nf)
        {id = Some id; diff = Sapling_storage.empty_diff; memo_size = 0}
        nf_list_ctx
    in
    Sapling_storage.apply_diff ctx id state.diff >>= wrap >>=? fun (ctx, _) ->
    let nf_list_diff =
      List.init ~when_negative_length:() 10 (fun _ -> gen_nf ()) |> function
      | Error () -> assert false (* 10 > 0 *)
      | Ok nf_list_diff -> nf_list_diff
    in
    let state =
      List.fold_left
        (fun state nf -> Sapling_storage.nullifiers_add state nf)
        state
        nf_list_diff
    in
    List.iter_ep
      (fun nf ->
        Sapling_storage.nullifiers_mem ctx state nf >>= wrap
        >>=? fun (_, bool) ->
        assert bool ;
        return_unit)
      (nf_list_ctx @ nf_list_diff)
    >>=? fun () ->
    let nf_list_absent =
      List.init 10 ~when_negative_length:() (fun _ -> gen_nf ()) |> function
      | Error () -> assert false (* 10 > 0 *)
      | Ok nf_list_absent -> nf_list_absent
    in
    List.iter_ep
      (fun nf ->
        Sapling_storage.nullifiers_mem ctx state nf >>= wrap
        >>=? fun (_, bool) ->
        assert (not bool) ;
        return_unit)
      nf_list_absent

  (* This test applies a diff with tuples of ciphertext, commitment. Then it
     checks the result of get_from with different indexes. *)
  let cm_cipher_test () =
    Random.self_init () ;
    let memo_size = Random.int 200 in
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id) ->
    Sapling_storage.init ctx id ~memo_size >>= wrap >>=? fun ctx ->
    Sapling_storage.state_from_id ctx id >>= wrap >>=? fun (diff, ctx) ->
    let list_added =
      List.init ~when_negative_length:() 10 (fun _ ->
          gen_cm_cipher ~memo_size ())
      |> function
      | Error () -> assert false (* 10 > 0 *)
      | Ok list_added -> list_added
    in
    let state = Sapling_storage.add diff list_added in
    Sapling_storage.apply_diff ctx id state.diff >>= wrap >>=? fun (ctx, _) ->
    let rec test_from from until expected =
      if from > until then return_unit
      else
        Sapling_storage.Ciphertexts.get_from ctx id from >>= wrap
        >>=? fun (ctx, result) ->
        let expected_cipher = List.map snd expected in
        assert (result = expected_cipher) ;
        Sapling_storage.Commitments.get_from ctx id from >>= wrap
        >>=? fun result ->
        let expected_cm = List.map fst expected in
        assert (result = expected_cm) ;
        test_from
          (Int64.succ from)
          until
          (WithExceptions.Option.get ~loc:__LOC__ @@ List.tl expected)
    in
    test_from 0L 9L list_added

  (* This test tests the insertion of a list vs inserting one by one.
     It does so by checking the equality of the roots. *)
  let list_insertion_test () =
    Random.self_init () ;
    let memo_size = Random.int 200 in
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id_one_by_one) ->
    Sapling_storage.init ctx id_one_by_one ~memo_size >>= wrap >>=? fun ctx ->
    let list_to_add =
      fst @@ List.split
      @@ (List.init ~when_negative_length:() 33 (fun _ ->
              gen_cm_cipher ~memo_size ())
          |> function
          | Error () -> assert false (* 33 > 0 *)
          | Ok r -> r)
    in
    let rec test counter ctx =
      if counter >= 32 then return_unit
      else
        (* add a single cm to the existing tree *)
        Sapling_storage.Commitments.add
          ctx
          id_one_by_one
          [
            WithExceptions.Option.get ~loc:__LOC__
            @@ List.nth list_to_add counter;
          ]
          (Int64.of_int counter)
        >>= wrap
        (* create a new tree and add a list of cms *)
        >>=? fun (ctx, _size) ->
        Lazy_storage_diff.fresh
          Lazy_storage_kind.Sapling_state
          ~temporary:false
          ctx
        >>= wrap
        >>=? fun (ctx, id_all_at_once) ->
        Sapling_storage.init ctx id_all_at_once ~memo_size >>= wrap
        >>=? fun ctx ->
        Sapling_storage.Commitments.add
          ctx
          id_all_at_once
          (List.init ~when_negative_length:() (counter + 1) (fun i ->
               WithExceptions.Option.get ~loc:__LOC__ @@ List.nth list_to_add i)
           |> function
           | Error () -> assert false (* counter >= 0*)
           | Ok r -> r)
          0L
        >>= wrap
        >>=? fun (ctx, _size) ->
        Sapling_storage.Commitments.get_root ctx id_one_by_one >>= wrap
        >>=? fun (ctx, root_one_by_one) ->
        Sapling_storage.Commitments.get_root ctx id_all_at_once >>= wrap
        >>=? fun (ctx, root_all_at_once) ->
        assert (root_all_at_once = root_one_by_one) ;
        test (counter + 1) ctx
    in
    test 0 ctx

  (* This test adds 10 more roots the maximum capacity, all at different
     levels, and checks that all but the first 10 are stored.
     Then it adds one in the diff and checks it is stored.
     Then it adds 10 at the same level and check that only the last one is
     stored. *)
  let root_test () =
    let open Tezos_sapling.Core in
    let gen_root () =
      Data_encoding.Binary.of_bytes_exn
        Validator.Hash.encoding
        (Hacl.Rand.gen 32)
    in
    let roots_ctx =
      List.init
        ~when_negative_length:()
        (Int32.to_int Sapling_storage.Roots.size + 10)
        (fun _ -> gen_root ())
      |> function
      | Error () -> assert false (* size >= 0 *)
      | Ok roots_ctx -> roots_ctx
    in
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id) ->
    Sapling_storage.init ctx id ~memo_size:0 >>= wrap >>=? fun ctx ->
    (* Add one root per level to the context *)
    List.fold_left_es
      (fun (ctx, cnt) root ->
        Sapling_storage.Roots.add ctx id root >>= wrap >>=? fun ctx ->
        (* Very low level way to "bake" a block. It would be better to use the
           helpers functions but they complicate the access to the raw_context. *)
        Raw_context.prepare
          ~level:(Int32.add b.header.shell.level cnt)
          ~predecessor_timestamp:b.header.shell.timestamp
          ~timestamp:b.header.shell.timestamp
          ~fitness:b.header.shell.fitness
          (Raw_context.recover ctx)
        >>= wrap
        >|=? fun ctx -> (ctx, Int32.succ cnt))
      (ctx, 0l)
      roots_ctx
    >>=? fun (ctx, _) ->
    (* Check mem on all the roots in the context. *)
    let state =
      Sapling_storage.
        {id = Some id; diff = Sapling_storage.empty_diff; memo_size = 0}
    in
    List.fold_left_es
      (fun i root ->
        Sapling_storage.root_mem ctx state root >>= wrap >|=? fun bool ->
        assert (if i < 10 then not bool else bool) ;
        i + 1)
      0
      roots_ctx
    >>=? fun _ ->
    (* Add roots w/o increasing the level *)
    let roots_same_level =
      List.init ~when_negative_length:() 10 (fun _ -> gen_root ()) |> function
      | Error () -> assert false (* 10 > 0 *)
      | Ok roots_same_level -> roots_same_level
    in
    List.fold_left_es
      (fun ctx root -> Sapling_storage.Roots.add ctx id root >>= wrap)
      ctx
      roots_same_level
    >>=? fun ctx ->
    List.fold_left_es
      (fun (i, ctx) root ->
        Sapling_storage.root_mem ctx state root >>= wrap >|=? fun bool ->
        assert (if i < 9 then not bool else bool) ;
        (i + 1, ctx))
      (0, ctx)
      roots_same_level
    >>=? fun _ -> return_unit

  let test_get_memo_size () =
    Context.init 1 >>=? fun (b, _) ->
    Raw_context.prepare
      b.context
      ~level:b.header.shell.level
      ~predecessor_timestamp:b.header.shell.timestamp
      ~timestamp:b.header.shell.timestamp
      ~fitness:b.header.shell.fitness
    >>= wrap
    >>=? fun ctx ->
    Lazy_storage_diff.fresh Lazy_storage_kind.Sapling_state ~temporary:false ctx
    >>= wrap
    >>=? fun (ctx, id) ->
    Sapling_storage.init ctx id ~memo_size:0 >>= wrap >>=? fun ctx ->
    Sapling_storage.get_memo_size ctx id >>= wrap >|=? fun memo_size ->
    assert (memo_size = 0)
end

module Alpha_context_tests = struct
  open Sapling_helpers.Alpha_context_helpers

  (* Create a transaction with memo_size 1, test that is validates with a newly
     created empty_state with memo_size 1 and does not with memo_size 0. *)
  let test_verify_memo () =
    init () >>=? fun ctx ->
    let sk =
      Tezos_sapling.Core.Wallet.Spending_key.of_seed
        (Tezos_crypto.Hacl.Rand.gen 32)
    in
    let vt =
      let ps = Tezos_sapling.Storage.empty ~memo_size:0 in
      (* the dummy output will have memo_size 0 *)
      Tezos_sapling.Forge.forge_transaction
        ~number_dummy_outputs:1
        []
        []
        sk
        "anti-replay"
        ps
    in
    verify_update ctx vt ~memo_size:0 |> assert_some >>=? fun _ ->
    verify_update ctx vt ~memo_size:1 |> assert_none

  (* Bench the proving and validation time of shielding and transferring several
     tokens. *)
  let test_bench_phases () =
    init () >>=? fun ctx ->
    let rounds = 5 in
    Printf.printf "\nrounds: %d\n" rounds ;
    let w = wallet_gen () in
    let cs = Tezos_sapling.Storage.empty ~memo_size:8 in
    (* one verify_update to get the id *)
    let vt = transfer w cs [] in
    verify_update ctx vt |> assert_some >>=? fun (ctx, id) ->
    client_state_alpha ctx id >>=? fun cs ->
    let start = Unix.gettimeofday () in
    let vts = List.map (fun _ -> transfer w cs []) (1 -- rounds) in
    let ctime_shields = Unix.gettimeofday () -. start in
    Printf.printf "client_shields %f\n" ctime_shields ;
    let start = Unix.gettimeofday () in
    List.fold_left_es
      (fun ctx vt ->
        verify_update ctx ~id vt |> assert_some >|=? fun (ctx, _id) -> ctx)
      ctx
      vts
    >>=? fun ctx ->
    let vtime_shields = Unix.gettimeofday () -. start in
    Printf.printf "valdtr_shields %f\n" vtime_shields ;
    client_state_alpha ctx id >>=? fun cs ->
    let start = Unix.gettimeofday () in
    let vts = List.map (fun i -> transfer w cs [i]) (1 -- rounds) in
    let ctime_transfers = Unix.gettimeofday () -. start in
    Printf.printf "client_txs %f\n" ctime_transfers ;
    let start = Unix.gettimeofday () in
    List.fold_left_es
      (fun ctx vt ->
        verify_update ctx ~id vt |> assert_some >|=? fun (ctx, _id) -> ctx)
      ctx
      vts
    >|=? fun _ctx ->
    let vtime_transfers = Unix.gettimeofday () -. start in
    Printf.printf "valdtr_txs %f\n" vtime_transfers

  (* Transfer several times the same token. *)
  let test_bench_fold_over_same_token () =
    init () >>=? fun ctx ->
    let rounds = 5 in
    let w = wallet_gen () in
    let cs = Tezos_sapling.Storage.empty ~memo_size:8 in
    (* one verify_update to get the id *)
    let vt = transfer w cs [] in
    verify_update ctx vt |> assert_some >>=? fun (ctx, id) ->
    let rec loop cnt ctx =
      if cnt >= rounds then return_unit
      else
        (* inefficient: re-synch from scratch at each round *)
        client_state_alpha ctx id >>=? fun cs ->
        let vt = transfer w cs [cnt] in
        verify_update ctx ~id vt |> assert_some >>=? fun (ctx, _id) ->
        loop (cnt + 1) ctx
    in
    loop 0 ctx

  (*
    The following tests trigger all the branches of
    Sapling_validator.verify_update.
    The function performs several checks and returns None in case of failure.
    During development the function was modified to throw a different exception
    for each of its checks so to be sure that they were reached.
   *)

  (* Test that double spending the same input fails the nf check. *)
  let test_double_spend_same_input () =
    init () >>=? fun ctx ->
    let w = wallet_gen () in
    let cs = Tezos_sapling.Storage.empty ~memo_size:8 in
    (* one verify_update to get the id *)
    let vt = transfer w cs [] in
    verify_update ctx vt |> assert_some >>=? fun (ctx, id) ->
    client_state_alpha ctx id >>=? fun cs ->
    let vt = transfer w cs [0] in
    verify_update ctx ~id vt |> assert_some >>=? fun (_ctx, id) ->
    let vt = transfer w cs [0; 0] in
    verify_update ctx ~id vt |> assert_none

  let test_verifyupdate_one_transaction () =
    init () >>=? fun ctx ->
    let w = wallet_gen () in
    let cs = Tezos_sapling.Storage.empty ~memo_size:8 in
    let vt = transfer w cs [] in
    verify_update ctx vt |> assert_some >>=? fun (ctx, id) ->
    client_state_alpha ctx id >>=? fun cs ->
    let vt = transfer w cs [0] in
    (* fails sig check because of wrong balance *)
    let vt_broken =
      Tezos_sapling.Core.Validator.UTXO.
        {vt with balance = Int64.(succ vt.balance)}
    in
    verify_update ctx ~id vt_broken |> assert_none >>=? fun () ->
    (* randomize one output to fail check outputs *)
    (* don't randomize the ciphertext as it is not part of the proof *)
    let open Tezos_sapling.Core.Client.UTXO in
    let o = WithExceptions.Option.get ~loc:__LOC__ @@ List.hd vt.outputs in
    let o_wrong_cm =
      {
        o with
        cm = randomized_byte o.cm Tezos_sapling.Core.Client.Commitment.encoding;
      }
    in
    let vt_broken =
      Tezos_sapling.Core.Validator.UTXO.{vt with outputs = [o_wrong_cm]}
    in
    verify_update ctx ~id vt_broken |> assert_none >>=? fun () ->
    (* position inside the cv *)
    let pos = Random.int 32 in
    let o_wrong_cv =
      {
        o with
        ciphertext =
          randomized_byte
            ~pos
            o.ciphertext
            Tezos_sapling.Core.Client.Ciphertext.encoding;
      }
    in
    let vt_broken =
      Tezos_sapling.Core.Validator.UTXO.{vt with outputs = [o_wrong_cv]}
    in
    verify_update ctx ~id vt_broken |> assert_none

  let test_verifyupdate_two_transactions () =
    init () >>=? fun ctx ->
    let w = wallet_gen () in
    let cs = Tezos_sapling.Storage.empty ~memo_size:8 in
    (* generate the first storage *)
    let vt = transfer w cs [] in
    verify_update ctx vt |> assert_some >>=? fun (ctx, id1) ->
    client_state_alpha ctx id1 >>=? fun cs1 ->
    let vt1 = transfer w cs1 [0] in
    (* generate the second storage *)
    let vt = transfer w cs [] in
    verify_update ctx vt |> assert_some >>=? fun (ctx, id2) ->
    client_state_alpha ctx id2 >>=? fun cs2 ->
    let vt2 = transfer w cs2 [0] in
    (* fail root check *)
    verify_update ctx ~id:id1 vt2 |> assert_none >>=? fun () ->
    (* Swap the root so that it passes the root_mem check but fails
       the input check *)
    let vt1_broken =
      Tezos_sapling.Core.Validator.UTXO.{vt2 with root = vt1.root}
    in
    verify_update ctx ~id:id1 vt1_broken |> assert_none >>=? fun () ->
    (* fail the sig check *)
    let vt1_broken =
      Tezos_sapling.Core.Validator.UTXO.{vt1 with outputs = vt2.outputs}
    in
    verify_update ctx ~id:id1 vt1_broken |> assert_none
end

module Interpreter_tests = struct
  open Sapling_helpers.Interpreter_helpers

  let parameters_of_list transactions =
    let string = "{ " ^ String.concat " ; " transactions ^ " }" in
    Alpha_context.Script.(lazy_expr (expression_from_string string))

  (* In this test we use a contract which takes a list of transactions, applies
     all of them, and assert all of them are correct. It also enforces a 1-to-1
     conversion with mutez by asking an amount to shield and asking for a pkh to
     unshield.
     We create 2 keys a and b. We originate the contract, then do two lists of
     shield for a, then transfers several outputs to b while unshielding, then
     transfer all of b inputs to a while adding dummy inputs and outputs.
     At last we fail we make a failing transaction. *)
  let test_shielded_tez () =
    init () >>=? fun (b, baker, src0, src1) ->
    let memo_size = 8 in
    originate_contract "contracts/sapling_contract.tz" "{ }" src0 b baker
    >>=? fun (dst, b, anti_replay) ->
    let wa = wallet_gen () in
    let (list_transac, total) =
      shield
        ~memo_size
        wa.sk
        4
        wa.vk
        (Format.sprintf "Pair 0x%s None")
        anti_replay
    in
    let parameters = parameters_of_list list_transac in
    (* a does a list of shield transaction *)
    transac_and_sync ~memo_size b parameters total src0 dst baker
    >>=? fun (b, _state) ->
    (* we shield again on another block, forging with the empty state *)
    let (list_transac, total) =
      shield
        ~memo_size
        wa.sk
        4
        wa.vk
        (Format.sprintf "Pair 0x%s None")
        anti_replay
    in
    let parameters = parameters_of_list list_transac in
    (* a does a list of shield transaction *)
    transac_and_sync ~memo_size b parameters total src0 dst baker
    >>=? fun (b, state) ->
    (* address that will receive an unshield *)
    Context.Contract.balance (B b) src1 >>=? fun balance_before_shield ->
    let wb = wallet_gen () in
    let list_addr = gen_addr 15 wb.vk in
    let list_forge_input =
      List.init ~when_negative_length:() 14 (fun pos_int ->
          let pos = Int64.of_int pos_int in
          let forge_input =
            snd
              (Tezos_sapling.Forge.Input.get state pos wa.vk
              |> WithExceptions.Option.get ~loc:__LOC__)
          in
          forge_input)
      |> function
      | Error () -> assert false (* 14 > 0 *)
      | Ok list_forge_input -> list_forge_input
    in
    let list_forge_output =
      List.map
        (fun addr -> Tezos_sapling.Forge.make_output addr 1L (Bytes.create 8))
        list_addr
    in
    let hex_transac =
      to_hex
        (Tezos_sapling.Forge.forge_transaction
           ~number_dummy_inputs:0
           ~number_dummy_outputs:0
           list_forge_input
           list_forge_output
           wa.sk
           anti_replay
           state)
        Tezos_sapling.Core.Client.UTXO.transaction_encoding
    in
    let hex_pkh =
      to_hex
        (Alpha_context.Contract.is_implicit src1
        |> WithExceptions.Option.get ~loc:__LOC__)
        Signature.Public_key_hash.encoding
    in
    let string =
      Format.sprintf "{Pair 0x%s (Some 0x%s) }" hex_transac hex_pkh
    in
    let parameters =
      Alpha_context.Script.(lazy_expr (expression_from_string string))
    in
    (* a transfers to b and unshield some money to src_2 (the pkh) *)
    transac_and_sync ~memo_size b parameters 0 src0 dst baker
    >>=? fun (b, state) ->
    Context.Contract.balance (B b) src1 >>=? fun balance_after_shield ->
    let diff =
      Int64.sub
        (Test_tez.Tez.to_mutez balance_after_shield)
        (Test_tez.Tez.to_mutez balance_before_shield)
    in
    (* The inputs total [total] mutez and 15 of those are transfered in shielded tez *)
    assert (Int64.equal diff (Int64.of_int (total - 15))) ;
    let list_forge_input =
      List.init ~when_negative_length:() 15 (fun i ->
          let pos = Int64.of_int (i + 14 + 14) in
          let forge_input =
            snd
              (Tezos_sapling.Forge.Input.get state pos wb.vk
              |> WithExceptions.Option.get ~loc:__LOC__)
          in
          forge_input)
      |> function
      | Error () -> assert false (* 14 > 0 *)
      | Ok list_forge_input -> list_forge_input
    in
    let addr_a =
      snd
      @@ Tezos_sapling.Core.Client.Viewing_key.new_address
           wa.vk
           Tezos_sapling.Core.Client.Viewing_key.default_index
    in
    let output = Tezos_sapling.Forge.make_output addr_a 15L (Bytes.create 8) in
    let hex_transac =
      to_hex
        (Tezos_sapling.Forge.forge_transaction
           ~number_dummy_inputs:2
           ~number_dummy_outputs:2
           list_forge_input
           [output]
           wb.sk
           anti_replay
           state)
        Tezos_sapling.Core.Client.UTXO.transaction_encoding
    in
    let string = Format.sprintf "{Pair 0x%s None }" hex_transac in
    let parameters =
      Alpha_context.Script.(lazy_expr (expression_from_string string))
    in
    (* b transfers to a with dummy inputs and outputs *)
    transac_and_sync ~memo_size b parameters 0 src0 dst baker
    >>=? fun (b, _state) ->
    (* Here we fail by doing the same transaction again*)
    Incremental.begin_construction b >>=? fun incr ->
    let fee = Test_tez.Tez.of_int 10 in
    Op.transaction ~fee (B b) src0 dst Test_tez.Tez.zero ~parameters
    >>=? fun operation ->
    Incremental.add_operation (* TODO make more precise *)
      ~expect_failure:(fun _ -> return_unit)
      incr
      operation
    >>=? fun _incr -> return_unit

  let test_push_sapling_state_should_be_forbidden () =
    init ()
    (* Originating a contract to get a sapling_state with ID 0, used in the next contract *)
    >>=?
    fun (block, baker, src, _) ->
    originate_contract "contracts/sapling_contract.tz" "{ }" src block baker
    >>=? fun _ ->
    (* Originating the next contract should fail *)
    originate_contract
      "contracts/sapling_push_sapling_state.tz"
      "{ }"
      src
      block
      baker
    >>= function
    | Error
        [
          Environment.Ecoproto_error (Script_tc_errors.Ill_typed_contract _);
          Environment.Ecoproto_error
            (Script_tc_errors.Unexpected_lazy_storage _);
        ] ->
        return_unit
    | _ -> assert false

  let test_use_state_from_other_contract_and_transact () =
    (*
     Attempt to use a sapling state of a contract A in a contract B
     *)
    init () (* Originating the contracts *) >>=? fun (block, baker, src, _) ->
    let memo_size = 8 in
    (* originate_contract "contracts/sapling_contract.tz" "{ }" src block baker
       >>=? fun (_shielded_pool_contract_address, block, _anti_replay_shielded_pool)
                -> *)
    originate_contract
      "contracts/sapling_use_existing_state.tz"
      "{ }"
      src
      block
      baker
    >>=? fun (existing_state_contract_address, block, anti_replay_2) ->
    (* we create one shielding transaction and transform it in Micheline to use
       it as a parameter
    *)
    let wa = wallet_gen () in
    let (transactions, _total) =
      shield
        ~memo_size
        wa.sk
        1
        wa.vk
        (Format.sprintf "(Pair 0x%s 0)")
        anti_replay_2
    in
    let transaction =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.hd transactions
    in
    let parameters =
      Alpha_context.Script.(lazy_expr (expression_from_string transaction))
    in
    transac_and_sync
      ~memo_size
      block
      parameters
      0
      src
      existing_state_contract_address
      baker
    >|= function
    | Ok _ -> Alcotest.failf "Unexpected operations success"
    | Error errs ->
        assert (
          List.exists
            (function
              | Environment.Ecoproto_error
                  (Tezos_raw_protocol_011_PtHangzH.Script_tc_errors
                   .Unexpected_forged_value _) ->
                  true
              | _ -> false)
            errs) ;
        Result.return_unit

  (* In this test we do two transactions in one block and same two in two block.
     We check that the sate is the same expect for roots.
     The second transaction is possible only if the first one is done. *)
  let test_transac_and_block () =
    init () >>=? fun (b, baker, src, _) ->
    let memo_size = 8 in
    originate_contract "contracts/sapling_contract.tz" "{ }" src b baker
    >>=? fun (dst, block_start, anti_replay) ->
    let {sk; vk} = wallet_gen () in
    let hex_transac_1 = hex_shield ~memo_size {sk; vk} anti_replay in
    let string_1 = Format.sprintf "{Pair %s None }" hex_transac_1 in
    let parameters_1 =
      Alpha_context.Script.(lazy_expr (expression_from_string string_1))
    in
    transac_and_sync ~memo_size block_start parameters_1 15 src dst baker
    >>=? fun (block_1, state) ->
    let intermediary_root = Tezos_sapling.Storage.get_root state in
    let addr =
      snd
      @@ Tezos_sapling.Core.Wallet.Viewing_key.(new_address vk default_index)
    in
    let output = Tezos_sapling.Forge.make_output addr 15L (Bytes.create 8) in
    let hex_transac_2 =
      "0x"
      ^ to_hex
          (Tezos_sapling.Forge.forge_transaction
             [
               snd
                 (Tezos_sapling.Forge.Input.get state 0L vk
                 |> WithExceptions.Option.get ~loc:__LOC__);
             ]
             [output]
             sk
             anti_replay
             state)
          Tezos_sapling.Core.Client.UTXO.transaction_encoding
    in
    let string_2 = Format.sprintf "{Pair %s None }" hex_transac_2 in
    let parameters_2 =
      Alpha_context.Script.(lazy_expr (expression_from_string string_2))
    in
    transac_and_sync ~memo_size block_1 parameters_2 0 src dst baker
    >>=? fun (block_1, state_1) ->
    let final_root = Tezos_sapling.Storage.get_root state_1 in
    Alpha_services.Contract.single_sapling_get_diff
      Block.rpc_ctxt
      block_1
      dst
      ~offset_commitment:0L
      ~offset_nullifier:0L
      ()
    >>=? fun (_root, diff_1) ->
    let fee = Test_tez.Tez.of_int 10 in
    Test_tez.Tez.(one_mutez *? Int64.of_int 15) >>?= fun amount_tez ->
    Op.transaction
      ~fee
      (B block_start)
      src
      dst
      amount_tez
      ~parameters:parameters_1
    >>=? fun operation ->
    Incremental.begin_construction block_start >>=? fun incr ->
    Incremental.add_operation incr operation >>=? fun incr ->
    (* We need to manually get the counter here *)
    let ctx = Incremental.alpha_ctxt incr in
    let pkh =
      Alpha_context.Contract.is_implicit src
      |> WithExceptions.Option.get ~loc:__LOC__
    in
    Alpha_context.Contract.get_counter ctx pkh >>= wrap >>=? fun counter ->
    Op.transaction
      ~counter
      ~fee
      (B block_start)
      src
      dst
      Test_tez.Tez.zero
      ~parameters:parameters_2
    >>=? fun operation ->
    Incremental.add_operation incr operation >>=? fun incr ->
    Incremental.finalize_block incr >>=? fun block_2 ->
    Alpha_services.Contract.single_sapling_get_diff
      Block.rpc_ctxt
      block_2
      dst
      ~offset_commitment:0L
      ~offset_nullifier:0L
      ()
    >>=? fun (_root, diff_2) ->
    (* We check that the same transactions have passed *)
    assert (diff_1 = diff_2) ;
    let is_root_in block dst root =
      Incremental.begin_construction block >>=? fun incr ->
      let ctx_2 = Incremental.alpha_ctxt incr in
      Alpha_services.Contract.script Block.rpc_ctxt block dst >>=? fun script ->
      let ctx_without_gas_2 = Alpha_context.Gas.set_unlimited ctx_2 in
      Script_ir_translator.parse_script
        ctx_without_gas_2
        ~legacy:true
        ~allow_forged_in_storage:true
        script
      >>= wrap
      >>=? fun (Ex_script script, ctxt) ->
      Script_ir_translator.get_single_sapling_state
        ctxt
        script.storage_type
        script.storage
      |> wrap
      >>=? fun (id, _ctx_2) ->
      let single_id = WithExceptions.Option.get ~loc:__LOC__ id in
      let id =
        Lazy_storage_kind.Sapling_state.Id.parse_z
        @@ Alpha_context.Sapling.Id.unparse_to_z single_id
      in
      Raw_context.prepare
        block.context
        ~level:block.header.shell.level
        ~predecessor_timestamp:block.header.shell.timestamp
        ~timestamp:block.header.shell.timestamp
        ~fitness:block.header.shell.fitness
      >>= wrap
      >>=? fun raw_ctx -> Sapling_storage.Roots.mem raw_ctx id root >>= wrap
    in
    (* We check that the second state did not store the root in between
         transactions. *)
    is_root_in block_2 dst intermediary_root |> assert_false >>=? fun () ->
    (* We check that the second state did store the final root. *)
    is_root_in block_2 dst final_root |> assert_true >>=? fun () ->
    (* We check that the first state did store the final root. *)
    is_root_in block_1 dst final_root |> assert_true >>=? fun () ->
    (* We check that the first state did store the root in between transactions. *)
    is_root_in block_1 dst intermediary_root |> assert_true

  (* In this test we try a contract which creates an empty sapling state on the
     fly. It then applies a list of transactions, checks they are correct and
     drops the result. We make several shields in the same list (since the state
     is drop). *)
  let test_drop () =
    init () >>=? fun (b, baker, src, _) ->
    originate_contract "contracts/sapling_contract_drop.tz" "Unit" src b baker
    >>=? fun (dst, b, anti_replay) ->
    let {sk; vk} = wallet_gen () in
    let (list_transac, _total) =
      shield ~memo_size:8 sk 4 vk (Format.sprintf "0x%s") anti_replay
    in
    let parameters = parameters_of_list list_transac in
    Op.transaction
      ~fee:(Test_tez.Tez.of_int 10)
      (B b)
      src
      dst
      Test_tez.Tez.zero
      ~parameters
    >>=? fun operation ->
    next_block b operation >>=? fun _b -> return_unit

  (* We use a contrac with two states. Its parameter is two transactions and a
     bool. The two transactions are tested valid against the two states, but
     only one state according to the bool is updated.
     We do two transactions shielding to different keys in the two states.
     At each transactions both are applied but only state is updated.
     We then check that the first state is updated in the correct way. *)
  let test_double () =
    init () >>=? fun (b, baker, src, _) ->
    let memo_size = 8 in
    originate_contract
      "contracts/sapling_contract_double.tz"
      "(Pair { } { })"
      src
      b
      baker
    >>=? fun (dst, b, anti_replay) ->
    let wa = wallet_gen () in
    let hex_transac_1 = hex_shield ~memo_size wa anti_replay in
    let wb = wallet_gen () in
    let hex_transac_2 = hex_shield ~memo_size wb anti_replay in
    let str_1 =
      "(Pair True (Pair " ^ hex_transac_1 ^ " " ^ hex_transac_2 ^ "))"
    in
    let str_2 =
      "(Pair False (Pair " ^ hex_transac_2 ^ " " ^ hex_transac_1 ^ "))"
    in
    (* transac 1 is applied to state_1*)
    let parameters_1 =
      Alpha_context.Script.(lazy_expr (expression_from_string str_1))
    in
    (* tranasc_2 is applied to state_2*)
    let parameters_2 =
      Alpha_context.Script.(lazy_expr (expression_from_string str_2))
    in
    let fee = Test_tez.Tez.of_int 10 in
    Op.transaction ~fee (B b) src dst Test_tez.Tez.zero ~parameters:parameters_1
    >>=? fun operation ->
    next_block b operation >>=? fun b ->
    Op.transaction ~fee (B b) src dst Test_tez.Tez.zero ~parameters:parameters_2
    >>=? fun operation ->
    next_block b operation >>=? fun b ->
    Incremental.begin_construction b >>=? fun incr ->
    let ctx = Incremental.alpha_ctxt incr in
    let ctx_without_gas = Alpha_context.Gas.set_unlimited ctx in
    Alpha_services.Contract.storage Block.rpc_ctxt b dst >>=? fun storage ->
    let storage_lazy_expr = Alpha_context.Script.lazy_expr storage in

    (let memo_size = memo_size_of_int memo_size in
     let open Script_typed_ir in
     let state_ty = sapling_state_t ~memo_size ~annot:None in
     pair_t (-1) (state_ty, None, None) (state_ty, None, None) ~annot:None)
    >>??= fun tytype ->
    Script_ir_translator.parse_storage
      ctx_without_gas
      ~legacy:true
      ~allow_forged:true
      tytype
      ~storage:storage_lazy_expr
    >>= wrap
    >>=? fun ((state_1, state_2), _ctx) ->
    (*Only works when diff is empty*)
    let local_state_from_disk disk_state ctx =
      let id =
        Alpha_context.Sapling.(disk_state.id)
        |> WithExceptions.Option.get ~loc:__LOC__
      in
      Alpha_context.Sapling.get_diff
        ctx
        id
        ~offset_commitment:0L
        ~offset_nullifier:0L
        ()
      >>= wrap
      >|=? fun diff -> client_state_of_diff ~memo_size diff
    in
    local_state_from_disk state_1 ctx >>=? fun state_1 ->
    local_state_from_disk state_2 ctx >|=? fun state_2 ->
    (* we check that first state contains 15 to addr_1 but not 15 to addr_2*)
    assert (Option.is_some @@ Tezos_sapling.Forge.Input.get state_1 0L wa.vk) ;
    assert (Option.is_some @@ Tezos_sapling.Forge.Input.get state_2 0L wa.vk) ;
    assert (Option.is_none @@ Tezos_sapling.Forge.Input.get state_1 0L wb.vk) ;
    assert (Option.is_none @@ Tezos_sapling.Forge.Input.get state_2 0L wb.vk)

  let test_state_as_arg () =
    init () >>=? fun (b, baker, src, _) ->
    originate_contract
      "contracts/sapling_contract_state_as_arg.tz"
      "None"
      src
      b
      baker
    >>=? fun (dst, b, anti_replay) ->
    originate_contract "contracts/sapling_contract_send.tz" "Unit" src b baker
    >>=? fun (dst_2, b, anti_replay_2) ->
    let w = wallet_gen () in
    let hex_transac_1 = hex_shield ~memo_size:8 w anti_replay in
    let string = "Left " ^ hex_transac_1 in
    let parameters =
      Alpha_context.Script.(lazy_expr (expression_from_string string))
    in
    let fee = Test_tez.Tez.of_int 10 in
    Op.transaction ~fee (B b) src dst Test_tez.Tez.zero ~parameters
    >>=? fun operation ->
    next_block b operation >>=? fun b ->
    let contract = "0x" ^ to_hex dst Alpha_context.Contract.encoding in
    let hex_transac_2 = hex_shield ~memo_size:8 w anti_replay_2 in
    let string = "(Pair " ^ contract ^ " " ^ hex_transac_2 ^ ")" in
    let parameters =
      Alpha_context.Script.(lazy_expr (expression_from_string string))
    in
    Op.transaction ~fee (B b) src dst_2 Test_tez.Tez.zero ~parameters
    >>=? fun operation ->
    next_block b operation >>=? fun _b -> return_unit
end

let tests =
  [
    Tztest.tztest
      "commitments_add_uncommitted"
      `Quick
      Raw_context_tests.commitments_add_uncommitted;
    Tztest.tztest "nullifier_double" `Quick Raw_context_tests.nullifier_double;
    Tztest.tztest "nullifier_test" `Quick Raw_context_tests.nullifier_test;
    Tztest.tztest "cm_cipher_test" `Quick Raw_context_tests.cm_cipher_test;
    Tztest.tztest
      "list_insertion_test"
      `Quick
      Raw_context_tests.list_insertion_test;
    Tztest.tztest "root" `Quick Raw_context_tests.root_test;
    Tztest.tztest
      "test_get_memo_size"
      `Quick
      Raw_context_tests.test_get_memo_size;
    Tztest.tztest "test_verify_memo" `Quick Alpha_context_tests.test_verify_memo;
    Tztest.tztest
      "test_bench_phases"
      `Slow
      Alpha_context_tests.test_bench_phases;
    Tztest.tztest
      "test_bench_fold_over_same_token"
      `Slow
      Alpha_context_tests.test_bench_fold_over_same_token;
    Tztest.tztest
      "test_double_spend_same_input"
      `Quick
      Alpha_context_tests.test_double_spend_same_input;
    Tztest.tztest
      "test_verifyupdate_one_transaction"
      `Quick
      Alpha_context_tests.test_verifyupdate_one_transaction;
    Tztest.tztest
      "test_verifyupdate_two_transactions"
      `Quick
      Alpha_context_tests.test_verifyupdate_two_transactions;
    Tztest.tztest "test_shielded_tez" `Quick Interpreter_tests.test_shielded_tez;
    Tztest.tztest
      "test use state from other contract and transact"
      `Quick
      Interpreter_tests.test_use_state_from_other_contract_and_transact;
    Tztest.tztest
      "Instruction PUSH sapling_state 0 should be forbidden"
      `Quick
      Interpreter_tests.test_push_sapling_state_should_be_forbidden;
    Tztest.tztest
      "test_transac_and_block"
      `Quick
      Interpreter_tests.test_transac_and_block;
    Tztest.tztest "test_drop" `Quick Interpreter_tests.test_drop;
    Tztest.tztest "test_double" `Quick Interpreter_tests.test_double;
    Tztest.tztest "test_state_as_arg" `Quick Interpreter_tests.test_state_as_arg;
  ]
