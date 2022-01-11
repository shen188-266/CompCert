Require Import Smallstep.
Require Import Machregs.
Require Import UserAsm.
Require Import Integers.
Require Import List.
Require Import ZArith.
Require Import Memtype.
Require Import Memory.
Require Import Archi.
Require Import Coqlib.
Require Import AST.
Require Import Globalenvs.
Require Import Events.
Require Import Values.
Require Import Conventions1.
(* Require Import RawAsm AsmFacts AsmRegs. *)
(* Require Import LocalLib. *)
Require Import SSAsm.
Require Import UserAsmFacts AsmRegs.

(* CompCertELF/backend/Asmgenproof0 *)
Lemma find_instr_in:
  forall c pos i,
  find_instr pos c = Some i -> In i c.
Proof.
  induction c; simpl. intros; discriminate.
  intros until i. case (zeq pos 0); intros.
  left; congruence. right; eauto.
Qed.

(* CompCertELF/x86/AsmFacts *)
(*
(** instructions which have no relationship with stack *)
Definition stk_unrelated_instr (i: instruction) :=
  match i with
    Pallocframe _ _
  | Pfreeframe _ _
  | Pcall _ _
  | Pret => false
  | _ => true
  end.

Definition asm_instr_no_rsp (i : instruction) : Prop :=
  forall ge f rs m rs' m',
    stk_unrelated_instr i = true ->
    UserAsm.exec_instr ge f i rs m = Next rs' m' ->
    rs # RSP = rs' # RSP.

Definition asm_code_no_rsp (c : UserAsm.code) : Prop :=
  forall i,
    In i c ->
    asm_instr_no_rsp i.
*)

