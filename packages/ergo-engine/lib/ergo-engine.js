/*
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
 */

'use strict';

const Ergo=require('@accordproject/ergo-compiler/lib/ergo');
const Fs = require('fs');
const Path = require('path');
const Moment = require('moment');

const {
    VM
} = require('vm2');

/**
 * Utility class that implements the internals for Ergo.
 * @class
 */
class ErgoEngine {
    /**
     * Execute Ergo
     *
     * @param {string} ergoText text for Ergo code
     * @param {string} ctoTexts texts for CTO models
     * @param {object} contractJson the contract data in JSON
     * @param {object} requestJson the request transaction in JSON
     * @param {object} stateJson the state in JSON
     * @param {string} contractName of the contract to execute
     * @param {string} clauseName of the clause to execute
     * @param {bool} withDispatch whether to generate dispatch function
     * @returns {object} Promise to the result of execution
     */
    static execute(ergoText,ctoTexts,contractJson,requestJson,stateJson,contractName,clauseName,withDispatch) {
        const ergoRuntime = Fs.readFileSync(Path.join(__dirname,'ergoruntime.js'), 'utf8');

        const vm = new VM({
            timeout: 1000,
            sandbox: { moment: Moment }
        });

        return (Ergo.compile(ergoText,ctoTexts,null,null,withDispatch)).then((ergoCode) => {
            // add immutables to the context
            const params = { 'contract': contractJson, 'request': requestJson, 'state': stateJson, 'now': Moment() };
            vm.freeze(params, 'params'); // Add the context
            vm.run(ergoRuntime); // Load the runtime
            vm.run(ergoCode); // Load the generated logic
            const contract = 'let contract = new ' + contractName+ '();'; // Instantiate the contract
            const functionName = 'contract.' + clauseName;
            const clauseCall = functionName+'(params);'; // Create the clause call
            const res = vm.run(contract + clauseCall); // Call the logic
            return res;
        });
    }
}

module.exports = ErgoEngine;
