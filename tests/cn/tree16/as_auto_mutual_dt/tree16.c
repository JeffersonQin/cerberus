

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
datatype tree {
  Empty_Tree {},
  Node {integer v, list <datatype tree> children}
}

function (map <integer, datatype tree>) default_children ()

predicate {datatype tree t, integer v, map <integer, datatype tree> children}
  Tree (pointer p)
{
  if (p == NULL) {
    return {t: Empty_Tree {}, v: 0, children: default_children ()};
  }
  else {
    take V = Owned<int>((pointer)(((integer)p) + (offsetof (node, v))));
    let nodes_ptr = ((pointer)((((integer)p) + (offsetof (node, nodes)))));
    take Ns = each (integer i; (0 <= i) && (i < (num_nodes ())))
      {Indirect_Tree((pointer)(((integer)nodes_ptr) + (i * (sizeof <tree>))))};
    let ts = array_to_list (Ns, 0, num_nodes ());
    return {t: Node {v: V, children: ts}, v: V, children: Ns};
  }
}

predicate (datatype tree) Indirect_Tree (pointer p) {
  take V = Owned<tree>(p);
  take T = Tree(V);
  return T.t;
}

datatype arc_in_array {
  Arc_In_Array {map <integer, integer> arr, integer i, integer len}
}

function (boolean) in_tree (datatype tree t, datatype arc_in_array arc)
function (integer) tree_v (datatype tree t, datatype arc_in_array arc)

function [coq_unfold] (integer) tree_v_step (datatype tree t, datatype arc_in_array arc)
{
  match t {
    Empty_Tree {} => {
      0
    }
    Node {} => {
      let arc2 = Arc_In_Array {arr: arc.arr, i: arc.i + 1, len: arc.len};
      ((arc.i < arc.len) ?
        (tree_v(nth_list((arc.arr)[arc.i], t.children, Empty_Tree {}), arc2)) :
        t.v)
    }
  }
}

function [coq_unfold] (boolean) in_tree_step (datatype tree t, datatype arc_in_array arc)
{
  match t {
    Empty_Tree {} => {
      false
    }
    Node {} => {
      let arc2 = Arc_In_Array {arr: arc.arr, i: arc.i + 1, len: arc.len};
      ((arc.i < arc.len) ?
        (in_tree(nth_list((arc.arr)[arc.i], t.children, Empty_Tree {}), arc2)) :
        true)
    }
  }
}

lemma in_tree_tree_v_lemma (datatype tree t, datatype arc_in_array arc,
    map <integer, datatype tree> t_children)
  requires true
  ensures
    (tree_v(t, arc)) == (tree_v_step(t, arc));
    (in_tree(t, arc)) == (in_tree_step(t, arc))
@*/

int
lookup_rec (tree t, int *path, int i, int path_len, int *v)
/*@ requires take T = Tree(t) @*/
/*@ requires take Xs = each (integer j; (0 <= j) && (j < path_len))
    {Owned<typeof(i)>(path + (j * 4))} @*/
/*@ requires ((0 <= path_len) && (0 <= i) && (i <= path_len)) @*/
/*@ requires each (integer j; (0 <= j) && (j < path_len))
    {(0 <= (Xs[j])) && ((Xs[j]) < (num_nodes ()))} @*/
/*@ requires take V = Owned(v) @*/
/*@ requires let arc = Arc_In_Array {arr: Xs, i: i, len: path_len} @*/
/*@ ensures take T2 = Tree(t) @*/
/*@ ensures T2.t == {T.t}@start @*/
/*@ ensures T2.children == {T.children}@start @*/
/*@ ensures take Xs2 = each (integer j; (0 <= j) && (j < path_len))
    {Owned<typeof(i)>(path + (j * 4))} @*/
/*@ ensures Xs2 == {Xs}@start @*/
/*@ ensures take V2 = Owned(v) @*/
/*@ ensures ((return == 0) && (not (in_tree (T2.t, arc))))
  || ((return == 1) && (in_tree (T2.t, arc)) && ((tree_v (T2.t, arc)) == V2)) @*/
{
  int idx = 0;
  int r = 0;
  if (! t) {
    /*@ unpack Tree(t); @*/
    /*@ apply in_tree_tree_v_lemma(T.t, arc, T.children); @*/
    return 0;
  }
  if (i >= path_len) {
    *v = t->v;
    /*@ apply in_tree_tree_v_lemma(T.t, arc, T.children); @*/
    return 1;
  }
  /*@ instantiate i; @*/
  /*@ extract Owned<int>, i; @*/
  idx = path[i];
  /*@ extract Indirect_Tree, idx; @*/
  r = lookup_rec(t->nodes[idx], path, i + 1, path_len, v);
  /*@ apply in_tree_tree_v_lemma(T.t, arc, T.children); @*/
  /*@ unpack Tree(t); @*/
  if (r)
    return 1;
  else
    return 0;
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

