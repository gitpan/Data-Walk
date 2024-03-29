#! /bin/false

# $Id: Walk.pm,v 1.15 2006/05/11 14:10:54 guido Exp $

# Traverse Perl data structures.
# Copyright (C) 2005-2006 Guido Flohr <guido@imperia.net>,
# all rights reserved.

# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU Library General Public License as published
# by the Free Software Foundation; either version 2, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.

# You should have received a copy of the GNU Library General Public
# License along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
# USA.

package Data::Walk;

use strict;
use 5.004;

require Exporter;

use vars qw ($VERSION @ISA @EXPORT);

$VERSION = '1.00';
@ISA = qw (Exporter);
@EXPORT = qw (walk walkdepth);

use vars qw ($container $type $seen $address $depth);

# Forward declarations.
sub walk;
sub walkdepth;
sub __walk;
sub __recurse;

sub walk {
    my ($options, @args) = @_;
   
    unless ('HASH' eq ref $options) {
	$options = { wanted => $options };
    }

    __walk ($options, @args);
}

sub walkdepth {
    my ($options, @args) = @_;

    unless ('HASH' eq ref $options) {
	$options = { wanted => $options };
    }

    $options->{bydepth} = 1;

    __walk ($options, @args);
}

sub __walk {
    my ($options, @args) = @_;

    $options->{seen} = {};
    $options->{copy} = 1 unless exists $options->{copy};

    foreach my $item (@args) {
    	local $depth;
	$depth = 0;
	__recurse $options, $item;
    }
    
    return 1;
}

sub __recurse {
    my ($options, $item) = @_;

    ++$depth;
    
    my @children;
    my $data_type;

    local ($address, $seen);
    undef $address;
    $seen = 0;
    my $ref = ref $item;

    if ($ref) {
	my $blessed = -1 != index $ref, '=';

	# Avoid fancy overloading stuff.
	bless $item if $blessed;
	$address = int $item;
	
	$seen = $options->{seen}->{$address}++;

	if (UNIVERSAL::isa ($item, 'HASH')) {
		$data_type = 'HASH';
	} elsif (UNIVERSAL::isa ($item, 'ARRAY')) {
		$data_type = 'ARRAY';
	} else {
		$data_type = '';
	}
	
	if ($data_type eq 'HASH' || $data_type eq 'ARRAY') {
	    if (('ARRAY' eq $data_type || 'HASH' eq $data_type)) {
		if ('ARRAY' eq $data_type) {
		    @children = @{$item};
		} else {
		    @children = %{$item};
		}
		
		if ($options->{copy}) {
		    if ('ARRAY' eq $data_type) {
			@children = $options->{preprocess} (@{$item}) 
			    if $options->{preprocess};
		    } else {
			@children = %{$item};
			@children = $options->{preprocess} (@children) 
			    if $options->{preprocess};
			@children = $options->{preprocess_hash} (@children) 
			    if $options->{preprocess_hash};
		    }
		} else {
		    $item = $options->{preprocess} ($item) 
			if $options->{preprocess};
		    $item = $options->{preprocess_hash} ($item) 
			if 'HASH' eq $data_type && $options->{preprocess_hash};
		    @children = 'HASH' eq $data_type ? %{$item} : @{$item};
		}
	    }
	}
    }

    unless ($options->{bydepth}) {
	$_ = $item;
	$options->{wanted}->($item);
    }

    local ($container, $type);
    $type = $data_type;
    $container = $item;

    if ($options->{follow} || !$seen) {
	foreach my $child (@children) {
	    __recurse $options, $child;
	}
    }

    if ($options->{bydepth}) {
	$_ = $item;
	$options->{wanted}->($item);
    }

    $options->{postprocess}->() if $options->{postprocess};

    --$depth;
    # void
}


1;

=head1 NAME

Data::Walk - Traverse Perl data structures

=head1 SYNOPSIS

 use Data::Walk;    
 walk \&wanted, @items_to_walk;

 use Data::Walk;    
 walkdepth \&wanted, @items_to_walk;
    
 use Data::Walk;    
 walk { wanted => \&process, follow => 1 }, $self;
    
=head1 DESCRIPTION

The above synopsis bears an amazing similarity to File::Find(3pm)
and this is not coincidental.

