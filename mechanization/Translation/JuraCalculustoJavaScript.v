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
Require Import Qcert.Common.CommonRuntime.
Require Import Error.
Require Import JuraBase.
Require Import JuraCalculus.
Require Import Qcert.NNRC.NNRCRuntime.

Section JuraCalculustoJavaScript.
  Context {fruntime:foreign_runtime}.

  Section lookup_clause.
    (** Returns clause code *)
    Definition lookup_clause_from_clause (clname:string) (c:jurac_clause) : option jurac_clause :=
      if (string_dec clname c.(clause_name))
      then Some c
      else None.

    Definition clause_code_from_clause (c:option jurac_clause) : option nnrc :=
      match c with
      | None => None
      | Some c => Some c.(clause_code)
      end.
    
    Definition lookup_clause_code_from_clause (clname:string) (c:jurac_clause) : option nnrc :=
      clause_code_from_clause (lookup_clause_from_clause clname c).

    Definition lookup_clause_from_declaration (clname:string) (d:jurac_declaration) : option jurac_clause :=
      match d with
      | Clause c => lookup_clause_from_clause clname c
      end.

    Definition lookup_clause_from_declarations (clname:string) (dl:list jurac_declaration) : option jurac_clause :=
      List.fold_left
        (fun acc d =>
           match acc with
           | Some e => Some e
           | None => lookup_clause_from_declaration clname d
           end
        ) dl None.
    
    Definition lookup_contract_from_contract (coname:string) (c:jurac_contract) : option jurac_contract :=
      if (string_dec coname c.(contract_name))
      then Some c
      else None.

    Definition lookup_clause_from_contract
               (coname:string) (clname:string) (c:jurac_contract) : option jurac_clause :=
      match lookup_contract_from_contract coname c with
      | None => None
      | Some c =>
        lookup_clause_from_declarations clname c.(contract_declarations)
      end.

    Definition lookup_clause_from_package
               (coname:string) (clname:string) (p:jurac_package) : option jurac_clause :=
      lookup_clause_from_contract coname clname p.(package_contract).

    Definition lookup_error (coname:string) (clname:string) :=
      let msg := ("Clause " ++ clname ++ " in contract " ++ coname ++ " not found")%string in
      CompilationError msg.
    
    Definition lookup_clause_code_from_package
               (coname:string) (clname:string) (p:jurac_package) : jresult nnrc :=
      let clause := lookup_clause_from_contract coname clname p.(package_contract) in
      jresult_of_option (clause_code_from_clause clause) (lookup_error coname clname).
  End lookup_clause.

  Section translate.
    (* Basic modules *)
    Require Import Qcert.Common.CommonSystem.
    Require Import Qcert.Utils.OptimizerLogger.
    Require Import Qcert.NNRC.NNRCRuntime.
    Require Import Qcert.Translation.NNRCtoJavaScript.
    Require Import Qcert.Compiler.Driver.CompLang.

    (* Foreign Datatypes Support *)
    Require Import Qcert.Translation.ForeignToJavaScript.

    (* Context *)
    Context {ft:foreign_type}.
    Context {bm:brand_model}.
    Context {ftyping: foreign_typing}.
    Context {nnrc_logger:optimizer_logger string nnrc}.
    Context {ftojs:foreign_to_javascript}.
    Context {ftjson:foreign_to_JSON}.

    Local Open Scope string_scope.

    Definition javacsript_method_of_clause_code
               (eol:string) (quotel:string) (fname:string) (e:jurac_expr) : javascript :=
      let input_v := "constants" in
      nnrcToJSMethod input_v e 1 eol quotel (input_v::nil) fname.
    
    Definition javascript_function_of_clause_code (fname:string) (e:jurac_expr) : javascript :=
      lift_nnrc_core nnrc_to_js_top_with_name (nnrc_to_nnrc_core e) fname.

    Definition javascript_of_clause_code (fname:string) (e:jurac_expr) : javascript :=
      javascript_function_of_clause_code fname e.

    Definition function_name_of_contract_clause_name (coname:string) (clname:string) : string :=
      coname ++ "_" ++ clname.

    Definition javascript_of_clause (eol:string) (quotel:string) (coname:string) (c:jurac_clause) : javascript :=
      let fname := function_name_of_contract_clause_name coname c.(clause_name) in
      javacsript_method_of_clause_code eol quotel fname c.(clause_code).
    
    Definition javascript_of_declaration (eol:string) (quotel:string) (coname:string) (d:jurac_declaration) : javascript :=
      match d with
      | Clause c => javascript_of_clause eol quotel coname c
      end.

    Definition multi_append {A} separator (f:A -> string) (elems:list A) : string :=
      match elems with
      | nil => ""
      | e :: elems' =>
        (fold_left (fun acc e => acc ++ separator ++ (f e)) elems' (f e))%string
      end.

    Definition javascript_of_declaration_list (eol:string) (quotel:string) (coname:string) (dl:list declaration) : javascript :=
      multi_append eol (javascript_of_declaration eol quotel coname) dl.

    Definition javascript_of_contract (eol:string) (quotel:string) (c:jurac_contract) : javascript :=
      let coname := c.(contract_name) in
      "class " ++ coname ++ " {" ++ eol
               ++ (javascript_of_declaration_list eol quotel coname c.(contract_declarations)) ++ eol
               ++ "}" ++ eol.

    Definition preamble eol :=
      "" ++ "'use strict';" ++ eol
         ++ "/*eslint-disable no-unused-vars*/" ++ eol
         ++ "/*eslint-disable no-undef*/" ++ eol
         ++ "/*eslint-disable no-var*/" ++ eol
         ++ eol.

    Definition postamble eol :=
      "" ++ eol
         ++ "/*eslint-enable no-unused-vars*/" ++ eol
         ++ "/*eslint-enable no-undef*/" ++ eol
         ++ eol.
    
    Definition javascript_of_package (eol:string) (quotel:string) (c:jurac_package) : javascript :=
      (preamble eol) ++ eol
                     ++ (javascript_of_contract eol quotel c.(package_contract))
                     ++ (postamble eol).

    Definition javascript_of_package_top (c:jurac_package) : javascript :=
      javascript_of_package eol_newline quotel_double c.

    Definition javascript_of_clause_code_in_package
               (coname:string) (clname:string) (p:jurac_package) : jresult javascript :=
      let expr_opt := lookup_clause_code_from_package coname clname p in
      jlift (fun e =>
               let fname := function_name_of_contract_clause_name coname clname in
               javascript_of_clause_code fname e) expr_opt.

  End translate.
End JuraCalculustoJavaScript.
