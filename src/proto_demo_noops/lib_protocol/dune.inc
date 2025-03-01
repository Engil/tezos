

;
;        /!\ /!\ Do not modify this file /!\ /!\
;
; but the original template in `tezos-protocol-compiler`
;

; generated from src/lib_protocol_compiler/dune_protocol.template.v1

; This template is intended for protocols written after the Tezos
; project start using OCaml 4.12.
;
; template.v1 was introduced when we bumped the version of our OCaml
; dependency to 4.12.  This change to a newer OCaml version introduced
; new warnings that need to be ignored in the protocols written before
; the update (see dune_protocol.template.v0).

(rule
 (targets environment.ml)
 (action
  (write-file %{targets}
              "module Name = struct let name = \"demo-noops\" end
include Tezos_protocol_environment.MakeV4(Name)()
module CamlinternalFormatBasics = struct include CamlinternalFormatBasics end
")))

(rule
 (targets registerer.ml)
 (deps
   main.mli main.ml
   (:src_dir TEZOS_PROTOCOL))
 (action
  (with-stdout-to %{targets}
                  (chdir %{workspace_root} (run %{bin:tezos-embedded-protocol-packer} "%{src_dir}" "demo_noops")))))

(rule
 (targets functor.ml)
 (deps
   main.mli main.ml
   (:src_dir TEZOS_PROTOCOL))
 (action (with-stdout-to %{targets}
                         (chdir %{workspace_root}
                                (run %{bin:tezos-protocol-compiler.tezos-protocol-packer} %{src_dir})))))

(rule
 (targets protocol.ml)
 (deps
   main.mli main.ml)
 (action
  (write-file %{targets}
    "module Environment = Tezos_protocol_environment_demo_noops.Environment
let hash = Tezos_crypto.Protocol_hash.of_b58check_exn \"ProtoDemoNoopsDemoNoopsDemoNoopsDemoNoopsDemo6XBoYp\"
let name = Environment.Name.name
include Tezos_raw_protocol_demo_noops
include Tezos_raw_protocol_demo_noops.Main
")))

(library
 (name tezos_protocol_environment_demo_noops)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-demo-noops.environment)
 (library_flags (:standard -linkall))
 (libraries tezos-protocol-environment)
 (modules Environment))

(library
 (name tezos_raw_protocol_demo_noops)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-demo-noops.raw)
 (libraries tezos_protocol_environment_demo_noops)
 (library_flags (:standard -linkall))
 (flags (:standard -nopervasives -nostdlib
                   -w +a-4-40..42-44-45-48
                   -warn-error +a
                   -open Tezos_protocol_environment_demo_noops__Environment
                   -open Pervasives
                   -open Error_monad))
 (modules
   Main))

(install
 (section lib)
 (package tezos-protocol-demo-noops)
 (files (TEZOS_PROTOCOL as raw/TEZOS_PROTOCOL)))

(library
 (name tezos_protocol_demo_noops)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-demo-noops)
 (libraries
      tezos-protocol-environment
      tezos-protocol-environment-sigs
      tezos_raw_protocol_demo_noops)
 (flags -w "+a-4-40..42-44-45-48"
        -warn-error "+a"
        -nopervasives)
 (modules Protocol))

(library
 (name tezos_protocol_demo_noops_functor)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-protocol-functor-demo-noops)
 (libraries
      tezos-protocol-environment
      tezos-protocol-environment-sigs
      tezos-protocol-demo-noops.raw)
 (flags -w "+a-4-40..42-44-45-48"
        -warn-error "+a"
        -nopervasives)
 (modules Functor))

(library
 (name tezos_embedded_protocol_demo_noops)
 (instrumentation (backend bisect_ppx))
 (public_name tezos-embedded-protocol-demo-noops)
 (library_flags (:standard -linkall))
 (libraries tezos-protocol-demo-noops
            tezos-protocol-updater
            tezos-protocol-environment)
 (flags (:standard -w +a-4-40..42-44-45-48
                   -warn-error +a))
 (modules Registerer))

(rule
 (alias runtest_compile_protocol)
 (deps
   main.mli main.ml
  (:src_dir TEZOS_PROTOCOL))
 (action (run %{bin:tezos-protocol-compiler} -no-hash-check .)))

(rule
 (alias runtest_sandbox)
 (deps .tezos_protocol_demo_noops.objs/native/tezos_protocol_demo_noops.cmx)
 (action (progn)))

(rule
 (alias runtest)
 (package tezos-protocol-demo-noops)
 (deps (alias runtest_sandbox))
 (action (progn)))
