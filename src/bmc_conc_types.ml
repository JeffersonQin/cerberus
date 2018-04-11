(* Adapted from cppmem model exploration tool *)
(*========================================================================*)
(*                                                                        *)
(*             cppmem model exploration tool                              *)
(*                                                                        *)
(*                    Mark Batty                                          *)
(*                    Scott Owens                                         *)
(*                    Jean Pichon                                         *)
(*                    Susmit Sarkar                                       *)
(*                    Peter Sewell                                        *)
(*                                                                        *)
(*  This file is copyright 2011, 2012 by the above authors.               *)
(*                                                                        *)
(*  Redistribution and use in source and binary forms, with or without    *)
(*  modification, are permitted provided that the following conditions    *)
(*  are met:                                                              *)
(*  1. Redistributions of source code must retain the above copyright     *)
(*  notice, this list of conditions and the following disclaimer.         *)
(*  2. Redistributions in binary form must reproduce the above copyright  *)
(*  notice, this list of conditions and the following disclaimer in the   *)
(*  documentation and/or other materials provided with the distribution.  *)
(*  3. The names of the authors may not be used to endorse or promote     *)
(*  products derived from this software without specific prior written    *)
(*  permission.                                                           *)
(*                                                                        *)
(*  THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS    *)
(*  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED     *)
(*  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE    *)
(*  ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY       *)
(*  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL    *)
(*  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE     *)
(*  GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS         *)
(*  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHE   *)
(*  IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR       *)
(*  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN   *)
(*  IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                         *)
(*========================================================================*)


open Z3

type aid = int
type tid = int

type memory_order =
  | NA
  | Seq_cst
  | Relaxed
  | Release
  | Acquire
  | Consume
  | Acq_rel

type flexsym = string

type cst =
  | Concrete of int  
  | Symbolic of string

type cvalue =
  | Rigid of cst
  | Flexible of flexsym
  | Z3Expr of Expr.expr

type location = int

type lock_outcome =
    Locked
  | Blocked

type action = 
  | Lock of aid * tid * location * lock_outcome
  | Unlock of aid * tid * location
  | Load of aid * tid * memory_order * location * cvalue
  | Store of aid * tid * memory_order * location * cvalue
  | RMW of aid * tid * memory_order * location * cvalue * cvalue
  | Fence of aid * tid * memory_order
  | Blocked_rmw of aid * tid * location

type location_kind =
  | Non_Atomic
  | Atomic
  | Mutex

type 'a set = 'a list
type 'a reln = ('a * 'a) list

type action_rel = action reln

type pre_execution =
  {   actions : action set;
      threads : tid set;
      lk      : (location, location_kind) Pmap.map; 
      sb      : action_rel ;
      asw     : action_rel ; 
(*      dd      : (action * action) set ; *)
(*      cd      : (action * action) set ; *)
  }

type execution_witness =
  {  rf      : action_rel;
     mo      : action_rel;
     (*
     sc      : (action * action) set;
     lo      : (action * action) set;
     ao      : (action * action) set;
     tot     : (action * action) set;
     *)
  }

type fault =
    One of action list
  | Two of action_rel

type execution_derived_data = {
  derived_relations : (string * action_rel) list; 
  undefined_behaviour : (string * fault) list;
}


type observable_execution = (pre_execution * execution_witness)

(*************************************************** *)
(*    Pp_stuff functions *)
(*************************************************** *)
type layoutmode = 
| LO_dot
| LO_neato_par
| LO_neato_par_init
| LO_neato_downwards

type ppmode = {
    fontsize    : int  ;
    fontname    : string  ;
    node_height : float;
    node_width  : float;
    filled      : bool;
    xscale      : float;
    yscale      : float;
    ranksep     : float;
    nodesep     : float;
    penwidth    : float;
    legend      : string option;
    layout      : layoutmode;
    texmode     : bool;
    thread_ids  : bool;
} 

let ppmode_default_web = {
  fontsize    = 10;
  fontname    = "Helvetica";
  node_height = 0.2;
  node_width  = 0.9;
  filled      = false;
  xscale      = 1.5;
  yscale      = 0.7;
  ranksep     = 0.2; (* for dot - but it seems to clip-below at 0.2, for no reason*)
  nodesep     = 0.25;   (* for dot and for self-loops in neato *)
  penwidth    = 1.0;
  legend      = None; (*Some "filename";*)
  layout      = LO_neato_downwards;
  texmode     = false;
  thread_ids  = false
}

  

