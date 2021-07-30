open! Base
open Hardcaml
open Signal

module Make (M : Hardcaml.Interface.S) = struct
  module I = struct
    type 'a t =
      { clock : 'a
      ; clear : 'a
      ; wr_data : 'a M.t [@rtlprefix "wr_"]
      ; wr_enable : 'a
      ; rd_enable : 'a
      }
    [@@deriving sexp_of, hardcaml]
  end

  module O = struct
    type 'a t =
      { rd_data : 'a M.t [@rtlprefix "rd_"]
      ; rd_valid : 'a
      ; full : 'a
      }
    [@@deriving sexp_of, hardcaml]
  end

  let create ~capacity (_scope : Scope.t) (i : _ I.t) =
    (* Fifo from [Fifo.create] has a one-cycle write latency. This means that
       writes on cycle [T] will be available immediately at cycle [T+1].
    *)
    let fifo_empty = wire 1 in
    let wr_underlying_fifo = i.wr_enable &: (~:fifo_empty |: ~:(i.rd_enable)) in
    let underlying_fifo =
      (* Explicitly tell vivado to use LUTRAM rather than BRAM, because
         this fifo should generally be small.
      *)
      Fifo.create
        ~ram_attributes:[ Rtl_attribute.Vivado.Ram_style.distributed ]
        ~overflow_check:true
        ~underflow_check:true
        ~showahead:true
        ~capacity
        ~clock:i.clock
        ~clear:i.clear
        ~wr:wr_underlying_fifo
        ~d:(M.Of_signal.pack i.wr_data)
        ~rd:(~:fifo_empty &: i.rd_enable)
        ()
    in
    fifo_empty <== underlying_fifo.empty;
    let rd_data =
      M.Of_signal.mux2
        underlying_fifo.empty
        i.wr_data
        (M.Of_signal.unpack underlying_fifo.q)
    in
    let rd_valid = ~:(i.clear) &: (~:(underlying_fifo.empty) |: i.wr_enable) in
    { O.full = underlying_fifo.full; rd_data; rd_valid }
  ;;

  let hierarchical ?instance ~capacity (scope : Scope.t) (i : _ I.t) =
    let module H = Hierarchy.In_scope (I) (O) in
    H.hierarchical ?instance ~scope ~name:"fast_fifo" (create ~capacity) i
  ;;
end