Section WFASM.


  Fixpoint in_builtin_arg (b: builtin_arg preg) (r: preg) :=
    match b with
    | BA x => if preg_eq r x then True else False
    | BA_splitlong ba1 ba2 => in_builtin_arg ba1 r \/ in_builtin_arg ba2 r
    | _ => False
    end.

  Inductive is_alloc : instruction -> Prop :=
    is_alloc_intro sz ora:
      is_alloc (Pallocframe sz ora).

  Definition make_palloc f  : instruction :=
    let sz := fn_stacksize f in
    (Pallocframe sz (Ptrofs.sub (Ptrofs.repr (align sz 8)) (Ptrofs.repr (size_chunk Mptr)))).
  
  Lemma make_palloc_is_alloc:
    forall f,
      is_alloc (make_palloc f).
  Proof. constructor. Qed.
  
  Inductive is_free : instruction -> Prop :=
    is_free_intro sz ora:
      is_free (Pfreeframe sz ora).

  Lemma is_free_dec:
    forall i,
      {is_free i} + {~ is_free i}.
  Proof.
    destruct i; try now (right; intro A; inv A).
    left. econstructor; eauto.
  Defined.
  
  Inductive is_jmp: instruction -> Prop :=
  | is_jmp_intro:
      forall ros sg,
        is_jmp (Pjmp ros sg).

  Inductive intermediate_instruction : instruction -> Prop :=
  | ii_alloc i: is_alloc i -> intermediate_instruction i
  | ii_jmp i: i = Pret \/ is_jmp i -> intermediate_instruction i.

  Record wf_asm_function (f: function): Prop :=
    {

      wf_asm_alloc_only_at_beginning:
        forall o sz ora,
          find_instr o (fn_code f) = Some (Pallocframe sz ora) ->
          o = 0;

      wf_asm_alloc_at_beginning:
        find_instr 0 (fn_code f) = Some (make_palloc f);

      wf_asm_after_freeframe:
        forall i o,
          find_instr (Ptrofs.unsigned o) (fn_code f) = Some i ->
          is_free i ->
          exists i' ,
            find_instr (Ptrofs.unsigned (Ptrofs.add o (Ptrofs.repr (instr_size i)))) (fn_code f) = Some i' /\
            (i' = Pret \/ is_jmp i' );

      wf_asm_ret_jmp_comes_after_freeframe:
        forall i o,
          find_instr (Ptrofs.unsigned o) (fn_code f) = Some i ->
          i = Pret \/ is_jmp i ->
          exists o' ifree,
            find_instr (Ptrofs.unsigned o') (fn_code f) = Some ifree /\
            is_free ifree /\
            Ptrofs.unsigned o' + instr_size ifree = Ptrofs.unsigned o;

      wf_asm_code_bounded:
        0 <= code_size (fn_code f) <= Ptrofs.max_unsigned;

      wf_asm_builtin_not_PC:
        forall o ef args res,
          find_instr o (fn_code f) = Some (Pbuiltin ef args res) ->
          ~ in_builtin_res res PC /\
          ~ in_builtin_res res RSP
          /\ Forall (fun arg : builtin_arg preg => ~ in_builtin_arg arg RA) args;

      wf_asm_jmp_no_rsp:
        forall o (r: ireg) sg,
          find_instr o (fn_code f) = Some (Pjmp (inl r) sg) ->
          r <> RSP;

      wf_asm_call_no_rsp:
        forall o (r: ireg) sg,
          find_instr o (fn_code f) = Some (Pcall (inl r) sg) ->
          r <> RSP;
      
      wf_asm_free_spec:
        forall o sz ora,
          find_instr o (fn_code f) = Some (Pfreeframe sz ora) ->
          sz = fn_stacksize f /\ ora = Ptrofs.sub (Ptrofs.repr (align (Z.max 0 sz) 8)) (Ptrofs.repr (size_chunk Mptr));

      wf_allocframe_repr:
        forall o sz ora,
          find_instr o (fn_code f) = Some (Pallocframe sz ora) ->
          align sz 8 - size_chunk Mptr =
          Ptrofs.unsigned (Ptrofs.sub (Ptrofs.repr (align sz 8)) (Ptrofs.repr (size_chunk Mptr)));

      wf_freeframe_repr:
        forall o sz ora,
          find_instr o (fn_code f) = Some (Pfreeframe sz ora) ->
          Ptrofs.repr (align sz 8 - size_chunk Mptr) = Ptrofs.sub (Ptrofs.repr (align (Z.max 0 sz) 8)) (Ptrofs.repr (size_chunk Mptr));
      
    }.

 
  Definition is_make_palloc a f :=  a = make_palloc f /\
                                    align (fn_stacksize f) 8 - size_chunk Mptr =
                                    Ptrofs.unsigned (Ptrofs.sub (Ptrofs.repr (align (fn_stacksize f) 8)) (Ptrofs.repr (size_chunk Mptr))).

  Lemma pair_eq: forall {A B}
                   (Adec: forall (a b: A), {a = b} + {a <> b})
                   (Bdec: forall (a b: B), {a = b} + {a <> b}),
      forall (a b: A * B), {a = b} + {a <> b}.
  Proof.
    intros.
    destruct a, b.
    destruct (Adec a a0), (Bdec b b0); subst;
      first [ now (right; inversion 1; congruence)
            | left; reflexivity ].
  Defined.
  
  Definition pallocframe_dec s s' o o': {Pallocframe s o = Pallocframe s' o'} + {Pallocframe s o <> Pallocframe s' o'}.
  Proof.
    destruct (zeq s s'); subst. 2: (now right; inversion 1).
    destruct (Ptrofs.eq_dec o o'); subst. 2: (now right; inversion 1).
    left; reflexivity.
  Defined.

  Lemma and_dec: forall {A B: Prop},
      { A } + { ~ A } ->
      { B } + { ~ B } ->
      { A /\ B } + { ~ (A /\ B) }.
  Proof.
    intros. destruct H, H0; [left|right|right|right]; intuition.
  Qed.

  Definition is_make_palloc_dec a f : { is_make_palloc a f } + { ~ is_make_palloc a f }.
  Proof.
    unfold is_make_palloc, make_palloc.
    destruct a; try (now right; inversion 1).
    apply and_dec.
    apply pallocframe_dec.
    apply zeq.
  Defined.

  Definition check_ret_or_jmp roj :=
    match roj with
    | Pret | Pjmp _ _ => true
    | _ => false
    end.

  Definition valid_ret_or_jmp roj :=
    match roj with
    | Pjmp (inl r) _ =>  negb (preg_eq r RSP)
    | _ => true
    end.
  
  Definition check_free f sz ora :=
      sz = fn_stacksize f /\ ora = Ptrofs.sub (Ptrofs.repr (align (Z.max 0 sz) 8)) (Ptrofs.repr (size_chunk Mptr)) /\
      Ptrofs.repr (align sz 8 - size_chunk Mptr) = Ptrofs.sub (Ptrofs.repr (align (Z.max 0 sz) 8)) (Ptrofs.repr (size_chunk Mptr)).

  Definition check_free_dec f sz ora : { check_free f sz ora } + { ~ check_free f sz ora }.
  Proof.
    unfold check_free.
    apply and_dec. 2: apply and_dec.
    apply zeq. apply Ptrofs.eq_dec. apply Ptrofs.eq_dec.
  Defined.

  Definition check_builtin args res :=
    ~ in_builtin_res res PC /\
    ~ in_builtin_res res RSP
    /\ Forall (fun arg : builtin_arg preg => ~ in_builtin_arg arg RA) args.

  Lemma not_in_builtin_res_dec res r:
    {~ in_builtin_res res r} + {~ ~ in_builtin_res res r}.
  Proof.
    induction res; simpl.
    destruct (preg_eq x r); subst; intuition. left; inversion 1.
    destruct IHres1, IHres2; try (right; now intuition). left. intuition congruence.
  Qed.


  Lemma not_in_builtin_arg_dec arg r:
    {~ in_builtin_arg arg r} + {~ ~ in_builtin_arg arg r}.
  Proof.
    induction arg; simpl; try (try destr; left; now inversion 1).
    destruct IHarg1, IHarg2; try (right; now intuition). left. intuition congruence.
  Qed.
  
  Definition check_builtin_dec args res: {check_builtin args res} + { ~ check_builtin args res}.
  Proof.
    unfold check_builtin.
    repeat apply and_dec.
    apply not_in_builtin_res_dec.
    apply not_in_builtin_res_dec.
    apply Forall_dec. intros.
    apply not_in_builtin_arg_dec.
  Defined.

  Lemma find_instr_bound:
    forall c o i,
      find_instr o c = Some i ->
      o + instr_size i <= code_size c.
  Proof.
    induction c; simpl; intros; eauto. congruence.
    destr_in H. inv H. generalize (code_size_non_neg c). lia.
    apply IHc in H. lia.      
  Qed.
    
  Lemma code_bounded_repr':
    forall c
      (RNG: 0 <= code_size c <= Ptrofs.max_unsigned)
      i o
      (FI: find_instr o c = Some i)
      sz
      (LE: 0 <= sz <= instr_size i),
      Ptrofs.unsigned (Ptrofs.add (Ptrofs.repr o) (Ptrofs.repr sz)) = o + sz.
  Proof.
    intros.
    unfold Ptrofs.add.
    rewrite (Ptrofs.unsigned_repr sz). 2: generalize (instr_size_repr i); lia.
    generalize (find_instr_bound _ _ _ FI) (find_instr_pos_positive _ _ _ FI) (instr_size_positive i). intros.
    rewrite (Ptrofs.unsigned_repr o) by lia.
    apply Ptrofs.unsigned_repr; lia.
  Qed.

  Lemma code_bounded_repr:
    forall c
      (RNG: 0 <= code_size c <= Ptrofs.max_unsigned)
      i o
      (FI: find_instr (Ptrofs.unsigned o) c = Some i)
      sz
      (LE: 0 <= sz <= instr_size i),
      Ptrofs.unsigned (Ptrofs.add o (Ptrofs.repr sz)) = Ptrofs.unsigned o + sz.
  Proof.
    intros.
    erewrite <- code_bounded_repr'; eauto.
    unfold Ptrofs.add.
    rewrite Ptrofs.repr_unsigned. reflexivity.
  Qed.

  Lemma wf_asm_pc_repr' : forall f : function,
       wf_asm_function f ->
       forall (i : instruction) (o : ptrofs),
       find_instr (Ptrofs.unsigned o) (fn_code f) = Some i ->
       forall sz : Z, 0 <= sz <= instr_size i -> Ptrofs.unsigned (Ptrofs.add o (Ptrofs.repr sz)) = Ptrofs.unsigned o + sz.
  Proof.
    intros; eapply code_bounded_repr; eauto.
    apply wf_asm_code_bounded; eauto.
  Qed.
  
  Fixpoint check_asm_body (f: function) (next_roj: bool) (r: code) : bool :=
    match r with
    | nil => negb next_roj
    | i :: r =>
      let roj := proj_sumbool (is_free_dec i) in
      check_asm_body f roj r && 
      if next_roj then check_ret_or_jmp i && valid_ret_or_jmp i
      else
        negb (check_ret_or_jmp i) &&
        match i with
        | Pfreeframe sz ora =>     (* after a free, ret or jmp *)
          check_free_dec f sz ora
        | Pallocframe _ _ => false (* no alloc in body *)
        | Pcall (inl r) sg => negb (preg_eq r RSP)
        | Pbuiltin _ args res => check_builtin_dec args res
        | _ => true
      end
    end.
  
  Definition wf_asm_function_check (f: function) : bool :=
    match fn_code f with
    | nil => false
    | a::r => is_make_palloc_dec a f && check_asm_body f false r
    end && zle (code_size (fn_code f)) Ptrofs.max_unsigned.

  Lemma check_asm_body_no_alloc:
    forall f c b i,
      check_asm_body f b c = true ->
      In i c ->
      ~ is_alloc i.
  Proof.
    induction c; simpl; intros. easy.
    intro IA. inv IA.
    assert (exists b, check_asm_body f b c = true).
    {
      eexists. refine (proj1 _); apply andb_true_iff; eauto.
    }
    destruct H1.
    destruct H0. subst. simpl in *.
    apply andb_true_iff in H. destruct H. destr_in H0.
    eapply IHc in H0; eauto. apply H0; constructor.
  Qed.
  
  Lemma find_instr_app:
    forall a o b,
      0 <= o ->
      find_instr (o + code_size a) (a ++ b) = find_instr o b.
  Proof.
    induction a; simpl; intros; eauto.
    f_equal. lia.
    rewrite pred_dec_false.
    rewrite <- (IHa o b). f_equal. lia. lia.
    generalize (instr_size_positive a) (code_size_non_neg a0). lia.
  Qed.

  Lemma find_instr_app':
    forall a o b,
      code_size a <= o ->
      find_instr o (a ++ b) = find_instr (o - code_size a) b.
  Proof.
    intros.
    rewrite <- (find_instr_app a _ b). f_equal. lia. lia.
  Qed.
  
  Lemma find_instr_split:
    forall c o i,
      find_instr o c = Some i ->
      exists a b, c = a ++ i :: b /\ o = code_size a.
  Proof.
    induction c; simpl; intros; eauto. congruence.
    destr_in H. inv H. eexists nil, c; simpl. split; auto.
    edestruct IHc as (aa & b & EQ & SZ). apply H. subst.
    exists (a::aa), b; simpl; split; auto. lia.
  Qed.

  Lemma code_size_app:
    forall c1 c2,
      code_size (c1 ++ c2) = code_size c1 + code_size c2.
  Proof.
    induction c1; simpl; intros; eauto. rewrite IHc1. lia.
  Qed.
  
  Lemma check_asm_body_after_free:
    forall f a i b roj,
      check_asm_body f roj (a ++ i :: b) = true ->
      is_free i ->
      check_asm_body f true b = true.
  Proof.
    induction a; simpl; intros; eauto.
    apply andb_true_iff in H. destruct H as (H & _).
    inv H0. simpl in *. auto.
    apply andb_true_iff in H. destruct H as (H & B).
    destruct (is_free_dec a); simpl in *. inv i0.
    eapply IHa; eauto.
    eapply IHa; eauto.
  Qed.


  Lemma check_asm_body_call:
    forall f c b r sg,
      check_asm_body f b c = true ->
      In (Pcall (inl r) sg) c ->
      r <> RSP.
  Proof.
    induction c; simpl; intros. easy.
    assert (exists b, check_asm_body f b c = true).
    {
      eexists. refine (proj1 _); apply andb_true_iff; eauto.
    }
    apply andb_true_iff in H. destruct H. destruct H1. destruct H0; eauto. subst. simpl in *.
    destr_in H2; simpl in *. 
    unfold proj_sumbool in H2; destr_in H2. simpl in H2. congruence.
  Qed.
  
  Lemma check_asm_body_free:
    forall f c b sz ora,
      check_asm_body f b c = true ->
      In (Pfreeframe sz ora) c ->
      check_free f sz ora.
  Proof.
    induction c; simpl; intros. easy.
    assert (exists b, check_asm_body f b c = true).
    {
      eexists. refine (proj1 _); apply andb_true_iff; eauto.
    }
    apply andb_true_iff in H. destruct H. destruct H1. destruct H0; eauto. subst. simpl in *.
    destr_in H2; simpl in *. 
    unfold proj_sumbool in H2; destr_in H2.
  Qed.
 
  Lemma check_asm_body_before_roj:
    forall f a i b roj,
      check_asm_body f roj (a ++ i :: b) = true ->
      i = Pret \/ is_jmp i ->
      (a = nil /\ roj = true) \/ exists a0 i0, a = a0 ++ i0 :: nil /\ is_free i0.
  Proof.
    induction a; simpl; intros; eauto.
    - apply andb_true_iff in H. destruct H as (A & B).
      destruct H0 as [ROJ|ROJ]; inv ROJ; simpl in *. destr_in B. destr_in B.
    - apply andb_true_iff in H. destruct H as (A & B).
      destruct (is_free_dec a); simpl in *. inv i0.
      + simpl in *. destr_in B. right.
        destruct a0. clear IHa. simpl in *.
        eexists nil, _. split. simpl. eauto. constructor.
        edestruct IHa as [ROJ|(a1 & i1 & EQ & IFR)]; eauto.
        destruct ROJ; congruence. rewrite EQ.
        eexists (_ :: a1), i1; split. simpl. reflexivity. auto.
      + edestruct IHa as [ROJ|(a1 & i1 & EQ & IFR)]; eauto.
        destruct ROJ; congruence. subst. right.
        eexists (_ :: a1), i1; split. simpl. reflexivity. auto.
  Qed.

  Lemma check_asm_body_builtin:
    forall f c b ef args res,
      check_asm_body f b c = true ->
      In (Pbuiltin ef args res) c ->
      check_builtin args res.
  Proof.
    induction c; simpl; intros. easy.
    assert (exists b, check_asm_body f b c = true).
    {
      eexists. refine (proj1 _); apply andb_true_iff; eauto.
    }
    destruct H1.
    destruct H0. subst. simpl in *.
    apply andb_true_iff in H. destruct H. destr_in H0.
    unfold proj_sumbool in H0; destr_in H0.
    eapply IHc in H0; eauto.
  Qed.


  Lemma check_asm_body_jmp:
    forall f c b r sg,
      check_asm_body f b c = true ->
      In (Pjmp (inl r) sg) c ->
      r <> RSP.
  Proof.
    induction c; simpl; intros. easy.
    assert (exists b, check_asm_body f b c = true).
    {
      eexists. refine (proj1 _); apply andb_true_iff; eauto.
    }
    apply andb_true_iff in H. destruct H. destruct H1. destruct H0; eauto. subst. simpl in *.
    destr_in H2; simpl in *. 
    unfold proj_sumbool in H2; destr_in H2. simpl in H2. congruence.
  Qed.
  
  Lemma wf_asm_function_check_correct f:
    wf_asm_function_check f = true ->
    wf_asm_function f.
  Proof.
    unfold wf_asm_function_check. destr. simpl. congruence.
    rewrite ! andb_true_iff. intros ((A & B) & C).
    unfold proj_sumbool in A, C. destr_in A; destr_in C.
    clear A C. rename Heqc into CODE. rename l into SIZE.
    constructor.
    - rewrite CODE. simpl. intros. destr_in H.
      apply find_instr_in in H.
      eapply check_asm_body_no_alloc in H; eauto. contradict H. constructor.
    - rewrite CODE; simpl. clear - i0. destruct i0 as (A & B). subst. reflexivity.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros. destr_in H. inv H. inv H0.
      simpl in SIZE.
      rewrite pred_dec_false.
      replace (Ptrofs.unsigned (Ptrofs.add o (Ptrofs.repr (instr_size i))) - instr_size (make_palloc f))
        with (Ptrofs.unsigned (Ptrofs.add (Ptrofs.repr (Ptrofs.unsigned o - instr_size (make_palloc f))) (Ptrofs.repr (instr_size i)))).
      revert H.
      generalize (Ptrofs.unsigned o - instr_size (make_palloc f)).
      intros. 
      edestruct find_instr_split as (a & b & EQ & SZ). apply H. subst.
      rewrite find_instr_app'.
      simpl. rewrite pred_dec_false.
      eapply check_asm_body_after_free in B; eauto.
      destruct b; simpl in B. congruence. simpl. rewrite pred_dec_true. eexists; split; eauto.
      apply andb_true_iff in B. destruct B as (B & CHK).
      unfold check_ret_or_jmp in CHK. apply andb_true_iff in CHK. destruct CHK as (CHK & _). destr_in CHK; try (right; constructor).
      unfold Ptrofs.add.
      rewrite (Ptrofs.unsigned_repr (code_size a)).
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i)).
      rewrite Ptrofs.unsigned_repr. lia.
      simpl in SIZE. rewrite code_size_app in SIZE. simpl in SIZE.
      generalize (code_size_non_neg a) (instr_size_positive i) (instr_size_positive i0) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      simpl in SIZE. rewrite code_size_app in SIZE. simpl in SIZE.
      generalize (code_size_non_neg a) (instr_size_positive i) (instr_size_positive i0) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      unfold Ptrofs.add.
      rewrite (Ptrofs.unsigned_repr (code_size a)).
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i)).
      rewrite Ptrofs.unsigned_repr. generalize (instr_size_positive i); lia.
      simpl in SIZE. rewrite code_size_app in SIZE. simpl in SIZE.
      generalize (code_size_non_neg a) (instr_size_positive i) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      simpl in SIZE. rewrite code_size_app in SIZE. simpl in SIZE.
      generalize (code_size_non_neg a) (instr_size_positive i) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      unfold Ptrofs.add.
      rewrite (Ptrofs.unsigned_repr (code_size a)).
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i)).
      rewrite Ptrofs.unsigned_repr. generalize (instr_size_positive i); lia.
      simpl in SIZE. rewrite code_size_app in SIZE. simpl in SIZE.
      generalize (code_size_non_neg a) (instr_size_positive i) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      simpl in SIZE. rewrite code_size_app in SIZE. simpl in SIZE.
      generalize (code_size_non_neg a) (instr_size_positive i) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      unfold Ptrofs.add.
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i)).
      rewrite (Ptrofs.unsigned_repr (Ptrofs.unsigned o - _)).
      rewrite ! Ptrofs.unsigned_repr. lia.
      generalize (find_instr_bound _ _ _ H) (find_instr_pos_positive _ _ _ H).
      generalize (instr_size_positive i)
                 (instr_size_positive (make_palloc f)). lia.
      generalize (find_instr_bound _ _ _ H) (find_instr_pos_positive _ _ _ H).
      generalize (instr_size_positive i)
                 (instr_size_positive (make_palloc f)). lia.
      generalize (find_instr_bound _ _ _ H) (find_instr_pos_positive _ _ _ H).
      generalize (instr_size_positive i)
                 (instr_size_positive (make_palloc f)). lia.
      unfold Ptrofs.add.
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i)).
      rewrite Ptrofs.unsigned_repr.
      generalize (Ptrofs.unsigned_range o) (instr_size_positive i); lia.
      generalize (find_instr_bound _ _ _ H) (find_instr_pos_positive _ _ _ H).
      generalize (instr_size_positive i)
                 (instr_size_positive (make_palloc f)). lia.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros i o FI ROJ.
      destr_in FI. inv FI. destruct ROJ as [ROJ|ROJ]; inv ROJ.
      edestruct find_instr_split as (a & b & EQ & SZ). apply FI. subst.
      destruct (check_asm_body_before_roj _ _ _ _ _ B ROJ) as [(NIL & ROJFALSE)|(a0 & i0 & EQ & IFR)]. congruence.
      subst.
      exists (Ptrofs.sub o (Ptrofs.repr (instr_size i0))), i0.
      rewrite pred_dec_false.
      replace (Ptrofs.unsigned (Ptrofs.sub o (Ptrofs.repr (instr_size i0))) - instr_size (make_palloc f)) 
        with (0 + code_size a0). rewrite app_ass.
      rewrite find_instr_app. simpl. split; auto. split. auto.
      unfold Ptrofs.sub. 
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i0)).
      rewrite Ptrofs.unsigned_repr. lia.
      generalize (find_instr_bound _ _ _ FI) (find_instr_pos_positive _ _ _ FI). intros.
      simpl in *. rewrite ! code_size_app in *. simpl in *.
      generalize (code_size_non_neg a0) (instr_size_positive i) (instr_size_positive i0) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      lia.
      unfold Ptrofs.sub. 
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i0)).
      rewrite Ptrofs.unsigned_repr.
      simpl in *. rewrite ! code_size_app in *. simpl in *. lia.
      generalize (find_instr_bound _ _ _ FI) (find_instr_pos_positive _ _ _ FI). intros.
      simpl in *. rewrite ! code_size_app in *. simpl in *.
      generalize (code_size_non_neg a0) (instr_size_positive i) (instr_size_positive i0) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      unfold Ptrofs.sub. 
      rewrite (Ptrofs.unsigned_repr _ (instr_size_repr i0)).
      rewrite Ptrofs.unsigned_repr.
      simpl in *. rewrite ! code_size_app in *. simpl in *.
      generalize (find_instr_bound _ _ _ FI) (find_instr_pos_positive _ _ _ FI). intros. 
      simpl in *. rewrite ! code_size_app in *. simpl in *.
      generalize (code_size_non_neg a0) (instr_size_positive i) (instr_size_positive i0) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
      generalize (find_instr_bound _ _ _ FI) (find_instr_pos_positive _ _ _ FI). intros. 
      simpl in *. rewrite ! code_size_app in *. simpl in *.
      generalize (code_size_non_neg a0) (instr_size_positive i) (instr_size_positive i0) (code_size_non_neg b)
                 (instr_size_positive (make_palloc f)). lia.
    - rewrite CODE; split; auto.
      generalize (code_size_non_neg (i::c)). lia.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros o ef args res FI.
      destr_in FI. inv FI.
      apply find_instr_in in FI.
      eapply check_asm_body_builtin in FI; eauto.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros o r sg FI.
      destr_in FI. inv FI.
      apply find_instr_in in FI.
      eapply check_asm_body_jmp in FI; eauto.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros o r sg FI.
      destr_in FI. inv FI.
      apply find_instr_in in FI.
      eapply check_asm_body_call in FI; eauto.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros o sz ora FI.
      destr_in FI. inv FI.
      apply find_instr_in in FI.
      edestruct check_asm_body_free as (A & BB & C); subst; eauto.
    - destruct i0 as (i0 & PA). subst. rewrite CODE. simpl.
      intros o sz ora FI.
      destr_in FI. inv FI; auto.
      apply find_instr_in in FI.
      eapply check_asm_body_no_alloc in FI; eauto. contradict FI; constructor.
    - destruct i0 as (i0 & _). subst. rewrite CODE. simpl.
      intros o sz ora FI.
      destr_in FI. inv FI.
      apply find_instr_in in FI.
      edestruct check_asm_body_free as (A & BB & C); subst; eauto.
  Qed.

  Lemma wf_asm_pc_repr:
    forall f (WF: wf_asm_function f) i o,
      find_instr (Ptrofs.unsigned o) (fn_code f) = Some i ->
      Ptrofs.unsigned (Ptrofs.add o (Ptrofs.repr (instr_size i))) = Ptrofs.unsigned o + instr_size i.
  Proof.
    intros; eapply wf_asm_pc_repr'; eauto. generalize (instr_size_positive i); lia.
  Qed.

  Lemma wf_asm_wf_allocframe:
    forall f (WF: wf_asm_function f) o sz ora
      (FI: find_instr o (fn_code f) = Some (Pallocframe sz ora)),
      make_palloc f = Pallocframe sz ora.
  Proof.
    intros.
    exploit wf_asm_alloc_only_at_beginning; eauto. intro; subst.
    erewrite wf_asm_alloc_at_beginning in FI; eauto. inv FI; auto.
  Qed.

