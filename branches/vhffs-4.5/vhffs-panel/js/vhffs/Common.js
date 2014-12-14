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

dojo.provide('vhffs.Common');

dojo.require('dojo.back');

dojo.declare('vhffs.Common', null, {});

dojo.mixin(vhffs.Common, {
	handleHash: function() {
		var hash = window.location.hash;
                if(hash.charAt(0) == "#"){ hash = hash.substring(1); }
		if(!dojo.isMozilla) hash = decodeURIComponent(hash);
		if(hash.length) {
			document.location.href = hash;
		}
	},

	ajaxizeLinks: function(contentTarget, rootNode) {
		dojo.forEach(dojo.query('a.ajax', rootNode), function(link) {
			dojo.connect(link, 'onclick', function(e) {
				dojo.stopEvent(e);
				var href = dojo.attr(link, 'href');
				if(href != '#') {
					dojo.back.addToHistory(new vhffs.Common.pageState(href, contentTarget));
					dojo.xhrGet({
						url: href,
						load: function(response) {
							vhffs.Common.loadContent(contentTarget, response);
						}
					});
				}
			});
			// Avoid double ajaxization
			dojo.removeClass(link, 'ajax');
		});
	},

	showLoading: function() {
		var bodyCoords = dojo.coords(dojo.doc.body);
		dojo.style(dojo.byId('loading'), 
			{ display: 'block', top: (- bodyCoords.y + 10) + 'px', left: ((bodyCoords.w - 32) / 2) + 'px' });
	},

	hideLoading: function() {
		dojo.style(dojo.byId('loading'), { display: 'none' });
	},
	
	loadContent: function(contentTarget, xhrResponse) {
		var parsed = vhffs.Common.extractScripts(xhrResponse);
		contentTarget.innerHTML = parsed[0];
		dojo.eval(parsed[1]);
		vhffs.Common.ajaxizeLinks(contentTarget, contentTarget);
	},
	
	extractScripts: function(html) {
		var _t = this, code, byRef = {
			downloadRemote: true,
			errBack:function(e){
				_t._onError.call(_t, 'Exec', 'Error downloading remote script in "'+_t.id+'"', e);
			}
		};
		var cleanedHtml = vhffs.Common.snarfScripts(html, byRef);
		byRef.code = byRef.code.replace(/(<!--|(?:\/\/)?-->|<!\[CDATA\[|\]\]>)/g, '');
		return [cleanedHtml, byRef.code];
	},
	
	snarfScripts: function(cont, byRef){
		// summary
		//		strips out script tags from cont
		// invoke with 
		//	byRef = {errBack:function(){/*add your download error code here*/, downloadRemote: true(default false)}}
		//	byRef will have {code: 'jscode'} when this scope leaves
		byRef.code = "";

		function download(src){
			if(byRef.downloadRemote){
				// console.debug('downloading',src);
				dojo.xhrGet({
					url: src,
					sync: true,
					load: function(code){
						byRef.code += code+";";
					},
					error: byRef.errBack
				});
			}
		}
		
		// match <script>, <script type="text/..., but not <script type="dojo(/method)...
		return cont.replace(/<script\s*(?![^>]*type=['"]?dojo)(?:[^>]*?(?:src=(['"]?)([^>]*?)\1[^>]*)?)*>([\s\S]*?)<\/script>/gi,
			function(ignore, delim, src, code){
				if(src){
					download(src);
				}else{
					byRef.code += code;
				}
				return "";
			}
		);
	}
});

try {
	vhffs.Common.theme = dojo.query("meta[name=theme]")[0].content;
} catch(e) {
	vhffs.Common.theme = "light-grey";
}

// Back and forward handling with Ajax

dojo.declare('vhffs.Common.pageState', null, {
	changeUrl: true, 
	/**
	 * Creates a new pageState.
	 * url is the URL to load when this page is to
	 * be restored, target the container in which the
	 * content will be injected and postObject an optional
	 * object containing post data (request will be GET if
	 * it evaluates to false).
	 */
	constructor: function(url, target, postObject) {
		var prefix = new RegExp('^' + window.location.protocol + '//' + window.location.host);
		url = url.replace(prefix, '');
		this.url = url;
		this.target = target;
		this.postObject = postObject;
		this.changeUrl = url;
	},

	back: function() {
		this.loadUrl();
	},

	forward: function() {
		this.loadUrl();
	},

	loadUrl: function() {
		var href = this.url;
		var contentTarget = this.target;

		if(this.postObject) {
			var postContent = this.postObject;
			dojo.xhrPost({
				url: href,
				load: function(response) {
					vhffs.Common.loadContent(contentTarget, response);
				},
				content: postContent
			});
		} else {
			dojo.xhrGet({
				url: href,
				load: function(response) {
					vhffs.Common.loadContent(contentTarget, response);
				}
			});
		}
	}
});

dojo.addOnLoad(function() {
	var initState = new vhffs.Common.pageState(document.location.pathname, dojo.byId('public-content'));
	dojo.back.setInitialState(initState);
});

dojo.subscribe("/dojo/io/start", function() {
	vhffs.Common.showLoading();
});

dojo.subscribe("/dojo/io/stop", function() {
	vhffs.Common.hideLoading();
})

