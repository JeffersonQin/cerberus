

enum {
  NUM_NODES = 16
};

struct node;

typedef struct node * tree;

struct node {
  int v;
  tree nodes[NUM_NODES];
};

/*@
function (integer) num_nodes ()
@*/

int cn_get_num_nodes (void)
/*@ cn_function num_nodes @*/
{
  return NUM_NODES;
}

/*@
datatype tree_arc {
  Arc_End {},
  Arc_Step {integer i, datatype tree_arc tail}
}

datatype tree_node_option {
  Node_None {},
  Node {integer v}
}

function (map<datatype tree_arc, datatype tree_node_option>) empty ()
function (map<datatype tree_arc, datatype tree_node_option>) construct
    (integer v, map<integer, map<datatype tree_arc, datatype tree_node_option> > ts)

function (map<integer, map<datatype tree_arc, datatype tree_node_option> >) default_ns ()

predicate {map<datatype tree_arc, datatype tree_node_option> t,
        integer v, map<integer, map<datatype tree_arc, datatype tree_node_option> > ns}
  Tree (pointer p)
{
  if (p == NULL) {
    return {t: (empty ()), v: 0, ns: default_ns ()};
  }
  else {
    take V = Owned<int>((pointer)(((integer)p) + (offsetof (node, v))));
    let nodes_ptr = ((pointer)((((integer)p) + (offsetof (node, nodes)))));
    take Ns = each (integer i; (0 <= i) && (i < (num_nodes ())))
      {Indirect_Tree((pointer)(((integer)nodes_ptr) + (i * (sizeof <tree>))))};
    let t = construct (V, Ns);
    return {t: t, v: V, ns: Ns};
  }
}

predicate (map <datatype tree_arc, datatype tree_node_option>) Indirect_Tree (pointer p) {
  take V = Owned<tree>(p);
  take T = Tree(V);
  return T.t;
}

function (datatype tree_arc) mk_arc (map <integer, integer> m, integer i, integer len)

predicate {datatype tree_arc arc, map<integer, integer> xs}
        Arc (pointer p, integer i, integer len) {
  assert (0 <= len);
  assert (i <= len);
  assert (0 <= i);
  take Xs = each (integer j; (0 <= j) && (j < len))
    {Owned<signed int>(p + (j * sizeof<signed int>))};
  assert (each (integer j; (0 <= j) && (j < len))
    {(0 <= Xs[j]) && (Xs[j] < (num_nodes ()))});
  return {arc: mk_arc(Xs, i, len), xs: Xs};
}

lemma mk_arc_lemma (map <integer, integer> m, integer i, integer len)
  requires ((0 <= len) && (0 <= i) && (i <= len))
  ensures (mk_arc(m, i, len)) ==
    (i < len ?
        Arc_Step {i: m[i], tail: mk_arc(m, i + 1, len)} :
        Arc_End {})

lemma empty_lemma (datatype tree_arc arc)
  requires true
  ensures ((empty ())[arc]) == Node_None {}

function (datatype tree_node_option) construct_app_rhs (integer v,
        map<integer, map<datatype tree_arc, datatype tree_node_option> > ns,
        datatype tree_arc arc)
{
  match arc {
    Arc_End {} => {
      Node {v: v}
    }
    Arc_Step {i: _, tail: _} => {
     ns[arc.i][arc.tail]
    }
  }
}

function (boolean) arc_first_idx_valid (datatype tree_arc arc)
{
  match arc {
    Arc_End {} => {
      true
    }
    Arc_Step {i: _, tail: _} => {
      (0 <= arc.i) && (arc.i < num_nodes())
    }
  }
}


lemma construct_lemma (integer v,
        map<integer, map<datatype tree_arc, datatype tree_node_option> > ns,
        datatype tree_arc arc)
  requires
    arc_first_idx_valid(arc)
  ensures
    ((construct(v, ns))[arc]) == (construct_app_rhs(v, ns, arc))

@*/

int
lookup_rec (tree t, int *path, int i, int path_len, int *v)
/*@ requires take T = Tree(t) @*/
/*@ requires take Xs = each (integer j; (0 <= j) && (j < path_len))
    {Owned<int>(path + (j * 4))} @*/
/*@ requires ((0 <= path_len) && (0 <= i) && (i <= path_len)) @*/
/*@ requires each (integer j; (0 <= j) && (j < path_len))
    {(0 <= (Xs[j])) && ((Xs[j]) < (num_nodes ()))} @*/
/*@ requires take V = Owned(v) @*/
/*@ requires let arc = mk_arc(Xs, i, path_len) @*/
/*@ ensures take T2 = Tree(t) @*/
/*@ ensures T2.t == {T.t}@start @*/
/*@ ensures take Xs2 = each (integer j; (0 <= j) && (j < path_len))
    {Owned<int>(path + (j * 4))} @*/
/*@ ensures Xs2 == {Xs}@start @*/
/*@ ensures take V2 = Owned(v) @*/
/*@ ensures ((return == 0) && ((T2.t[arc]) == Node_None {}))
  || ((return == 1) && ((T2.t[arc]) == Node {v: V2})) @*/
{
  int idx = 0;
  int r = 0;
  if (! t) {
    /*@ unpack Tree(t); @*/
    /*@ apply empty_lemma(arc); @*/
    return 0;
  }
  if (i >= path_len) {
    *v = t->v;
    /*@ apply mk_arc_lemma(Xs, i, path_len); @*/
    /*@ apply construct_lemma (T.v, T.ns, arc); @*/
    return 1;
  }
  /*@ apply mk_arc_lemma(Xs, i, path_len); @*/
  /*@ extract Owned<int>, i; @*/
  /*@ instantiate i; @*/
  idx = path[i];
  /*@ extract Indirect_Tree, idx; @*/
  r = lookup_rec(t->nodes[idx], path, i + 1, path_len, v);
  /*@ apply construct_lemma (T.v, T.ns, arc); @*/
  return r;
}

#ifdef NOT_CURRENTLY_WORKING
int
lookup (tree t, int *path, int path_len, int *v)
/*@ requires let T = Tree(t) @*/
/*@ requires let A = Arc(path, 0, path_len) @*/
/*@ requires let V = Owned(v) @*/
/*@ ensures let T2 = Tree(t) @*/
/*@ ensures T2.t == {T.t}@start @*/
/*@ ensures let A2 = Arc(path, 0, path_len) @*/
/*@ ensures A2.arc == {A.arc}@start @*/
/*@ ensures let V2 = Owned(v) @*/
/*@ ensures ((return == 0) && ((T2.t[A2.arc]) == Node_None {}))
  || ((return == 1) && ((T2.t[A2.arc]) == Node {v: V2})) @*/
{
  int i;

  for (i = 0; i < path_len; i ++)
  {
    if (! t) {
      return 0;
    }
    t = t->nodes[path[i]];
  }
  if (! t) {
    return 0;
  }
  *v = t->v;
  return 1;
}
#endif

