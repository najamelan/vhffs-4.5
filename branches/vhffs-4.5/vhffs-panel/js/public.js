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
 * JS functions used in all the public part
 */

dojo.require('vhffs.Menu');
dojo.require('vhffs.Common');

dojo.addOnLoad(function() {
	vhffs.Common.handleHash();
	new vhffs.Menu(dojo.byId('left-menu'));
	vhffs.Common.ajaxizeLinks(dojo.byId('public-content'));
});

var Public = {};

Public.SearchGroup = {};

Public.SearchGroup.onLoad = function() {
	Public.SearchGroup.setUpTagsList();
	Public.SearchGroup.ajaxizeForm();
}

Public.SearchGroup.ajaxizeForm = function() {
	var form = dojo.byId('AdvancedSearchGroupForm');
	dojo.connect(form, 'onsubmit', function(e) {
		dojo.stopEvent(e);
		var url = dojo.attr(form, 'action');
		var content = dojo.formToObject(form);
		var container = dojo.byId('public-content');
		dojo.back.addToHistory(new vhffs.Common.pageState(url, container, content));
		dojo.xhrPost({
			'url': url,
			'content': content,
			load: function(response) {
				vhffs.Common.loadContent(container, response);
				vhffs.Common.ajaxizeLinks(container);
			}
		});
	});
}

/**
 * Adds the event listeners on +/- beside each tags.
 */
Public.SearchGroup.setUpTagsList = function() {
	dojo.forEach(dojo.query('#searchTagsList span'), function(el, index) {
		var id = dojo.attr(el, 'id');
		if(!id) return;
		
		// We're only interrested in tag container's spans
		if(/^tag\d+$/.test(id) == false) return;
		
		// Strips tag part (tag1 => 1)
		var tagId = id.substring(3);
		var include = dojo.query('a.include', el);
		if(include.length > 0) {
			include = include[0];
			dojo.connect(include, 'onclick', function(e) { dojo.stopEvent(e); Public.SearchGroup.includeTag(tagId); });
		}
		var exclude = dojo.query('a.exclude', el);
		if(exclude.length > 0) {
			exclude = exclude[0];
			dojo.connect(exclude, 'onclick', function(e) { dojo.stopEvent(e); Public.SearchGroup.excludeTag(tagId); });
		}
	});
}

/**
 * Adds a tag to the exclusion list. Put the tag in
 * the "Doesn't matches" section and add an hidden field
 * to reflect this.
 */
Public.SearchGroup.excludeTag = function(tagId) {
	Public.SearchGroup.addToList(tagId, 'searchTagExclude');
	Public.SearchGroup.addHiddenField('excluded_tags', tagId);
}

/**
 * Adds a tag to the inclusion list. Put the tag in
 * the "Matches" section and add an hidden field
 * to reflect this.
 */
Public.SearchGroup.includeTag = function(tagId) {
	Public.SearchGroup.addToList(tagId, 'searchTagInclude');
	Public.SearchGroup.addHiddenField('included_tags', tagId);
}

/**
 * Adds an hidden field to the search form to reflect tag's
 * inclusion/exclusion.
 * @param name Name of the hidden field (included_tags or
 * excluded_tags.
 * @param tagId The hidden field will have tagId as its value
 * and hidden[tagId] as its ID.
 */
Public.SearchGroup.addHiddenField = function(name, tagId) {
	var h = document.createElement('input');
	dojo.attr(h, {
		type: 'hidden',
		name: name,
		value: tagId,
		id: 'hidden' + tagId
	});
	dojo.place(h, 'AdvancedSearchGroupForm', 'first');
}

/**
 * Removes the hidden field including or excluding
 * 
 */
Public.SearchGroup.removeHiddenField = function(tagId) {
	var h = dojo.byId('hidden' + tagId);
	h.parentNode.removeChild(h);
}

Public.SearchGroup.removeTag = function(tagId, span) {
	span.parentNode.removeChild(span);
	Public.SearchGroup.removeHiddenField(tagId);
	dojo.style(dojo.byId('tag' + tagId), 'display', '');
}

Public.SearchGroup.addToList = function(tagId, list) {
	var tagContainer = dojo.byId('tag' + tagId);
	if(tagContainer == null) return;
	var list = dojo.byId(list);
	var label = dojo.query('span.label', tagContainer);
	if(label.length > 0) {
		label = dojo.string.trim(label[0].innerHTML);
	} else {
		label = dojo.string.trim(tagContainer.innerHTML);
	}
	var span = document.createElement('span');
	span.innerHTML = (label + ' ');
	var remove = document.createElement('a');
	dojo.attr(remove, 'href', '#');
	remove.innerHTML = '&#160;X';
	
	dojo.place(remove, span, 'last');
	// Don't use += ' ' since remove will be lost...
	dojo.place(document.createTextNode(' '), span, 'last');
	dojo.place(span, list, 'last');
	
	dojo.connect(remove, 'onclick', function(e) {
		dojo.stopEvent(e); Public.SearchGroup.removeTag(tagId, span);
	});
	
	dojo.style(tagContainer, 'display', 'none');
}

Public.SearchUser = {};

Public.SearchUser.onLoad = function() {
	Public.SearchUser.ajaxizeForm();
}

Public.SearchUser.ajaxizeForm = function() {
	var form = dojo.byId('SearchUserForm');
	dojo.connect(form, 'onsubmit', function(e) {
		dojo.stopEvent(e);
		var url = dojo.attr(form, 'action');
		var content = dojo.formToObject(form);
		var container = dojo.byId('public-content');
		dojo.back.addToHistory(new vhffs.Common.pageState(url, container, content));
		dojo.xhrPost({
			'url': url,
			'content': content,
			load: function(response) {
				vhffs.Common.loadContent(container, response);
				vhffs.Common.ajaxizeLinks(container);
			}
		});
	});
}