(*************************************************** *)
(*    Projection functions *)
(*************************************************** *)


let aid_of a =    
((match a with
    | Lock( aid, _, _, _)            -> aid
    | Unlock( aid, _, _)            -> aid
    | Load( aid, _, _, _, _)          -> aid
    | Store( aid, _, _, _, _)         -> aid
    | RMW( aid, _, _, _, _, _)         -> aid
    | Fence( aid, _, _)             -> aid
    | Blocked_rmw( aid, _, _)       -> aid
    ))

let action_cmp a1 a2 = Pervasives.compare (aid_of a1) (aid_of a2)

let tid_of a =    
((match a with
      Lock( _, tid, _, _)           -> tid
    | Unlock( _, tid, _)           -> tid
    | Load( _, tid, _, _, _)         -> tid
    | Store( _, tid, _, _, _)        -> tid
    | RMW( _, tid, _, _, _, _)        -> tid
    | Fence( _, tid, _)            -> tid
    | Blocked_rmw( _, tid, _)      -> tid
    ))

let loc_of a =    
((match a with
      Lock( _, _, l, _)           -> Some( l)
    | Unlock( _, _, l)           -> Some( l)
    | Load( _, _, _, l, _)         -> Some( l)
    | Store( _, _, _, l, _)        -> Some( l)
    | RMW( _, _, _, l, _, _)        -> Some( l)
    | Fence( _, _, _)            -> None
    | Blocked_rmw( _, _, l)      -> Some( l)
    ))

let value_read_by a =    
((match a with
      Load( _, _, _, _, v)         -> Some( v)
    | RMW( _, _, _, _, v, _)        -> Some( v)
    | _                      -> None
    ))

let value_written_by a =    
((match a with
      Store( _, _, _, _, v)        -> Some( v)
    | RMW( _, _, _, _, _, v)        -> Some( v)
    | _                      -> None
    ))

let is_atomic_load a =    
((match a with
      Load( _, _, mo, _, _) -> mo <> NA
    | _               -> false
    ))

let is_atomic_store a =    
((match a with
      Store( _, _, mo, _, _) -> mo <> NA
    | _                -> false
    ))

let is_NA_load a =    
((match a with
      Load( _, _, mo, _, _) -> mo = NA
    | _               -> false
    ))

let is_NA_store a =    
((match a with
      Store( _, _, mo, _, _) -> mo = NA
    | _                -> false
    ))

let is_load a =    
((match a with
      Load( _, _, _, _, _) -> true
    | _              -> false
    ))

let is_store a =    
((match a with
      Store( _, _, _, _, _) -> true
    | _               -> false
    ))

let is_atomic_action a =    
((match a with
      Load( _, _, mo, _, _)  -> mo <> NA
    | Store( _, _, mo, _, _) -> mo <> NA
    | RMW( _, _, _, _, _, _)  -> true
    | _                -> false
    ))

let is_read a =    
((match a with
      Load( _, _, _, _, _)  -> true
    | RMW( _, _, _, _, _, _) -> true
    | _               -> false
    ))

let is_write a =    
((match a with
      Store( _, _, _, _, _) -> true
    | RMW( _, _, _, _, _, _) -> true
    | _               -> false
    ))

let is_acquire a =    
 ((match a with
      Load( _, _, mo, _, _)  -> Pset.mem  mo 
  (Pset.from_list Pervasives.compare [Acquire;Seq_cst])
    | RMW( _, _, mo, _, _, _) -> Pset.mem  mo 
  (Pset.from_list Pervasives.compare [Acquire;Acq_rel;Seq_cst])
    | Fence( _, _, mo)     -> Pset.mem  mo 
  (Pset.from_list Pervasives.compare [Acquire;Consume;Acq_rel;Seq_cst])
    | _                -> false
    ))

let is_release a =    
 ((match a with
      Store( _, _, mo, _, _)  -> Pset.mem  mo 
  (Pset.from_list Pervasives.compare [Release;Seq_cst])
    | RMW( _, _, mo, _, _, _)  -> Pset.mem  mo 
  (Pset.from_list Pervasives.compare [Release;Acq_rel;Seq_cst])
    | Fence( _, _, mo)      -> Pset.mem  mo 
  (Pset.from_list Pervasives.compare [Release;Acq_rel;Seq_cst])
    | _                 -> false
    ))
