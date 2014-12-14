mirrordir=@BACKENDDIR@

nobase_dist_mirror_SCRIPTS = mirror/mx1-mirror.pl \
						mirror/mx2-mirror.pl \
						mirror/mydns-mirror.pl \
						mirror/nss-mirror.pl

nobase_dist_mirror_DATA = 	mirror/mx1-mirror.sql \
						mirror/mx2-mirror.sql \
						mirror/mydns-mirror.sql

do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g'

install-data-hook:
	@for f in $(nobase_dist_mirror_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(mirrordir)/$$f; \
	done

backenddir=@BACKENDDIR@
backend_DATA=pgsql/initdb.sql