End WFASM.

Section WITHGE.
  Variable ge : Genv.t UserAsm.fundef unit.

  Definition exec_instr f i rs (m: mem) :=
    let sz := Ptrofs.repr (UserAsm.instr_size i) in 
    match i with
    | Pallocframe size ofs_ra =>
      let sp := Val.offset_ptr (rs RSP) (Ptrofs.neg (Ptrofs.sub (Ptrofs.repr (align size 8)) (Ptrofs.repr (size_chunk Mptr)))) in
      Next (nextinstr (rs #RAX <- (Val.offset_ptr (rs RSP) (Ptrofs.repr (size_chunk Mptr))) #RSP <- sp) sz) m
    | Pfreeframe fsz ofs_ra =>
      let sp := Val.offset_ptr (rs RSP) (Ptrofs.sub (Ptrofs.repr (align (Z.max 0 fsz) 8)) (Ptrofs.repr (size_chunk Mptr))) in
      Next (nextinstr (rs#RSP <- sp) sz) m
    | Pload_parent_pointer rd z =>
      let sp := Val.offset_ptr (rs RSP) (Ptrofs.repr (align (Z.max 0 z) 8)) in
      Next (nextinstr (rs#rd <- sp) sz) m
    | Pcall ros sg =>
      let addr := eval_ros ge ros rs in
      let sp := Val.offset_ptr (rs RSP) (Ptrofs.neg (Ptrofs.repr (size_chunk Mptr))) in
      match Mem.storev Mptr m sp (Val.offset_ptr rs#PC sz) with
      | None => Stuck
      | Some m2 =>
        Next (rs#RA <- (Val.offset_ptr rs#PC sz)
                #PC <- addr
                #RSP <- sp) m2
      end
    | Pret =>
      match Mem.loadv Mptr m rs#RSP with
      | None => Stuck
      | Some ra =>
        let sp := Val.offset_ptr (rs RSP) (Ptrofs.repr (size_chunk Mptr)) in
        Next (rs #RSP <- sp
                 #PC <- ra
                 #RA <- Vundef) m
      end
    | _ => UserAsm.exec_instr (*NCC: *)(*nil*) ge f i rs m
    end.
  
  Inductive step  : state -> trace -> state -> Prop :=
  | exec_step_internal:
      forall b ofs f i rs m rs' m',
        rs PC = Vptr b ofs ->
        Genv.find_funct_ptr ge b = Some (Internal f) ->
        find_instr (Ptrofs.unsigned ofs) (fn_code f) = Some i ->
        exec_instr f i rs m = Next rs' m' ->
        step (State rs m) E0 (State rs' m')
  | exec_step_builtin:
      forall b ofs f ef args res rs m vargs t vres rs' m',
        rs PC = Vptr b ofs ->
        Genv.find_funct_ptr ge b = Some (Internal f) ->
        find_instr (Ptrofs.unsigned ofs) f.(fn_code) = Some (Pbuiltin ef args res) ->
        eval_builtin_args ge rs (rs RSP) m args vargs ->
        external_call ef ge vargs m t vres m' ->
          rs' = nextinstr_nf
                  (set_res res vres
                           (undef_regs (map preg_of (destroyed_by_builtin ef)) rs))
                  (Ptrofs.repr (UserAsm.instr_size (Pbuiltin ef args res))) ->
          step (State rs m) t (State rs' m')
  | exec_step_external:
      forall b ef args res rs m t rs' m',
        rs PC = Vptr b Ptrofs.zero ->
        Genv.find_funct_ptr ge b = Some (External ef) ->
        extcall_arguments (rs # RSP <- (Val.offset_ptr (rs RSP) (Ptrofs.repr (size_chunk Mptr)))) m (ef_sig ef) args ->
        forall (SP_TYPE: Val.has_type (rs RSP) Tptr)
          ra (LOADRA: Mem.loadv Mptr m (rs RSP) = Some ra)
          (SP_NOT_VUNDEF: rs RSP <> Vundef)
          (RA_NOT_VUNDEF: ra <> Vundef), 
          external_call ef ge args m t res m' ->
          rs' = (set_pair (loc_external_result (ef_sig ef)) res
                          (undef_regs (CR ZF :: CR CF :: CR PF :: CR SF :: CR OF :: nil)
                                      (undef_regs (map preg_of destroyed_at_call) rs)))
                  #PC <- ra
                  #RA <- Vundef
                  #RSP <- (Val.offset_ptr (rs RSP) (Ptrofs.repr (size_chunk Mptr))) ->
          step (State rs m) t (State rs' m').

End WITHGE.

  (* NCC: *)
  Inductive initial_state_gen (prog: UserAsm.program) (rs: regset) m: state -> Prop :=
  | initial_state_gen_intro:
      forall m1 bstack m2 m3 m4 bmain
        (MALLOC: Mem.alloc m 0 (max_stacksize + (align (size_chunk Mptr)8)) = (m1,bstack))
        (* (MALLOC: Mem.alloc (Mem.push_new_stage m) 0 (Mem.stack_limit + align (size_chunk Mptr) 8) = (m1,bstack)) *)
        (MDROP: Mem.drop_perm m1 bstack 0 (max_stacksize + (align (size_chunk Mptr) 8)) Writable = Some m2)
        (* (MDROP: Mem.drop_perm m1 bstack 0 (Mem.stack_limit + align (size_chunk Mptr) 8) Writable = Some m2) *)
        (MRSB: m2 = m3)
        (* (MRSB: Mem.record_stack_blocks m2 (make_singleton_frame_adt' bstack frame_info_mono 0) = Some m3) *)
        (STORE_RETADDR: Mem.storev Mptr m3 (Vptr bstack (Ptrofs.repr (max_stacksize + align (size_chunk Mptr) 8 - size_chunk Mptr))) Vnullptr = Some m4),
        (* (STORE_RETADDR: Mem.storev Mptr m3 (Vptr bstack (Ptrofs.repr (Mem.stack_limit + align (size_chunk Mptr) 8 - size_chunk Mptr))) Vnullptr = Some m4), *)
        let ge := Genv.globalenv prog in
        Genv.find_symbol ge prog.(prog_main) = Some bmain ->
        let rs0 :=
            rs #PC <- (Vptr bmain Ptrofs.zero)
               #RA <- Vnullptr
               #RSP <- (Val.offset_ptr (Vptr bstack (Ptrofs.repr (max_stacksize + align (size_chunk Mptr) 8))) (Ptrofs.neg (Ptrofs.repr (size_chunk Mptr)))) in
               (* #RSP <- (Val.offset_ptr (Vptr bstack (Ptrofs.repr (Mem.stack_limit + align (size_chunk Mptr) 8))) (Ptrofs.neg (Ptrofs.repr (size_chunk Mptr)))) in *)
        initial_state_gen prog rs m (State rs0 m4).

  Inductive initial_state (prog: UserAsm.program) (rs: regset) (s: state): Prop :=
  | initial_state_intro: forall m,
      Genv.init_mem prog = Some m ->
      initial_state_gen prog rs m s ->
      initial_state prog rs s.

  Ltac rewnb :=
  repeat
    match goal with
    | H: Mem.store _ _ _ _ _ = Some ?m |- context [Mem.nextblock ?m] =>
      rewrite (Mem.nextblock_store _ _ _ _ _ _ H)
    (* | H: Mem.storev _ _ _ _ = Some ?m |- context [Mem.nextblock ?m] => *)
    (*   rewrite (Mem.storev_nextblock _ _ _ _ _ H) *)
    | H: Mem.free _ _ _ _ = Some ?m |- context [Mem.nextblock ?m] =>
      rewrite (Mem.nextblock_free _ _ _ _ _ H)
    | H: Mem.drop_perm _ _ _ _ _ = Some ?m |- context [Mem.nextblock ?m] =>
      rewrite (Mem.nextblock_drop _ _ _ _ _ _ H)
    | H: Mem.alloc _ _ _ = (?m,_) |- context [Mem.nextblock ?m] =>
      rewrite (Mem.nextblock_alloc _ _ _ _ _ H)
    (* | H: Mem.record_stack_blocks _ _ = Some ?m |- context [Mem.nextblock ?m] => *)
    (*   rewrite (Mem.record_stack_block_nextblock _ _ _ H) *)
    (* | H: Mem.unrecord_stack_block _ = Some ?m |- context [Mem.nextblock ?m] => *)
    (*   rewrite (Mem.unrecord_stack_block_nextblock _ _ H) *)
    (* | |- context [ Mem.nextblock (Mem.push_new_stage ?m) ] => rewrite Mem.push_new_stage_nextblock *)
    (* | H: external_call _ _ _ ?m1 _ _ ?m2 |- Plt _ (Mem.nextblock ?m2) => *)
    (*   eapply Plt_Ple_trans; [ | apply external_call_nextblock in H; exact H ] *)
    (* | H: external_call _ _ _ ?m1 _ _ ?m2 |- Ple _ (Mem.nextblock ?m2) => *)
    (*   eapply Ple_trans; [ | apply external_call_nextblock in H; exact H ] *)
    (* | H: Genv.init_mem _ = Some ?m |- context [Mem.nextblock ?m] => *)
    (*   rewrite <- (Genv.init_mem_genv_next _ _ H) *)
    (* | H: Mem.tailcall_stage ?m1 = Some ?m2 |- context [ Mem.nextblock ?m2] => *)
    (*   rewrite (Mem.tailcall_stage_nextblock _ _ H) *)
    (* | H: Mem.record_init_sp ?m1 = Some ?m2 |- context [ Mem.nextblock ?m2] => *)
    (*   rewrite (Mem.record_init_sp_nextblock_eq _ _ H) *)
    end.

  Definition semantics_gen prog rs m :=
    Semantics step (initial_state_gen prog rs m) final_state (Genv.globalenv prog).

  Definition semantics prog rs :=
    Semantics step (initial_state prog rs) final_state (Genv.globalenv prog).

  Definition rs_state s :=
    let '(State rs _) := s in rs.
  Definition m_state s :=
    let '(State _ m) := s in m.

  Section INVARIANT.
    Variable prog: UserAsm.program.
    Let ge := Genv.globalenv prog.

    (* TODO: remove the workaround *)
    Variable prog_asm: Asm.program.
    Let ge_asm := Genv.globalenv prog_asm.
    Variable uasm_function : UserAsm.function -> Asm.function.
    Coercion uasm_function : UserAsm.function >-> Asm.function.
    Variable uasm_instruction : UserAsm.instruction -> Asm.instruction.
    Coercion uasm_instruction : UserAsm.instruction >-> Asm.instruction.
    Variable uasm_regset : UserAsm.regset -> Asm.regset.
    Coercion uasm_regset : UserAsm.regset >-> Asm.regset.
    Variable asm_outcome : Asm.outcome -> UserAsm.outcome.
    Coercion asm_outcome : Asm.outcome >-> UserAsm.outcome.

    Definition bstack := (* NCC: *) stkblock (*Genv.genv_next ge*).

    Definition rsp_ptr (s: state) : Prop :=
      exists o, rs_state s RSP = Vptr bstack o /\ (align_chunk Mptr | Ptrofs.unsigned o).

    Definition bstack_perm (s: state) : Prop :=
      forall o k p,
        Mem.perm (m_state s) bstack o k p ->
        Mem.perm (m_state s) bstack o k Writable.

    Definition stack_top_state (s: state) : Prop :=
      (* NCC: *) exists tl st, Mem.stack(Mem.support (m_state s))= Node None (1%positive::nil) tl st.
      (* is_stack_top (Mem.stack (m_state s)) bstack. *)

    Inductive real_asm_inv : state -> Prop := 
    | real_asm_inv_intro:
        forall s
          (RSPPTR: rsp_ptr s)
          (BSTACKPERM: bstack_perm s)
          (STOP: stack_top_state s),
          real_asm_inv s.

    Lemma real_initial_inv:
      forall rs0 is,
        initial_state prog rs0 is -> real_asm_inv is.
    Admitted.
    (*
    Proof.
      intros rs0 is IS; inv IS. inv H0.
      constructor.
      - red.
        simpl. unfold rs1. UserAsmFacts.simpl_regs. unfold Val.offset_ptr. (* simpl. (* TODO: explodes*) *)
        exploit Mem.alloc_result; eauto. rewnb.
        intro; subst.
        eexists; split; eauto.
        apply div_ptr_add.
        apply div_unsigned_repr.
        apply Z.divide_add_r. apply align_Mptr_stack_limit. apply align_Mptr_align8.
        apply align_Mptr_modulus. unfold Ptrofs.neg. apply div_unsigned_repr.
        apply Zdivide_opp_r.
        apply div_unsigned_repr.
        apply align_size_chunk_divides.
        apply align_Mptr_modulus.
        apply align_Mptr_modulus.
        apply align_Mptr_modulus.
      - exploit Mem.alloc_result; eauto. rewnb.
        fold ge. intro; subst.
        red. simpl. intros o k p. repeat rewrite_perms. unfold bstack. rewrite ! pred_dec_true by reflexivity.
        intros (A & B); split; auto. constructor.
      - red. simpl. repeat rewrite_stack_blocks.
        intros A. inv A. red; simpl. left.
        exploit Mem.alloc_result; eauto. rewnb.
        fold ge. unfold bstack. auto.
    Qed.
    *)

    Lemma exec_instr_invar_same:
      forall f i rs1 m1,
        (* (* NCC: *)stk_unrelated_instr i = true -> *)
        stack_invar i = true ->
        exec_instr ge f i rs1 m1 = (* NCC: *)SSAsm(*RawAsm*).exec_instr ge_asm f i rs1 m1.
    Admitted.
    (*
    Proof.
      intros f i rs1 m1 SI.
      destruct i; simpl in SI; simpl; congruence.
    Qed.
    *)

    Inductive is_load_parent_pointer: instruction -> Prop :=
    | ilpp_intro i z: is_load_parent_pointer (Pload_parent_pointer i z).

    Lemma is_load_parent_pointer_dec i: { is_load_parent_pointer i } + { ~ is_load_parent_pointer i }.
    Proof.
      destruct i; first [ now (right; inversion 1) | left; econstructor ].
    Defined.

    Lemma exec_instr_invar_same':
      forall f i rs1 m1 (*l*),
        (* (* NCC: *)stk_unrelated_instr i = true -> *)
        stack_invar i = true ->
        ~ is_load_parent_pointer i ->
        UserAsm.exec_instr (*l*) ge f i rs1 m1 = (* NCC: *)SSAsm(*RawAsm*).exec_instr ge_asm f i rs1 m1.
    Admitted.
    (*
    Proof.
      intros f i rs1 m1 (*l*) SI NILPP.
      destruct i; simpl in SI; simpl; try congruence.
      contradict NILPP. constructor.
    Qed.
    *)

    Lemma exec_instr_invar_inv:
      forall f i rs1 m1 rs2 m2,
        asm_instr_no_rsp i ->
        (* (* NCC: *)stk_unrelated_instr i = true -> *)
        stack_invar i = true ->
        exec_instr ge f i rs1 m1 = Next rs2 m2 ->
        real_asm_inv (State rs1 m1) ->
        real_asm_inv (State rs2 m2).
    Admitted.
    (*
    Proof.
      intros f i rs1 m1 rs2 m2 NORSP INVAR EI RAI; inv RAI.
      destruct (is_load_parent_pointer_dec i).
      - constructor.
        + red in RSPPTR; red.
          simpl in *.
          destruct RSPPTR as (o & EQ & AL).
          red in NORSP.
          inv i0. simpl in EI. inv EI.
          simpl_regs.
          setoid_rewrite Pregmap.gsspec. destr. inv e. rewrite EQ.
          simpl.
          eexists; split; eauto. apply div_ptr_add. auto. apply div_unsigned_repr.
          transitivity 8.
          unfold Mptr. destr; simpl. exists 1; lia. exists 2; lia.
          apply align_divides. lia.
          apply align_Mptr_modulus.
          apply align_Mptr_modulus.
          eauto.
        + red in BSTACKPERM; red. simpl in *. intros.
          inv i0; simpl in EI; inv EI. eauto.
        + red in STOP; red. simpl in *.
          inv i0; simpl in EI; inv EI. eauto.
      - erewrite exec_instr_invar_same in EI; eauto.
        erewrite <- exec_instr_invar_same' with (l:=nil) in EI; eauto.
        exploit NORSP; eauto. intro EQ.
        generalize (asmgen_no_change_stack i INVAR _ _ _ _ _ _ _ EI). intros (A & B).
        constructor.
        + red in RSPPTR; red. simpl in *; rewrite EQ. eauto.
        + red in BSTACKPERM; red. simpl in *. setoid_rewrite B. eauto.
        + red in STOP; red; simpl in *. rewrite A; eauto.
    Qed.
    *)

    Lemma align_Mptr_sub:
      forall o,
        (align_chunk Mptr | Ptrofs.unsigned o) ->
        (align_chunk Mptr | Ptrofs.unsigned (Ptrofs.add o (Ptrofs.neg (Ptrofs.repr (size_chunk Mptr))))).
    Proof.
      intros.
      apply div_ptr_add; auto.
      apply div_unsigned_repr.
      apply Z.divide_opp_r.
      apply div_unsigned_repr.
      apply align_size_chunk_divides.
      apply align_Mptr_modulus.
      apply align_Mptr_modulus.
      apply align_Mptr_modulus.
    Qed.

    Lemma align_Mptr_add:
      forall o,
        (align_chunk Mptr | Ptrofs.unsigned o) ->
        (align_chunk Mptr | Ptrofs.unsigned (Ptrofs.add o (Ptrofs.repr (size_chunk Mptr)))).
    Proof.
      intros.
      apply div_ptr_add; auto.
      apply div_unsigned_repr.
      apply align_size_chunk_divides.
      apply align_Mptr_modulus.
      apply align_Mptr_modulus.
    Qed.

    Lemma align_Mptr_add_gen:
      forall o d,
        (align_chunk Mptr | Ptrofs.unsigned o) ->
        (align_chunk Mptr | Ptrofs.unsigned d) ->
        (align_chunk Mptr | Ptrofs.unsigned (Ptrofs.add o d)).
    Proof.
      intros.
      apply div_ptr_add; auto.
      apply align_Mptr_modulus.
    Qed.

    Definition asm_prog_no_rsp (ge: Genv.t UserAsm.fundef unit):=
      forall b f,
        Genv.find_funct_ptr ge b = Some (Internal f) ->
        asm_code_no_rsp (fn_code f).

    Definition wf_asm_prog (ge: Genv.t UserAsm.fundef unit):=
      forall b f,
        Genv.find_funct_ptr ge b = Some (Internal f) ->
        wf_asm_function f.
    
    Lemma real_asm_inv_inv:
      forall (prog_no_rsp: asm_prog_no_rsp ge) (WF: wf_asm_prog ge) s1 t s2,
        step ge s1 t s2 ->
        real_asm_inv s1 ->
        real_asm_inv s2.
    Admitted.
    (*
    Proof.
      intros prog_no_rsp WF s1 t s2 STEP INV; inv STEP.
      - destruct (stk_unrelated_instr i) eqn:INVAR.
        eapply exec_instr_invar_inv; eauto.
        eapply prog_no_rsp; eauto. eapply find_instr_in; eauto.
        destruct i; simpl in INVAR; try congruence.
        + (* call_s *)
          simpl in H2. destr_in H2. inv H2. inv INV; constructor; simpl.
          * red. simpl. simpl_regs. destruct RSPPTR as (o & EQ & AL); simpl in *; rewrite EQ.
            simpl. eexists; split; eauto. apply align_Mptr_sub; auto.
          * red in BSTACKPERM; red; simpl in *.
            intros o k p. repeat rewrite_perms; eauto.
          * red in STOP; red; simpl in *. repeat rewrite_stack_blocks; eauto.
        + (* ret *)
          simpl in H2; repeat destr_in H2; inv INV; constructor; simpl.
          * red. simpl. simpl_regs. destruct RSPPTR as (o & EQ & AL); simpl in *; rewrite EQ.
            simpl. eexists; split; eauto. apply align_Mptr_add; auto.
          * red in BSTACKPERM; red; simpl in *.
            intros o k p. repeat rewrite_perms; eauto.
          * red in STOP; red; simpl in *. repeat rewrite_stack_blocks; eauto.
        + (* allocframe *)
          simpl in H2; repeat destr_in H2; inv INV; constructor; simpl.
          * red. simpl. simpl_regs. destruct RSPPTR as (o & EQ & AL); simpl in *; rewrite EQ.
            simpl. eexists; split; eauto. apply align_Mptr_add_gen; auto.
            unfold Ptrofs.neg. apply div_unsigned_repr; auto. apply Z.divide_opp_r.
            unfold Ptrofs.sub. apply div_unsigned_repr; auto.
            apply Z.divide_sub_r.
            apply div_unsigned_repr; auto.
            transitivity 8. unfold Mptr. destr; simpl. exists 1; lia. exists 2; lia. apply align_divides. lia.
            apply align_Mptr_modulus.
            apply div_unsigned_repr; auto.
            apply align_size_chunk_divides.
            apply align_Mptr_modulus.
            apply align_Mptr_modulus.
            apply align_Mptr_modulus.
          * red in BSTACKPERM; red; simpl in *.
            intros o k p. repeat rewrite_perms; eauto.
          * red in STOP; red; simpl in *. repeat rewrite_stack_blocks; eauto.
        + (* freeframe *)
          simpl in H2; repeat destr_in H2; inv INV; constructor; simpl.
          * red. simpl. simpl_regs. destruct RSPPTR as (o & EQ & AL); simpl in *; rewrite EQ.
            simpl. eexists; split; eauto. apply align_Mptr_add_gen; auto.
            unfold Ptrofs.sub. apply div_unsigned_repr; auto.
            apply Z.divide_sub_r.
            apply div_unsigned_repr; auto.
            transitivity 8. unfold Mptr. destr; simpl. exists 1; lia. exists 2; lia. apply align_divides. lia.
            apply align_Mptr_modulus.
            apply div_unsigned_repr; auto.
            apply align_size_chunk_divides.
            apply align_Mptr_modulus.
            apply align_Mptr_modulus.
          * red in BSTACKPERM; red; simpl in *.
            intros o k p. repeat rewrite_perms; eauto.
          * red in STOP; red; simpl in *. repeat rewrite_stack_blocks; eauto.
      - inv INV; constructor.
        + red in RSPPTR; red; simpl in *. unfold nextinstr_nf. repeat simpl_regs.
          rewrite Asmgenproof0.undef_regs_other.
          2: simpl; intuition subst; congruence.
          exploit wf_asm_builtin_not_PC; eauto.
          intros (NPC & NRSP & NRA).
          rewrite set_res_other; auto.
          rewrite Asmgenproof0.undef_regs_other.
          eauto. setoid_rewrite in_map_iff. intros r' (x & PREG & IN). subst.
          intro EQ. symmetry in EQ. apply preg_of_not_rsp in EQ. congruence.
        + red in BSTACKPERM; red. simpl in *. intros o k p.
          repeat rewrite_perms. eauto.
          red in STOP; simpl in STOP. eapply stack_top_in_stack; eauto.
          red in STOP; simpl in STOP. eapply stack_top_in_stack; eauto.
        + red in STOP; red; simpl in *. rewrite_stack_blocks. auto.
      - inv INV; constructor.
        + Opaque destroyed_at_call.
          red in RSPPTR; red; simpl in *. repeat simpl_regs.
          destruct RSPPTR as (o & EQ & AL); simpl in *; rewrite EQ.
          simpl. eexists; split; eauto. apply align_Mptr_add; auto.
        + red in BSTACKPERM; red. simpl in *. intros o k p.
          repeat rewrite_perms. eauto.
          red in STOP; simpl in STOP. eapply stack_top_in_stack; eauto.
          red in STOP; simpl in STOP. eapply stack_top_in_stack; eauto.
        + red in STOP; red; simpl in *. rewrite_stack_blocks. auto.        
    Qed.
    *)

End INVARIANT.

  Theorem real_asm_single_events p rs:
    single_events (semantics p rs).
  Proof.
    red. simpl. intros s t s' STEP.
    inv STEP; simpl. lia.
    eapply external_call_trace_length; eauto.
    eapply external_call_trace_length; eauto.
  Qed.

  Theorem real_asm_receptive p rs:
    receptive (semantics p rs).
  Proof.
    split.
    - simpl. intros s t1 s1 t2 STEP MT.
      inv STEP.
      inv MT. eexists. eapply exec_step_internal; eauto.
      edestruct external_call_receptive as (vres2 & m2 & EC2); eauto.
      eexists. eapply exec_step_builtin; eauto.
      edestruct external_call_receptive as (vres2 & m2 & EC2); eauto.
      eexists. eapply exec_step_external; eauto.
    - eapply real_asm_single_events; eauto.
  Qed.

  Theorem real_asm_determinate p rs:
    determinate (semantics p rs).
  Proof.
    split.
    - simpl; intros s t1 s1 t2 s2 STEP1 STEP2.
      inv STEP1.
      + inv STEP2; rewrite_hyps. split. constructor.  congruence.
        simpl in H2. inv H2.
      + inv STEP2; rewrite_hyps. inv H11.
        exploit eval_builtin_args_determ. apply H2. apply H9. intro; subst.
        exploit external_call_determ. apply H3. apply H10. intros (A & B); split; auto. intro C.
        destruct B; auto. congruence.
      + inv STEP2; rewrite_hyps.
        exploit extcall_arguments_determ. apply H1. apply H7. intro; subst.
        exploit external_call_determ. apply H2. apply H8. intros (A & B); split; auto. intro C.
        destruct B; auto. congruence.
    - apply real_asm_single_events.
    - simpl. intros s1 s2 IS1 IS2; inv IS1; inv IS2. rewrite_hyps.
      inv H0; inv H2. rewrite_hyps. unfold rs0, rs1, ge, ge0 in *. rewrite_hyps. congruence.
    - simpl. intros s r FS.
      red. intros t s' STEP.
      inv FS. inv STEP; rewrite_hyps.
    - simpl. intros s r1 r2 FS1 FS2.
      inv FS1; inv FS2. congruence.
  Qed.
  