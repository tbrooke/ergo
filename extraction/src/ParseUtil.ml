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

(* This module contains parsing utilities *)

open Util
open LexUtil

open JComp.JuraCompiler


(*****************)
(* Generic Parse *)
(*****************)

let parse parser lexer buf =
    try
      parser lexer buf
    with
    | LexError msg ->
	begin
	  let pos = buf.Lexing.lex_start_p in
	  let msg = Printf.sprintf "At line %d column %d: %s%!" pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol) msg in
	  raise (LexError msg)
	end
    | _ ->
	begin
	  let pos = buf.Lexing.lex_start_p in
	  let msg = Printf.sprintf "At line %d column %d: syntax error%!" pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol) in
	  raise (LexError msg)
	end

let parse_jura f : jura_package = parse JuraParser.main (JuraLexer.token (string_buff ())) f

let parse_sexp f : SExp.sexp = parse SExpParser.main (SExpLexer.token (string_buff ())) f
let parse_jurac_sexp f : jurac_package = AstsToSExp.sexp_to_jurac_package (parse_sexp f)
