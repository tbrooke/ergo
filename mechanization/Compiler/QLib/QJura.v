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

Require Import Qcert.Compiler.Model.CompilerRuntime.
Require String.
Require QOperators.
Require QData.
Require Qcert.Compiler.QLib.QLang.
Require Error.
Require Jura.
Require JuraCalculus.
Require JuraCalculusCall.
Require JuraSugar.
Require JuratoJuraCalculus.
Require JuratoJavaScript.
Require Import JuraModel.

Module QJura(juramodel:JuraCompilerModel).

  Module Data := QData.QData(juramodel).
  Module Ops := QOperators.QOperators(juramodel).

  Definition jura_package : Set 
    := Jura.jura_package.
  Definition jura_contract : Set
    := Jura.jura_contract.
  Definition jura_declaration : Set
    := Jura.jura_declaration.
  Definition jura_clause : Set
    := Jura.jura_clause.
  Definition jura_expr : Set 
    := Jura.jura_expr.
  
  Definition jurac_package : Set 
    := JuraCalculus.jurac_package.
  Definition jurac_contract : Set
    := JuraCalculus.jurac_contract.
  Definition jurac_declaration : Set
    := JuraCalculus.jurac_declaration.
  Definition jurac_clause : Set
    := JuraCalculus.jurac_clause.
  Definition jurac_expr : Set 
    := JuraCalculus.jurac_expr.
  
  Definition jvar : String.string -> jura_expr
    := Jura.JVar.

  Definition jconst := Jura.JConst.
  Definition jarray := Jura.JArray.
  Definition junaryop : Ops.Unary.op -> jura_expr -> jura_expr
    := Jura.JUnaryOp.
  Definition jbinaryop : Ops.Binary.op -> jura_expr -> jura_expr -> jura_expr 
    := Jura.JBinaryOp.
  Definition jif : jura_expr -> jura_expr -> jura_expr -> jura_expr 
    := Jura.JIf.
  Definition jguard : jura_expr -> jura_expr -> jura_expr -> jura_expr 
    := Jura.JGuard.
  Definition jlet : String.string -> jura_expr -> jura_expr -> jura_expr
    := Jura.JLet.
  Definition jfuncall : String.string -> list jura_expr -> jura_expr
    := Jura.JFunCall.

  Definition jdot : String.string -> jura_expr -> jura_expr 
    := JuraSugar.JDot.
  Definition jreturn : jura_expr -> jura_expr
    := JuraSugar.JReturn.
  Definition jnew : option String.string -> String.string -> list (String.string * jura_expr) -> jura_expr 
    := JuraSugar.JNewSugar.
  Definition jthrow : option String.string -> String.string -> list (String.string * jura_expr) -> jura_expr 
    := JuraSugar.JThrowSugar.
  Definition jthis : jura_expr
    := JuraSugar.JThis.

  (* XX For now, fix stdlib at top-level here *)
  Definition jstdlib : JuraCalculusCall.lookup_table
    := JuratoJuraCalculus.stdlib.
  
  Definition clause_calculus_from_jura_package :
    String.string -> String.string -> jura_package -> Error.jresult NNRC.nnrc
    := JuratoJavaScript.clause_calculus_from_package jstdlib.

  Definition clause_code_from_jura_package :
    String.string -> String.string -> jura_package -> Error.jresult JavaScript.javascript
    := JuratoJavaScript.clause_code_from_package jstdlib.

  Definition jura_calculus_package_from_jura_package :
    jura_package -> Error.jresult jurac_package
    := JuratoJuraCalculus.package_to_calculus jstdlib.

  Definition clause_code_from_jurac_package :
    String.string -> String.string -> jurac_package -> Error.jresult JavaScript.javascript
    := JuraCalculustoJavaScript.javascript_of_clause_code_in_package.

  Definition javascript_from_jurac_package :
    jurac_package -> JavaScript.javascript
    := JuraCalculustoJavaScript.javascript_of_package_top.

  Definition javascript_from_jura_package :
    jura_package -> Error.jresult JavaScript.javascript
    := JuratoJavaScript.javascript_from_package jstdlib.

End QJura.
