let unroll = ref 10;;

(* set of values that will not be explored as values of the instruction pointer *)
module SAddresses = Set.Make(Z)
let blackAddresses = ref SAddresses.empty
		       
let dotfile = ref "";;
  
let size_of_byte = 8
		     
type memory_model_t =
  | Flat
  | Segmented
      
let memory_model = ref Flat

type format_t =
  | Pe
  | Elf

type mode_t =
  | Protected
  | Real

let mode = ref Protected
	       
let format = ref Pe
		 
type call_conv_t =
  | Cdecl
  | Stdcall
  | Fastcall

let call_conv = ref Cdecl
		    
let text = ref ""
let code_length = ref 0
let ep = ref Z.zero
let phys_code_addr = ref 0
let rva_code = ref Z.zero
		   
let address_sz = ref 32
let operand_sz = ref 32
let stack_width = ref 32

let gdt: (Z.t, Z.t) Hashtbl.t = Hashtbl.create 19
			 
let cs = ref Z.zero
let ds = ref Z.zero
let ss = ref Z.zero
let es = ref Z.zero
let fs = ref Z.zero
let gs = ref Z.zero


type tvalue =
  | Bits of Z.t
  | MBits of Z.t * Z.t (* second element is a mask on the first one *)

type cvalue = Z.t
		
(* initial state utilities *)
		    
let initial_register_content: (Register.t, cvalue) Hashtbl.t = Hashtbl.create 10
let initial_memory_content: (Z.t, cvalue) Hashtbl.t = Hashtbl.create 10 (* TODO: better signature would be keys of type Data.Address.t but this would imply that Config and Data would be mutually recursive *)
let initial_register_tainting: (Register.t, tvalue) Hashtbl.t = Hashtbl.create 10
let initial_memory_tainting: (Z.t, tvalue) Hashtbl.t = Hashtbl.create 10 (* TODO: better signature would be keys of type Data.Address.t but this would imply that Config and Data would be mutually recursive *)				   


(* tainting rules for functions *)
type taint =
  | No_taint
  | Buf_taint
  | Addr_taint

type tainting_fun = string * (call_conv_t * taint option * taint list)
								
let tainting_tbl: (string, tainting_fun list) Hashtbl.t = Hashtbl.create 7
				  
let add_tainting_rules libname fun_rules =
  let cfuns =
    try
      Hashtbl.find tainting_tbl libname
    with
      Not_found -> Hashtbl.add tainting_tbl libname []; []
  in
  Hashtbl.replace tainting_tbl libname (fun_rules::cfuns)


(** data stuctures for the assertions *)
let assert_untainted_functions: (Z.t, taint list) Hashtbl.t = Hashtbl.create 5
let assert_tainted_functions: (Z.t, taint list) Hashtbl.t = Hashtbl.create 5

(** import table *)
(** first string is the function name, the second one its library *)
let imports: (Z.t, (string * string)) Hashtbl.t = Hashtbl.create 5
