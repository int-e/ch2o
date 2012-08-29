(* Copyright (c) 2012, Robbert Krebbers. *)
(* This file is distributed under the terms of the BSD license. *)
(** This file collects some general purpose tactics that are used throughout
the development. *)
Require Export base.

(** The tactic [simplify_equality] repeatedly substitutes, discriminates,
and injects equalities, and tries to contradict impossible inequalities. *)
Ltac simplify_equality := repeat
  match goal with
  | |- _ => progress subst
  | |- _ = _ => reflexivity
  | H : _ ≠ _ |- _ => now destruct H
  | H : _ = _ → False |- _ => now destruct H
  | H : _ = _ |- _ => discriminate H
  | H : _ = _ |-  ?G =>
    (* avoid introducing additional equalities *)
    change (id G); injection H; clear H; intros; unfold id at 1
  end.

(** Coq's default [remember] tactic does have an option to name the generated
equality. The following tactic extends [remember] to do so. *)
Tactic Notation "remember" constr(t) "as" "(" ident(x) "," ident(E) ")" :=
  remember t as x;
  match goal with
  | E' : x = _ |- _ => rename E' into E
  end.

(** Given a list [l], the tactic [map tac l] runs [tac x] for each element [x]
of the list [l]. It will succeed for the first element [x] of [l] for which 
[tac x] succeeds. *)
Tactic Notation "map" tactic(tac) tactic(l) :=
  let rec go l :=
  match l with
  | nil => idtac
  | ?x :: ?l => tac x || go l
  end in go l.

(** Given H : [A_1 → ... → A_n → B] (where each [A_i] is non-dependent), the
tactic [feed tac H tac_by] creates a subgoal for each [A_i] and calls [tac p]
with the generated proof [p] of [B]. *)
Tactic Notation "feed" tactic(tac) constr(H) :=
  let rec go H :=
  let T := type of H in
  lazymatch eval hnf in T with
  | ?T1 → ?T2 =>
    (* Use a separate counter for fresh names to make it more likely that
    the generated name is "fresh" with respect to those generated before
    calling the [feed] tactic. In particular, this hack makes sure that
    tactics like [let H' := fresh in feed (fun p => pose proof p as H') H] do
    not break. *)
    let HT1 := fresh "feed" in assert T1 as HT1;
      [| go (H HT1); clear HT1 ]
  | ?T1 => tac H
  end in go H.

(** The tactic [efeed tac H] is similar to [feed], but it also instantiates
dependent premises of [H] with evars. *)
Tactic Notation "efeed" tactic(tac) constr(H) :=
  let rec go H :=
  let T := type of H in
  lazymatch eval hnf in T with
  | ?T1 → ?T2 =>
    let HT1 := fresh "feed" in assert T1 as HT1;
      [| go (H HT1); clear HT1 ]
  | ?T1 → _ =>
    let e := fresh "feed" in evar (e:T1);
    let e' := eval unfold e in e in
    clear e; go (H e')
  | ?T1 => tac H
  end in go H.

(** The following variants of [pose proof], [specialize], [inversion], and
[destruct], use the [feed] tactic before invoking the actual tactic. *)
Tactic Notation "feed" "pose" "proof" constr(H) "as" ident(H') :=
  feed (fun p => pose proof p as H') H.
Tactic Notation "feed" "pose" "proof" constr(H) :=
  feed (fun p => pose proof p) H.

Tactic Notation "efeed" "pose" "proof" constr(H) "as" ident(H') :=
  efeed (fun p => pose proof p as H') H.
Tactic Notation "efeed" "pose" "proof" constr(H) :=
  efeed (fun p => pose proof p) H.

Tactic Notation "feed" "specialize" hyp(H) :=
  feed (fun p => specialize p) H.
Tactic Notation "efeed" "specialize" hyp(H) :=
  efeed (fun p => specialize p) H.

Tactic Notation "feed" "inversion" constr(H) :=
  feed (fun p => let H':=fresh in pose proof p as H'; inversion H') H.
Tactic Notation "feed" "inversion" constr(H) "as" simple_intropattern(IP) :=
  feed (fun p => let H':=fresh in pose proof p as H'; inversion H' as IP) H.

Tactic Notation "feed" "destruct" constr(H) :=
  feed (fun p => let H':=fresh in pose proof p as H'; destruct H') H.
Tactic Notation "feed" "destruct" constr(H) "as" simple_intropattern(IP) :=
  feed (fun p => let H':=fresh in pose proof p as H'; destruct H' as IP) H.

(** The tactic [is_non_dependent H] determines whether the goal's conclusion or
assumptions depend on [H]. *)
Tactic Notation "is_non_dependent" constr(H) :=
  match goal with
  | _ : context [ H ] |- _ => fail 1
  | |- context [ H ] => fail 1
  | _ => idtac
  end.

(** Coq's [firstorder] tactic fails or loops on rather small goals already. In 
particular, on those generated by the tactic [unfold_elem_ofs] to solve
propositions on collections. The [naive_solver] tactic implements an ad-hoc
and incomplete [firstorder]-like solver using Ltac's backtracking mechanism.
The tactic suffers from the following limitations:
- It might leave unresolved evars as Ltac provides no way to detect that.
- To avoid the tactic going into pointless loops, it just does not allow a
  universally quantified hypothesis to be used more than once.
- It does not perform backtracking on instantiation of universally quantified
  assumptions.

Despite these limitations, it works much better than Coq's [firstorder] tactic
for the purposes of this development. This tactic either fails or proves the
goal. *)
Tactic Notation "naive_solver" tactic(tac) :=
  unfold iff, not in *;
  let rec go :=
  repeat match goal with
  (**i intros *)
  | |- ∀ _, _ => intro
  (**i simplification of assumptions *)
  | H : False |- _ => destruct H
  | H : _ ∧ _ |- _ => destruct H
  | H : ∃ _, _  |- _ => destruct H
  (**i simplify and solve equalities *)
  | |- _ => progress simpl in *
  | |- _ => progress simplify_equality
  (**i solve the goal *)
  | |- _ => eassumption
  | |- _ => now constructor
  | |- _ => now symmetry
  (**i operations that generate more subgoals *)
  | |- _ ∧ _ => split
  | H : _ ∨ _ |- _ => destruct H
  (**i solve the goal using the user supplied tactic *)
  | |- _ => solve [tac]
  end;
  (**i use recursion to enable backtracking on the following clauses *)
  match goal with
  (**i instantiations of assumptions *)
  | H : _ → _ |- _ =>
    is_non_dependent H; eapply H; clear H; go
  | H : _ → _ |- _ =>
    is_non_dependent H;
    (**i create subgoals for all premises *)
    efeed (fun p =>
      match type of p with
      | _ ∧ _ =>
        let H' := fresh in pose proof p as H'; destruct H'
      | ∃ _, _ =>
        let H' := fresh in pose proof p as H'; destruct H'
      | _ ∨ _ =>
        let H' := fresh in pose proof p as H'; destruct H'
      | False =>
        let H' := fresh in pose proof p as H'; destruct H'
      end) H;
    (**i solve these subgoals, but clear [H] to avoid loops *)
    clear H; go
  (**i instantiation of the conclusion *)
  | |- ∃ x, _ => eexists; go
  | |- _ ∨ _ => first [left; go | right; go]
  end in go.
Tactic Notation "naive_solver" := naive_solver eauto.
