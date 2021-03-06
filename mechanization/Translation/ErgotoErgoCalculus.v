(*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

(** Translates contract logic to calculus *)

Require Import String.
Require Import List.

Require Import Qcert.Utils.Utils.

Require Import Ergo.Common.Utils.JNames.
Require Import Ergo.Common.Utils.JResult.
Require Import Ergo.Common.Utils.JError.
Require Import Ergo.Backend.ForeignErgo.
Require Import Ergo.Ergo.Lang.ErgoBase.
Require Import Ergo.Ergo.Lang.Ergo.
Require Import Ergo.Ergo.Lang.ErgoSugar.
Require Import Ergo.ErgoCalculus.Lang.ErgoCalculus.
Require Import Ergo.ErgoCalculus.Lang.ErgoCalculusCall.
Require Import Ergo.Backend.ErgoBackend.

Section ErgotoJavaScript.

  Require Import Qcert.NNRC.NNRCRuntime.

  Section utils.
    Open Scope string.
    (** This *)
    Definition this_contract := "contract"%string. (* Contains all contract data and clause data *)
    Definition this_state := "state"%string. (* Contains state *)
    Definition current_time := "now"%string.

    (** New Array *)
    Definition new_array (el:list ergoc_expr) : ergoc_expr :=
      match el with
      | nil => NNRCConst (dcoll nil)
      | e1::erest =>
        fold_left (fun acc e => NNRCBinop OpBagUnion (NNRCUnop OpBag e) acc) erest (NNRCUnop OpBag e1)
      end.

    (** [new Concept{ field1: expr1, ... fieldn: exprn }] creates a record and brands it with the concept name *)
    Definition new_expr (brand:string) (struct_expr:ergoc_expr) : ergoc_expr :=
      NNRCUnop (OpBrand (brand :: nil)) struct_expr.

    Definition ergo_enforce_error : ergoc_expr :=
      NNRCConst enforce_error_content.
    
  End utils.

  Record context :=
    mkContext {
        context_current_contract : option string;
        context_current_clause : option string;
        context_table: lookup_table;
        context_namespace: option string;
        context_globals: list string;
        context_params: list string;
      }.

  Definition add_globals (ctxt:context) (params:list string) : context :=
    mkContext
      ctxt.(context_current_contract)
      ctxt.(context_current_clause)
      ctxt.(context_table)
      ctxt.(context_namespace)
      (List.app params ctxt.(context_globals))
      ctxt.(context_params).

  Definition add_params (ctxt:context) (params:list string) : context :=
    mkContext
      ctxt.(context_current_contract)
      ctxt.(context_current_clause)
      ctxt.(context_table)
      ctxt.(context_namespace)
      ctxt.(context_globals)
      (List.app params ctxt.(context_params)).

  Definition add_one_global (ctxt:context) (param:string) : context :=
    mkContext
      ctxt.(context_current_contract)
      ctxt.(context_current_clause)
      ctxt.(context_table)
      ctxt.(context_namespace)
      (List.cons param ctxt.(context_globals))
      ctxt.(context_params).

  Definition add_one_param (ctxt:context) (param:string) : context :=
    mkContext
      ctxt.(context_current_contract)
      ctxt.(context_current_clause)
      ctxt.(context_table)
      ctxt.(context_namespace)
      ctxt.(context_globals)
      (List.cons param ctxt.(context_params)).

  Definition add_one_func (ctxt:context) (fname:string) (fclosure:closure) : context :=
    mkContext
      ctxt.(context_current_contract)
      ctxt.(context_current_clause)
      (add_function_to_table ctxt.(context_table) fname fclosure)
      ctxt.(context_namespace)
      ctxt.(context_globals)
      ctxt.(context_params).

  Definition set_current_contract (ctxt:context) (cname:string) : context :=
    mkContext
      (Some cname)
      ctxt.(context_current_clause)
      ctxt.(context_table)
      ctxt.(context_namespace)
      ctxt.(context_globals)
      ctxt.(context_params).
  
  Definition set_current_clause (ctxt:context) (cname:string) : context :=
    mkContext
      ctxt.(context_current_contract)
      (Some cname)
      ctxt.(context_table)
      ctxt.(context_namespace)
      ctxt.(context_globals)
      ctxt.(context_params).
  
  Definition cmatch_cases :=
    list (match_case * ergoc_expr).

  Section fresh_vars.
    Require Import Qcert.Utils.Fresh.
    Definition fresh_in_match {A} (eccases:list (A * ergoc_expr)) (ecdefault:ergoc_expr) :=
      fresh_var
        "$match"
        (List.app
           (List.concat
              (List.map (fun eccase => nnrc_free_vars (snd eccase)) eccases))
           (nnrc_free_vars ecdefault)).
    Definition fresh_in_case (e:ergoc_expr) :=
      fresh_var "$case"
                (nnrc_free_vars e).
  End fresh_vars.

  (** Translate expressions to calculus *)
  Fixpoint ergo_expr_to_calculus
           (ctxt:context) (e:ergo_expr) : jresult ergoc_expr :=
    match e with
    | JThisContract =>
      match ctxt.(context_current_contract) with
      | None => not_in_contract_error
      | Some _ => jsuccess (NNRCGetConstant this_contract)
      end
    | JThisClause => 
      match ctxt.(context_current_clause) with
      | None => not_in_clause_error
      | Some cname => jsuccess (NNRCUnop (OpDot cname) (NNRCUnop OpUnbrand (NNRCGetConstant this_contract)))
      end
    | JThisState =>
      match ctxt.(context_current_contract) with
      | None => not_in_contract_error
      | Some _ => jsuccess (NNRCGetConstant this_state)
      end
    | JVar v =>
      if in_dec string_dec v ctxt.(context_params)
      then jsuccess (NNRCGetConstant v)
      else jsuccess (NNRCVar v)
    | JConst d =>
      jsuccess (NNRCConst d)
    | JArray el =>
      let init_el := jsuccess nil in
      let proc_one (acc:jresult (list ergoc_expr)) (e:ergo_expr) : jresult (list ergoc_expr) :=
          jlift2
            cons
            (ergo_expr_to_calculus ctxt e)
            acc
      in
      jlift new_array (fold_left proc_one el init_el)
    | JUnaryOp u e =>
      jlift (NNRCUnop u)
            (ergo_expr_to_calculus ctxt e)
    | JBinaryOp b e1 e2 =>
      jlift2 (NNRCBinop b)
             (ergo_expr_to_calculus ctxt e1)
             (ergo_expr_to_calculus ctxt e2)
    | JIf e1 e2 e3 =>
      jlift3 NNRCIf
        (ergo_expr_to_calculus ctxt e1)
        (ergo_expr_to_calculus ctxt e2)
        (ergo_expr_to_calculus ctxt e3)
    | JEnforce e1 None e3 =>
      jlift3 NNRCIf
        (jlift (NNRCUnop (OpNeg)) (ergo_expr_to_calculus ctxt e1))
        (jsuccess ergo_enforce_error)
        (ergo_expr_to_calculus ctxt e3)
    | JEnforce e1 (Some e2) e3 =>
      jlift3 NNRCIf
        (jlift (NNRCUnop (OpNeg)) (ergo_expr_to_calculus ctxt e1))
        (ergo_expr_to_calculus ctxt e3)
        (ergo_expr_to_calculus ctxt e2)
    | JLet v None e1 e2 =>
      jlift2 (NNRCLet v)
              (ergo_expr_to_calculus ctxt e1)
              (ergo_expr_to_calculus ctxt e2)
    | JLet v (Some t1) e1 e2 => (** XXX TYPE IS IGNORED AT THE MOMENT *)
      jlift2 (NNRCLet v)
              (ergo_expr_to_calculus ctxt e1)
              (ergo_expr_to_calculus ctxt e2)
    | JNew cr nil =>
      jsuccess
        (new_expr (brand_of_class_ref ctxt.(context_namespace) cr) (NNRCConst (drec nil)))
    | JNew cr ((s0,init)::rest) =>
      let init_rec : jresult nnrc :=
          jlift (NNRCUnop (OpRec s0)) (ergo_expr_to_calculus ctxt init)
      in
      let proc_one (acc:jresult nnrc) (att:string * ergo_expr) : jresult nnrc :=
          let attname := fst att in
          let e := ergo_expr_to_calculus ctxt (snd att) in
          jlift2 (NNRCBinop OpRecConcat)
                 (jlift (NNRCUnop (OpRec attname)) e) acc
      in
      jlift (new_expr (brand_of_class_ref ctxt.(context_namespace) cr)) (fold_left proc_one rest init_rec)
    | JRecord nil =>
      jsuccess
        (NNRCConst (drec nil))
    | JRecord ((s0,init)::rest) =>
      let init_rec : jresult nnrc :=
          jlift (NNRCUnop (OpRec s0)) (ergo_expr_to_calculus ctxt init)
      in
      let proc_one (acc:jresult nnrc) (att:string * ergo_expr) : jresult nnrc :=
          let attname := fst att in
          let e := ergo_expr_to_calculus ctxt (snd att) in
          jlift2 (NNRCBinop OpRecConcat)
                 (jlift (NNRCUnop (OpRec attname)) e) acc
      in
      fold_left proc_one rest init_rec
    | JThrow cr nil =>
      jsuccess (new_expr (brand_of_class_ref ctxt.(context_namespace) cr) (NNRCConst (drec nil)))
    | JThrow cr ((s0,init)::rest) =>
      let init_rec : jresult nnrc :=
          jlift (NNRCUnop (OpRec s0)) (ergo_expr_to_calculus ctxt init)
      in
      let proc_one (acc:jresult nnrc) (att:string * ergo_expr) : jresult nnrc :=
          let attname := fst att in
          let e := ergo_expr_to_calculus ctxt (snd att) in
          jlift2 (NNRCBinop OpRecConcat)
                 (jlift (NNRCUnop (OpRec attname)) e)
                 acc
      in
      jlift (new_expr (brand_of_class_ref ctxt.(context_namespace) cr)) (fold_left proc_one rest init_rec)
    | JFunCall fname el =>
      let init_el := jsuccess nil in
      let proc_one (e:ergo_expr) (acc:jresult (list ergoc_expr)) : jresult (list ergoc_expr) :=
          jlift2
            cons
            (ergo_expr_to_calculus ctxt e)
            acc
      in
      jolift (lookup_call ctxt.(context_table) fname) (fold_right proc_one init_el el)
    | JMatch e0 ecases edefault =>
      let ec0 := ergo_expr_to_calculus ctxt e0 in
      let eccases :=
          let proc_one acc ecase :=
              jolift
                (fun acc =>
                   jlift (fun x => (fst ecase, x)::acc)
                         (ergo_expr_to_calculus ctxt (snd ecase))) acc
          in
          fold_left proc_one ecases (jsuccess nil)
      in
      let ecdefault := ergo_expr_to_calculus ctxt edefault in
      jolift
        (fun ec0 =>
           jolift
             (fun eccases =>
                jolift
                  (fun ecdefault =>
                     let v0 := fresh_in_match eccases ecdefault in
                     let proc_one_case
                           (acc:jresult ergoc_expr)
                           (ecase:match_case * ergoc_expr)
                         : jresult ergoc_expr :=
                         match fst ecase with
                         | (Some v, CaseValue d) =>
                           jlift
                             (fun acc =>
                                NNRCIf (NNRCBinop OpEqual
                                                  (NNRCVar v0)
                                                  (NNRCConst d))
                                       (NNRCLet v
                                                (NNRCVar v0)
                                                (snd ecase))
                                       acc) acc
                         | (None, CaseValue d) =>
                           jlift
                             (fun acc =>
                                NNRCIf (NNRCBinop OpEqual
                                                  (NNRCVar v0)
                                                  (NNRCConst d))
                                       (snd ecase)
                                       acc) acc
                         | (Some v, CaseType brand) =>
                           jlift (fun acc =>
                                    let v2 := fresh_in_case acc in
                                    NNRCEither
                                      (NNRCUnop (OpCast (brand::nil)) (NNRCVar v0))
                                      v (snd ecase)
                                      v2 acc
                                 ) acc
                         | (None, CaseType brand) =>
                           jlift (fun acc =>
                                    let v1 := fresh_in_case (snd ecase) in
                                    let v2 := fresh_in_case acc in
                                    NNRCEither
                                      (NNRCUnop (OpCast (brand::nil)) (NNRCVar v0))
                                      v1 (snd ecase)
                                      v2 acc
                                 ) acc
                         end
                     in
                     let eccases_folded :=
                         fold_left proc_one_case eccases (jsuccess ecdefault)
                     in
                     jlift (NNRCLet v0 ec0) eccases_folded)
                  ecdefault) eccases) ec0
    | JFor v e1 None e2 =>
      jlift2 (NNRCFor v)
              (ergo_expr_to_calculus ctxt e1)
              (ergo_expr_to_calculus ctxt e2)
    | JFor v e1 (Some econd) e2 =>
      jlift3 (fun e1 econd e3 =>
                NNRCUnop OpFlatten
                         (NNRCFor v
                                  e1
                                  (NNRCIf econd
                                          (NNRCUnop OpBag e3)
                                          (NNRCConst (dcoll nil)))))
             (ergo_expr_to_calculus ctxt e1)
             (ergo_expr_to_calculus ctxt econd)
             (ergo_expr_to_calculus ctxt e2)
    end.

  (** Translate a clause to clause+calculus *)
  Definition clause_to_calculus
             (ctxt:context) (c:ergo_clause) : jresult ergoc_clause :=
    let ctxt : context :=
        set_current_clause ctxt c.(clause_name)
    in
    let ctxt : context :=
        add_params
          ctxt
          (List.map fst c.(clause_closure).(closure_params))
    in
    jlift
      (mkClause
         c.(clause_name))
      (jlift
         (mkClosure
            c.(clause_closure).(closure_params)
            c.(clause_closure).(closure_output)
            c.(clause_closure).(closure_throw))
         (ergo_expr_to_calculus ctxt c.(clause_closure).(closure_body))).

  (** Translate a function to function+calculus *)
  Definition func_to_calculus
             (ctxt:context) (f:ergo_func) : jresult ergoc_func :=
    let ctxt :=
        add_params ctxt (List.map fst f.(func_closure).(closure_params))
    in
    jlift
      (mkFunc
         f.(func_name))
      (jlift
         (mkClosure
            f.(func_closure).(closure_params)
            f.(func_closure).(closure_output)
            f.(func_closure).(closure_throw))
         (ergo_expr_to_calculus ctxt f.(func_closure).(closure_body))).

  (** Translate a declaration to a declaration+calculus *)
  Definition declaration_to_calculus
             (ctxt:context) (d:ergo_declaration) : jresult (context * ergoc_declaration) :=
    match d with
    | Clause c =>
      jlift
        (fun x => (add_one_func ctxt x.(clause_name) x.(clause_closure), Clause x)) (* Add new function to context *)
        (clause_to_calculus ctxt c)
    | Func f =>
      jlift
        (fun x => (add_one_func ctxt x.(func_name) x.(func_closure), Func x)) (* Add new function to context *)
        (func_to_calculus ctxt f)
    end.

  (** Translate a contract to a contract+calculus *)
  (** For a contract, add 'contract' and 'now' to the context *)
  Definition contract_to_calculus
             (ctxt:context) (c:ergo_contract) : jresult (context * ergoc_contract) :=
    let ctxt :=
        set_current_contract ctxt c.(contract_name)
    in
    let ctxt : context :=
        add_params
          ctxt
          (current_time :: this_contract :: this_state :: nil)
    in
    let init := jsuccess (ctxt, nil) in
    let proc_one
          (acc:jresult (context * list ergoc_declaration))
          (s:ergo_declaration)
        : jresult (context * list ergoc_declaration) :=
        jolift
          (fun acc : context * list ergoc_declaration =>
             let (ctxt,acc) := acc in
             jlift (fun xy : context * ergoc_declaration =>
                      let (newctxt,news) := xy in
                      (newctxt,news::acc))
                   (declaration_to_calculus ctxt s))
          acc
    in
    jlift
      (fun xy =>
         (fst xy,
          (mkContract
             c.(contract_name)
             c.(contract_template)
             (snd xy))))
      (List.fold_left proc_one c.(contract_declarations) init).

  (** Translate a statement to a statement+calculus *)
  Definition stmt_to_calculus
             (ctxt:context) (s:ergo_stmt) : jresult (context * ergoc_stmt) :=
    match s with
    | JType cto_type => jsuccess (ctxt, JType cto_type) (* XXX TO BE REVISED -- add type to context *)
    | JExpr e =>
      jlift
        (fun x => (ctxt, JExpr x))
        (ergo_expr_to_calculus ctxt e)
    | JGlobal v e =>
      jlift
        (fun x => (add_one_global ctxt v, JGlobal v x)) (* Add new variable to context *)
        (ergo_expr_to_calculus ctxt e)
    | JImport s =>
      jsuccess (ctxt, JImport s)
    | JFunc f =>
      jlift
        (fun x => (add_one_func ctxt x.(func_name) x.(func_closure), JFunc x)) (* Add new function to context *)
        (func_to_calculus ctxt f)
    | JContract c =>
      jlift (fun xy => (fst xy, JContract (snd xy)))
            (contract_to_calculus ctxt c)
    end.

  Definition initial_context (p:option string) :=
    mkContext None None ergoc_stdlib p nil nil.

  (** Translate a package to a package+calculus *)
  Definition package_to_calculus (p:package) : jresult ergoc_package :=
    let local_namespace := p.(package_namespace) in
    let ctxt := initial_context local_namespace in
    let init := jsuccess (ctxt, nil) in
    let proc_one
          (acc:jresult (context * list ergoc_stmt))
          (s:ergo_stmt)
        : jresult (context * list ergoc_stmt) :=
        jolift
          (fun acc : context * list ergoc_stmt =>
             let (ctxt,acc) := acc in
             jlift (fun xy : context * ergoc_stmt =>
                      let (newctxt,news) := xy in
                      (newctxt,news::acc))
                   (stmt_to_calculus ctxt s))
          acc
    in
    jlift
      (fun xy =>
         (mkPackage
            p.(package_namespace)
            (snd xy)))
      (List.fold_left proc_one p.(package_statements) init).

  Section tests.
    Open Scope string.
    Definition ctxt0 := initial_context None.

    Definition input1 := dnat 2.
    
    Example j1 :=
      JMatch (JConst input1)
              (((Some "v1", CaseValue (dnat 1)), (JConst (dstring "1")))
                 :: ((Some "v2", CaseValue (dnat 2)), (JConst (dstring "2")))
                 :: nil)
              (JConst (dstring "lots")).
    Definition jc1 := ergo_expr_to_calculus ctxt0 j1.
    (* Eval vm_compute in jc1. *)
    (* Eval vm_compute in jlift (fun x => nnrc_eval_top nil x nil) jc1. *)

    Example j1' :=
      JMatch (JConst input1)
              (((Some "v1", CaseValue (dnat 1)), (JConst (dstring "1")))
                 :: ((Some "v2", CaseValue (dnat 2)), JVar "v2")
                 :: nil)
              (JConst (dstring "lots")).
    Definition jc1' := ergo_expr_to_calculus ctxt0 j1'.
    (* Eval vm_compute in jc1'. *)
    (* Eval vm_compute in jlift (fun x => nnrc_eval_top nil x nil) jc1'. *)

    Definition input2 :=
      dbrand ("C1"::nil) (dnat 1).
    
    Example j2 :=
      JMatch (JConst input2)
              (((Some "v1", CaseType "C1"), (JConst (dstring "1")))
                 :: ((Some "v2", CaseType "C2"), (JConst (dstring "2")))
                 :: nil)
              (JConst (dstring "lots")).

    Definition jc2 := ergo_expr_to_calculus ctxt0 j2.
    (* Eval vm_compute in jc2. *)
    (* Eval vm_compute in jlift (fun x => nnrc_eval_top nil x nil) jc2. *)

  End tests.
  
End ErgotoJavaScript.

