/* 
 * falseshell is a non-shell for VHFFS which simply display a message and exit. 
 *
 * Copyright (C) 2007 Samuel Lesueur <crafty@tuxfamily.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <stdio.h>
#include <stdlib.h>

int main (void){
	printf("\nThis is a disabled shell account.\n\n"
 		"You can enable login for this account on the panel by selecting an\n"
		"appropriate shell in the user preferences section.\n\n");
	return 1;
}
