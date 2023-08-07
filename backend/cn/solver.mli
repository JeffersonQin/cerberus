type solver
type model
type model_with_q = model * (Sym.t * LogicalSorts.t) list

val random_seed : int ref
val log_to_temp : bool ref

val make : Global.t -> solver

val push : solver -> unit
val pop : solver -> unit
val add_assumption : solver -> Global.t -> LogicalConstraints.t -> unit

val set_slow_threshold : float -> unit


val provable : 
  loc:Locations.t ->
  solver:solver -> 
  global:Global.t -> 
  assumptions:Context.LCSet.t -> 
  simp_ctxt:Simplify.simp_ctxt ->
  pointer_facts:IndexTerms.t list ->
  LogicalConstraints.t -> 
  [> `True | `False ]


val model : 
  unit -> 
  model_with_q



val eval : 
  Global.t -> 
  model -> 
  IndexTerms.t -> 
  IndexTerms.t option


val get_loc_addrs_in_eqs : solver ->
  pointer_facts:IndexTerms.t list ->
  Global.t -> Sym.t list