Data::Walk(3pm) is for data what File::Find(3pm) is for files.
You can use it for rolling your own serialization class, for displaying
Perl data structures, for deep copying or comparing, for recursive
deletion of data, or ...

If you are impatient and already familiar with File::Find(3pm),
you can skip the following documentation and proceed with 
L</"DIFFERENCES TO FILE::FIND">.

=head1 FUNCTIONS

The module exports two functions by default:

=over 4

=item B<walk>

  walk \&wanted, @items;
  walk \%options, @items;

As the name suggests, the function traverses the items in the order 
they are given.  For every object visited, it calls the &wanted 
subroutine.  See L</"THE WANTED FUNCTION"> for details.

=item B<walkdepth>

  walkdepth \&wanted, @items;
  walkdepth \%options, @items;

Works exactly like C<walk()> but it first descends deeper into
the structure, before visiting the nodes on the current level.
If you want to delete visited nodes, then C<walkdepth()> is probably
your friend.

=back

=head1 OPTIONS

The first argument to C<walk()> and C<walkdepth()> is either a 
code reference to your &wanted function, or a hash reference
describing the operations to be performed for each visited
node.

Here are the possible keys for the hash.

=over 4

=item B<wanted>

The value should be a code reference.  This code reference is
described in L</"THE WANTED FUNCTION"> below.

=item B<bydepth>

Visits nodes on the current level of recursion only B<after>
descending into subnotes.  The entry point C<walkdepth()> is
a shortcut for specifying C<{ bydepth =E<gt> 1 }>.

=item B<preprocess>

The value should be a code reference.  This code reference is used
to preprocess the current node $Data::Walk::container.  Your
preprocessing function is called before the loop that calls the
C<wanted()> function.  It is called with a list of member nodes
and is expected to return such a list.  The list will contain
all sub-nodes, regardless of the value of the option I<follow>!
The list is normally a shallow copy of the data contained in the original
structure.  You can therefore safely delete items in it, without
affecting the original data.  You can use the option I<copy>,
if you want to change that behavior.

The behavior is identical for regular arrays and hashes, so you 
probably want to coerce the list passed as an argument into a hash 
then.  The variable $Data::Walk::type will contain the string
"HASH" if the currently inspected node is a hash.

You can use the preprocessing function to sort the items 
contained or to filter out unwanted items.  The order is also preserved 
for hashes!

=item B<preprocess_hash>

The value should be a code reference.  The code is executed 
right after an eventual I<preprocess_hash> handler, but only
if the current container is a hash.  It is skipped for regular
arrays.

You will usually prefer a I<preprocess_hash> handler over a
I<preprocess> handler if you only want to sort hash keys.

=item B<postprocess>

The value should be a code reference.  It is invoked just before
leaving the currently visited node.  It is called in void context
with no arguments.  The variable $Data::Walk::container points
to the currently visited node.

=item B<follow>

Causes cyclic references to be followed.  Normally, the traversal
will not descend into nodes that have already been visited.  If
you set the option I<follow> to a truth value, you can change this
behavior.  Unless you take additional measures, this will always
imply an infinite loop!

Please note that the &wanted function is also called for nodes
that have already been visited!  The effect of I<follow> is to
suppress descending into subnodes.  

=item B<copy>

Normally, the &preprocess function is called with a shallow copy
of the data.  If you set the option I<copy> to a false value,
the &preprocess function is called with one single argument,
a reference to the original data structure.  In that case, you
also have to return a suitable reference.

Using this option will result in a slight performance win, and
can make it sometimes easier to manipulate the original data.

What is a shallow copy?  Think of a list containing references
to hashes:

    my @list = ({ foo => 'bar' }, { foo => 'baz' });
    my @shallow = @list;

After this, @shallow will contain a new list, but the items
stored in it are exactly identical to the ones stored in the
original.  In other words, @shallow occupies new memory, whereas
both lists contain references to the same memory for the list
members.

=back

All other options are silently ignored.

=head1 THE WANTED FUNCTION

The &wanted function does whatever verifications you want on each
item in the data structure.  Note that despite its name, the &wanted
function is a generic callback and does B<not> tell Data::Walk(3pm)
if an item is "wanted" or not.  In fact, its return value is
ignored.

The wanted function takes no arguments but rather does its work
through a collection of variables:

=over 4

=item B<$_>

The currently visited node.  Think "file" in terms of File::Find(3pm)!

