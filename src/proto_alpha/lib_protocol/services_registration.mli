(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020-2021 Nomadic Labs <contact@nomadic-labs.com>           *)
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

open Alpha_context

type rpc_context = {
  block_hash : Block_hash.t;
  block_header : Block_header.shell_header;
  context : t;
}

val rpc_init : Updater.rpc_context -> rpc_context Error_monad.tzresult Lwt.t

val register0 :
  ( [< RPC_service.meth],
    Updater.rpc_context,
    Updater.rpc_context,
    'a,
    'b,
    'c )
  RPC_service.t ->
  (t -> 'a -> 'b -> 'c Error_monad.tzresult Lwt.t) ->
  unit

val register0_noctxt :
  ([< RPC_service.meth], Updater.rpc_context, 'a, 'b, 'c, 'd) RPC_service.t ->
  ('b -> 'c -> 'd Error_monad.tzresult Lwt.t) ->
  unit

val register1_fullctxt :
  ( [< RPC_service.meth],
    Updater.rpc_context,
    Updater.rpc_context * 'a,
    'b,
    'c,
    'd )
  RPC_service.t ->
  (rpc_context -> 'a -> 'b -> 'c -> 'd Error_monad.tzresult Lwt.t) ->
  unit

val register1 :
  ( [< RPC_service.meth],
    Updater.rpc_context,
    Updater.rpc_context * 'a,
    'b,
    'c,
    'd )
  RPC_service.t ->
  (t -> 'a -> 'b -> 'c -> 'd Error_monad.tzresult Lwt.t) ->
  unit

val register2 :
  ( [< RPC_service.meth],
    Updater.rpc_context,
    (Updater.rpc_context * 'a) * 'b,
    'c,
    'd,
    'e )
  RPC_service.t ->
  (t -> 'a -> 'b -> 'c -> 'd -> 'e Error_monad.tzresult Lwt.t) ->
  unit

val get_rpc_services : unit -> Updater.rpc_context RPC_directory.directory
