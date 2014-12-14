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
  * Class handling the left menu.
  * Accordion style, without effect (since it can be
  * slow on some machine depending on the video hardware/driver).
  */
dojo.provide('vhffs.Menu');

dojo.declare('vhffs.Menu', null, {
	constructor: function(container, expandedIndex) {
		
		this.titles = dojo.query('h2', container);
		this.items = dojo.query('div.menu', container);
		
		if(!expandedIndex) expandedIndex = 0;
		
		dojo.forEach(this.items, function(submenu, index) {
			dojo.style(submenu, 'display', 'none');
		}, this);
		
		dojo.forEach(this.titles, function(title) {
			dojo.connect(title, 'onclick', this, this.toggleSubmenu);
		}, this); 
	},
	
	toggleSubmenu: function(e) {
		dojo.stopEvent(e);
		var title = e.currentTarget;
		
		dojo.forEach(this.titles, function(t, i) {
			if(t == title) {
				dojo.style(this.items[i], 'display', '');
			} else {
				dojo.style(this.items[i], 'display', 'none');
			}
		}, this);
	}
});
