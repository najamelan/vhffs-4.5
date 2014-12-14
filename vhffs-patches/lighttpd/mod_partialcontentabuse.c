/*
 * Copyright (c) 2008-2009 Sylvain Rochet (gradator at gradator dot net)
 */

/*
 * Returns a 403 forbidden if the same client requests the same path multiple
 * times.
 * Put this in src/ subdirectory of lighttpd and patch the Makefile.
 */
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "base.h"
#include "log.h"
#include "buffer.h"

#include "plugin.h"

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

INIT_FUNC(mod_partialcontentabuse_init) {
	return malloc(1);
}

FREE_FUNC(mod_partialcontentabuse_free) {

	UNUSED(srv);
	if(p_d) free(p_d);
	return HANDLER_GO_ON;
}

SETDEFAULTS_FUNC(mod_partialcontentabuse_set_defaults) {

	UNUSED(srv);
	UNUSED(p_d);
	return HANDLER_GO_ON;
}

URIHANDLER_FUNC(mod_partialcontentabuse_uri_handler) {
	size_t i;

	UNUSED(srv);
	UNUSED(p_d);

	if (con->uri.path->used == 0) return HANDLER_GO_ON;
	if ( !con->request.http_range ) return HANDLER_GO_ON;

	for (i = 0; i < srv->conns->used; i++) {
		connection *c = srv->conns->ptr[i];

		if ( c != con && c->dst_addr.ipv4.sin_addr.s_addr == con->dst_addr.ipv4.sin_addr.s_addr && c->state > CON_STATE_REQUEST_END
		  && c->uri.path->used > 0 && !strcmp( c->uri.path->ptr , con->uri.path->ptr) )  {
			con->http_status = 403;
			return HANDLER_FINISHED;
		}
	}

	return HANDLER_GO_ON;
}

int mod_partialcontentabuse_plugin_init(plugin *p) {
	p->version     = LIGHTTPD_VERSION_ID;
	p->name        = buffer_init_string("partialcontentabuse");

	p->init        = mod_partialcontentabuse_init;
	p->handle_uri_clean  = mod_partialcontentabuse_uri_handler;
	p->set_defaults  = mod_partialcontentabuse_set_defaults;
	p->cleanup     = mod_partialcontentabuse_free;

	p->data        = NULL;

	return 0;
}
