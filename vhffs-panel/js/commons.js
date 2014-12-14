/*
 *  Copyright (c) vhffs project and its contributors
 *  All rights reserved.
 * 
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 * 
 *  1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 * 3. Neither the name of vhffs nor the names of its contributors
 *    may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 *  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 *  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * Generic field check function. Use checkFunction to validate
 * field whose id is id content.
 *
 * If checkFunction returns true, field parentNode class is set
 * to 'validField' else it's set to 'invalidField'.
 *
 * Beware that it is *parentNode* class which is set. It allow
 * style to use a ':after' pseudo-class even if it's an input
 * field. Enclose field in a span to hava something easy to manage.
 * 
 * @param id string Id of the field to check.
 * @param checkFunction function(value). Function which returns
 *        true if value is considered as correct, false else.
 * @param extra any An optional extra parameter to pass to checkFunction.
 */

function check(id, checkFunction, extra) {
    if(! checkFunction($F(id), extra)) {
        $(id).parentNode.setAttribute('class', 'invalidField');
    } else {
        $(id).parentNode.setAttribute('class', 'validField');
    }
    // Avoid strange bug in firefox
    $(id).focus();
}

/*
 * Function to pass to 'check' to ensure that the field contains
 * a valid identifier (lower case letters and numbers, minimum
 * 3 letters, max can be defined through the extra argument of
 * check).
 * @param value string Value to check.
 * @param max integer Optional max length for the value.
 * @return true if the value is correct, false else.
 */
function validIdentifier(value, max) {
    var r = new RegExp('^[a-z0-9]{3,' + max + '}$');
    return r.test(value);
}

/**
 * Function to pass to 'check' to ensure that the field contains
 * a valid email address (the regex could be improved).
 * @param value string Value to check.
 */
function validEmail(value) {
    return /^[_a-z0-9-]+(\.[_a-z0-9-]+)*@[a-z0-9-]+(\.[a-z0-9-]+)*(\.[a-z]{2,10})$/.test(value);
}

/**
 * Function to check that a string is harmless (no tag
 * injection).
 * @param value string Value to check.
 */
function validString(value) {
    return /^[^<>"]+$/.test(value);
}

/**
 * Function to pass to 'check' to validate Zip code
 */
function validZip(value) {
    return /^[\w\d\s\-]+$/.test(value);
}

function decode_mail(crypted) {
    var clear = '';
    for(var i = 0 ; i < crypted.length ; ++i) {
        clear += String.fromCharCode(crypted.charCodeAt(i) - 1);
    }
    return clear;
}

/**
 * Toggles visibility of element whose id is id.
 * @param id string Id of element to toggle.
 */
function toggle(id) {
    var el = $(id);
    if(!el) return;
    if(el.style.display == 'none') {
        el.style.display = '';
    } else {
        el.style.display = 'none';
    }
}

