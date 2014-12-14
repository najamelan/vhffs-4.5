# Vhffs::ObjectFactory - Fetches an object depending on his type.
# Copyright (c) vhffs project and its contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of vhffs nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

=head1 NAME

Vhffs::ObjectFactory - Factory for VHFFS Objects.

=head1 SYNOPSYS

This class can be used to fetch a full object without any knowledge of its
type. This way, we can use polymorphism.

=head1 METHODS

=cut

package Vhffs::ObjectFactory;

use strict;
use utf8;
use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::User;
use Vhffs::Group;
use Vhffs::Services;
use Vhffs::Object;

=head2 fetch_object

	my $obj = Vhffs::ObjectFactory::fetch_object($vhffs, $oid);

Returns the object whose oid is C<$oid>. Actually the returned entity is a
subclass of Vhffs::Object, allowing use of polymorphism (eg. calling get_label
will call the subcall get_label method).

=cut
sub fetch_object {
	my ($vhffs, $oid) = @_;
	my $obj = Vhffs::Object::get_by_oid($vhffs, $oid);
	return undef unless defined $obj;
	my $class = Vhffs::Functions::type_class_from_type_id($obj->get_type);
	$obj = $class->fill_object($obj) if defined $class;
	return $obj;
}

return 1;

__END__

=head1 AUTHORS

Sébastien Le Ray <beuss AT tuxfamily DOT org>
