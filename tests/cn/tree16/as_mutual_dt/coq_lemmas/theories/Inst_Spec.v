(* Instantiation of the CN-exported specification
   using results from the prior theories. *)

Require Import ZArith Bool Lia.
Require Import CN_Lemmas.Setup.
Require Import CN_Lemmas.Gen_Spec.
Import CN_Lemmas.Gen_Spec.Types.
Require Import List.
Import ListNotations.
Module Inst.

  Definition nth_tree_list (xs : tree_list) (n : Z) :=
    List.nth (Z.to_nat n) (Setup.to_list xs) Empty_Tree.

  Definition array_to_tree_list := Setup.array_to_list.

  Definition tree_v := Setup.tree_v.

  Definition in_tree := Setup.in_tree.
  
End Inst.

Module Defs := CN_Lemmas.Gen_Spec.Defs (Inst).

Module Proofs.

(* now prove lemmas *)
Import Defs Inst.
Open Scope Z.

Lemma z_to_nat_eq_0:
  forall (z : Z), z <= 0 -> Z.to_nat z = 0%nat.
Proof.
  lia.
Qed.

Lemma arc_from_array_step:
  forall arr i len, arc_from_array (Arc_In_Array arr i len) =
  match (len <=? i) with
  | true => []
  | false => arr i :: arc_from_array (Arc_In_Array arr (i + 1) len)
  end.
Proof.
  intros.
  destruct (len <=? i) eqn: le.
  - simpl.
    assert (Z.to_nat (len - i) = 0%nat) as eq by lia.
    rewrite eq.
    auto.
  - simpl.
    assert (Z.to_nat (len - i) = S (Z.to_nat (len - (i + 1)))) as eq by lia.
    rewrite eq.
    auto.
Qed.

Lemma in_tree_tree_v_lemma : in_tree_tree_v_lemma_type.
Proof.
  unfold in_tree_tree_v_lemma_type.
  intros.
  destruct arc as [arr i len].
  repeat (apply conj).
  (*
  - unfold in_tree, Setup.in_tree.
    rewrite (arc_from_array_step _ i).
    destruct (path_len <=? i) eqn: path_end.
    + destruct (get_t_0_3 T); auto.
    + destruct (get_t_0_3 T); auto.
    *)
  - unfold tree_v, Setup.tree_v.
    rewrite (arc_from_array_step _ i).
    simpl.
    rewrite Z.leb_antisym.
    destruct (i <? len) eqn: path_end.
    + destruct t; auto.
    + destruct t; auto.
  - unfold in_tree, Setup.in_tree.
    rewrite (arc_from_array_step _ i).
    simpl.
    rewrite Z.leb_antisym.
    destruct (i <? len) eqn: path_end.
    + destruct t; auto.
    + destruct t; auto.
  - unfold nth_tree_list, array_to_tree_list, Setup.array_to_list.
    rewrite to_list_of_list.
    cbn.
    destruct ((0 <=? arr i) && (arr i <? num_nodes)) eqn: ix_ok; try apply I.
    unfold num_nodes in *.
    rewrite nth_get_array_elts by lia.
    simpl.
    f_equal.
    lia.
Qed.

End Proofs.

Module InstOK: CN_Lemmas.Gen_Spec.Lemma_Spec(Inst).

  Module D := CN_Lemmas.Gen_Spec.Defs (Inst).

  Include Proofs.

End InstOK.