=item B<$Data::Walk::container>

The node containing the currently visited node, either a reference to
a hash or an array.  Think "directory" in terms of File::Find(3pm)!

=item B<$Data::Walk::type>

The base type of the object that $Data::Walk::container
references.  This is either "ARRAY" or "HASH".

=item B<$Data::Walk::seen>

For  references, this will hold the number of times the currently
visited node has been visited I<before>.  The value is consequently
set to 0 not 1 on the first visit.  For non-references, the value
is undefined.

=item B<$Data::Walk::address>

For references, this will hold the memory address it points to.  It
can be used as a unique identifier for the current node.  For non-
references, the value is undefined.

=item B<$Data::Walk::depth>

The depth of the current recursion.

=back

These variables should not be modified.

=head1 DIFFERENCES TO FILE::FIND

The API of Data::Walk(3pm) tries to mimic the API of File::Find(3pm)
to a certain extent.  If you are already familiar with File::Find(3pm) 
you will find it very easy to use Data::Walk(3pm).  Even the
documentation for Data::Walk(3pm) is in parts similar or identcal
to that of File::Find(3pm).

=head2 Analogies

The equivalent of directories in File::Find(3pm) are the container
data types in Data::Walk(3pm).  Container data types are arrays
(aka lists) and associative arrays (aka hashes).  Files are equivalent
to scalars.  Wherever File::Find(3pm) passes lists of strings to functions,
Data::Walk(3pm) passes lists of variables.

=head2 Function Names

Instead of C<find()> and C<finddepth()>, Data::Walk(3pm) uses 
C<walk()> and C<walkdepth()>, like the smart reader 
has already guessed after reading the L</"SYNOPSIS">.

=head2 Variables

The variable $Data::Walk::container is vaguely equivalent to 
$File::Find::dir.  All other variables are specific to the 
corresponding module.

=head2 Wanted Function

Like its archetype from File::Find(3pm), the wanted function of
Data::Walk(3pm) is called with $_ set to the currently inspected
item.

=head2 Options

The option I<follow> has the effect that Data::Walk(3pm) also
descends into nodes it has already visited.  Unless you take
extra measures, this will lead to an infinite loop!

A number of options are not applicable to data traversion and
are ignored by Data::Walk(3pm).  Examples are I<follow_fast>,
I<follow_skip>, I<no_chdir>, I<untaint>, I<untaint_pattern>, and
I<untaint_skip>.  To give truth the honor, all unrecognized options
are skipped.

You may argue, that the options I<untaint> and friends would be
useful, too, allowing you to recursively untaint data structures.
But, hey, that is what Data::Walk(3pm) is all about.  It makes
it very easy for you to write that yourself.

=head1 EXAMPLES

Following are some recipies for common tasks.  

=head2 Recursive Untainting

    sub untaint { 
    	s/(.*)/$1/s unless ref $_;
    };
    walk \&untaint, $data;

See perlsec(1), if you don't understand why the untaint() function
untaints your data here.

=head2 Recurse To Maximum Depth

If you want to stop the recursion at a certain level, do it as follows:

    my $max_depth = 20;
    sub not_too_deep {
        if ($Data::Walk::depth > $max_depth) {
	    return ();
        } else {
	    return @_;
        }
    }
    sub do_something1 {
    	# Your code goes here.
    }
    walk { wanted => \&do_something, preprocess => \&not_too_deep };

=head1 BUGS

If you think you have spotted a bug, you can share it with others in the
bug tracking system at http://rt.cpan.org/NoAuth/Bugs.html?Dist=Data-Walk.

=head1 COPYING

Copyright (C) 2005-2006, Guido Flohr E<lt>guido@imperia.netE<gt>, all
rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Library General Public License as published
by the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.

You should have received a copy of the GNU Library General Public
License along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
USA.

=head1 SEE ALSO

Data::Dumper(3pm), Storable(3pm), File::Find(3pm), perl(1)

=cut

#Local Variables:
#mode: perl
#perl-indent-level: 4
#perl-continued-statement-offset: 4
#perl-continued-brace-offset: 0
#perl-brace-offset: -4
#perl-brace-imaginary-offset: 0
#perl-label-offset: -4
#cperl-indent-level: 4
#cperl-continued-statement-offset: 2
#tab-width: 8
#End:
