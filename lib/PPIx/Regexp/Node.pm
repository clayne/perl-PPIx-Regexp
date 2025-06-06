=head1 NAME

PPIx::Regexp::Node - Represent a container

=head1 SYNOPSIS

 use PPIx::Regexp::Dumper;
 PPIx::Regexp::Dumper->new( 'qr{(foo)}' )->print();

=head1 INHERITANCE

C<PPIx::Regexp::Node> is a
L<PPIx::Regexp::Element|PPIx::Regexp::Element>.

C<PPIx::Regexp::Node> is the parent of L<PPIx::Regexp|PPIx::Regexp>,
L<PPIx::Regexp::Node::Range|PPIx::Regexp::Node::Range> and
L<PPIx::Regexp::Structure|PPIx::Regexp::Structure>.

=head1 DESCRIPTION

This class represents a structural element that contains other classes.
It is an abstract class, not instantiated by the lexer.

=head1 METHODS

This class provides the following public methods. Methods not documented
here are private, and unsupported in the sense that the author reserves
the right to change or remove them without notice.

=cut

package PPIx::Regexp::Node;

use strict;
use warnings;

use base qw{ PPIx::Regexp::Element };

use Carp;
use List::Util qw{ max min };
use PPIx::Regexp::Constant qw{
    CODE_REF
    FALSE
    INFINITY
    MINIMUM_PERL
    NODE_UNKNOWN
    TRUE
    @CARP_NOT
};
use PPIx::Regexp::Util qw{ __instance __merge_perl_requirements width };
use Scalar::Util qw{ refaddr };

our $VERSION = '0.089';

use constant ELEMENT_UNKNOWN	=> NODE_UNKNOWN;

sub __new {
    my ( $class, @children ) = @_;
    foreach my $elem ( @children ) {
	__instance( $elem, 'PPIx::Regexp::Element' ) or return;
    }
    my $self = {
	children => \@children,
    };
    bless $self, ref $class || $class;
    foreach my $elem ( @children ) {
	$elem->_parent( $self );
    }
    return $self;
}

=head2 child

 my $kid = $node->child( 0 );

This method returns the child at the given index. The indices start from
zero, and negative indices are from the end of the list, so that
C<< $node->child( -1 ) >> returns the last child of the node.

=cut

sub child {
    my ( $self, $inx ) = @_;
    defined $inx or $inx = 0;
    return $self->{children}[$inx];
}

=head2 children

This method returns the children of the Node. If called in scalar
context it returns the number of children.

=cut

sub children {
    my ( $self ) = @_;
    return @{ $self->{children} };
}

=head2 contains

 print $node->contains( $elem ) ? "yes\n" : "no\n";

This method returns true if the given element is contained in the node,
or false otherwise.

=cut

sub contains {
    my ( $self, $elem ) = @_;
    __instance( $elem, 'PPIx::Regexp::Element' ) or return;

    my $addr = refaddr( $self );

    while ( $elem = $elem->parent() ) {
	$addr == refaddr( $elem ) and return 1;
    }

    return;
}

sub content {
    my ( $self ) = @_;
    return join( '', map{ $_->content() } $self->elements() );
}

=head2 elements

This method returns the elements in the Node. For a
C<PPIx::Regexp::Node> proper, it is the same as C<children()>.

=cut

{
    no warnings qw{ once };
    *elements = \&children;	# sub slements
}

=head2 find

 my $rslt = $node->find( 'PPIx::Regexp::Token::Literal' );
 my $rslt = $node->find( 'Token::Literal' );
 my $rslt = $node->find( sub {
     return $_[1]->isa( 'PPIx::Regexp::Token::Literal' )
	 && $_[1]->ordinal < ord(' ');
     } );

This method finds things.

If given a string as argument, it is assumed to be a class name
(possibly without the leading 'PPIx::Regexp::'), and all elements of the
given class are found.

If given a code reference, that code reference is called once for each
element, and passed C<$self> and the element. The code should return
true to accept the element, false to reject it, and ( for subclasses of
C<PPIx::Regexp::Node>) C<undef> to prevent recursion into the node. If
the code throws an exception, you get nothing back from this method.

Either way, the return is a reference to the list of things found, a
false (but defined) value if nothing was found, or C<undef> if an error
occurred.

=cut

sub _find_routine {
    my ( $want ) = @_;
    CODE_REF eq ref $want
	and return $want;
    ref $want and return;
    $want =~ m/ \A PPIx::Regexp:: /smx
	or $want = 'PPIx::Regexp::' . $want;
    return sub {
	return __instance( $_[1], $want ) ? 1 : 0;
    };
}

sub find {
    my ( $self, $want ) = @_;

    $want = _find_routine( $want ) or return;

    my @found;

    # We use a recursion to find what we want. PPI::Node uses an
    # iteration.
    foreach my $elem ( $self->elements() ) {
	my $rslt = eval { $want->( $self, $elem ) }
	    and push @found, $elem;
	$@ and return;

	__instance( $elem, 'PPIx::Regexp::Node' ) or next;
	defined $rslt or next;
	$rslt = $elem->find( $want )
	    and push @found, @{ $rslt };
    }

    return @found ? \@found : 0;

}

=head2 find_parents

 my $rslt = $node->find_parents( sub {
     return $_[1]->isa( 'PPIx::Regexp::Token::Operator' )
         && $_[1]->content() eq '|';
     } );

This convenience method takes the same arguments as C<find>, but instead
of the found objects themselves returns their parents. No parent will
appear more than once in the output.

This method returns a reference to the array of parents if any were
found. If no parents were found the return is false but defined. If an
error occurred the return is C<undef>.

=cut

sub find_parents {
    my ( $self, $want ) = @_;

    my $found;
    $found = $self->find( $want ) or return $found;

    my %parents;
    my @rslt;
    foreach my $elem ( @{ $found } ) {
	my $dad = $elem->parent() or next;
	$parents{ refaddr( $dad ) }++
	    or push @rslt, $dad;
    }

    return \@rslt;
}

=head2 find_first

This method has the same arguments as L</find>, but returns either a
reference to the first element found, a false (but defined) value if no
elements were found, or C<undef> if an error occurred.

=cut

sub find_first {
    my ( $self, $want ) = @_;

    $want = _find_routine( $want ) or return;

    # We use a recursion to find what we want. PPI::Node uses an
    # iteration.
    foreach my $elem ( $self->elements() ) {
	my $rslt = eval { $want->( $self, $elem ) }
	    and return $elem;
	$@ and return;

	__instance( $elem, 'PPIx::Regexp::Node' ) or next;
	defined $rslt or next;

	defined( $rslt = $elem->find_first( $want ) )
	    or return;
	$rslt and return $rslt;
    }

    return 0;

}

=head2 first_element

This method returns the first element in the node.

=cut

sub first_element {
    my ( $self ) = @_;
    return $self->{children}[0];
}

=head2 first_token

This method returns the first token in the node. If there is none, it
returns nothing.

=cut

sub first_token {
    my ( $self ) = @_;
    my $elem = $self->first_element()
	or return;
    my $token;
    while ( ! ( $token = $elem->first_token() ) ) {
	$elem = $elem->next_element()
	    or return;
    }
    return $token;
}

=head2 last_element

This method returns the last element in the node.

=cut

sub last_element {
    my ( $self ) = @_;
    return $self->{children}[-1];
}

=head2 last_token

This method returns the last token in the node. If there is none, it
returns nothing.

=cut

sub last_token {
    my ( $self ) = @_;
    my $elem = $self->last_element()
	or return;
    my $token;
    while ( ! ( $token = $elem->last_token() ) ) {
	$elem = $elem->previous_element()
	    or return;
    }
    return $token;
}

sub location {
    my ( $self ) = @_;
    my $token = $self->first_token()
	or return undef;	## no critic (ProhibitExplicitReturnUndef)
    return $token->location();
}

=head2 is_matcher

This method returns a true value if any of the node's children does.
Otherwise it returns C<undef> if any of the node's children does.
Otherwise it returns a false (but defined) value.

=cut

sub is_matcher {
    my ( $self ) = @_;
    my $rslt = 0;
    foreach my $kid ( @{ $self->{children} } ) {
	my $kid_rslt = $kid->is_matcher()
	    and return 1;
	defined $kid_rslt
	    or $rslt = $kid_rslt;
    }
    return $rslt;
}

=head2 perl_version_introduced

This method returns the maximum value of C<perl_version_introduced>
returned by any of its elements. In other words, it returns the minimum
version of Perl under which this node is valid. If there are no
elements, 5.000 is returned, since that is the minimum value of Perl
supported by this package.

=cut

sub perl_version_introduced {
    my ( $self ) = @_;
    return max( grep { defined $_ } MINIMUM_PERL,
	$self->{perl_version_introduced},
	map { $_->perl_version_introduced() } $self->elements() );
}

=head2 perl_version_removed

This method returns the minimum defined value of C<perl_version_removed>
returned by any of the node's elements. In other words, it returns the
lowest version of Perl in which this node is C<not> valid. If there are
no elements, or if no element has a defined C<perl_version_removed>,
C<undef> is returned.

=cut

sub perl_version_removed {
    my ( $self ) = @_;
    my $max;
    foreach my $elem ( $self->elements() ) {
	if ( defined ( my $ver = $elem->perl_version_removed() ) ) {
	    if ( defined $max ) {
		$ver < $max and $max = $ver;
	    } else {
		$max = $ver;
	    }
	}
    }
    return $max;
}

sub remove_insignificant {
    my ( $self ) = @_;
    return $self->__new( map { $_->remove_insignificant() }
	$self->children() );
}

=head2 schild

This method returns the significant child at the given index; that is,
C<< $node->schild(0) >> returns the first significant child,
C<< $node->schild(1) >> returns the second significant child, and so on.
Negative indices count from the end.

=cut

sub schild {
    my ( $self, $inx ) = @_;
    defined $inx or $inx = 0;

    my $kids = $self->{children};

    if ( $inx >= 0 ) {

	my $loc = 0;

	while ( exists $kids->[$loc] ) {
	    $kids->[$loc]->significant() or next;
	    --$inx >= 0 and next;
	    return $kids->[$loc];
	} continue {
	    $loc++;
	}

    } else {

	my $loc = -1;
	
	while ( exists $kids->[$loc] ) {
	    $kids->[$loc]->significant() or next;
	    $inx++ < -1 and next;
	    return $kids->[$loc];
	} continue {
	    --$loc;
	}

    }

    return;
}

=head2 schildren

This method returns the significant children of the Node. If called in
scalar context it returns the number of significant children.

=cut

sub schildren {
    my ( $self ) = @_;
    if ( wantarray ) {
	return ( grep { $_->significant() } @{ $self->{children} } );
    } elsif ( defined wantarray ) {
	my $kids = 0;
	foreach ( @{ $self->{children} } ) {
	    $_->significant() and $kids++;
	}
	return $kids;
    } else {
	return;
    }
}

sub scontent {
    my ( $self ) = @_;
    # As of the invention of this method all nodes are significant, so
    # the following statement is pure paranoia on my part. -- TRW
    $self->significant()
	or return;
    # This needs to be elements(), not children() or schildren() -- or
    # selements() if that is ever invented. Not children() or
    # schildren() because those ignore the delimiters. Not selements()
    # (if that ever comes to pass) because scontent() has to make the
    # significance check, so selements() would be wasted effort.
    return join( '', map{ $_->scontent() } $self->elements() );
}

sub tokens {
    my ( $self ) = @_;
    return ( map { $_->tokens() } $self->elements() );
}

sub unescaped_content {
    my ( $self ) = @_;
    return join '', map { $_->unescaped_content() } $self->elements();
}

use constant ALTERNATION	=> q<|>;

{
    my $obj;
    sub _alternation_object {
	unless ( $obj ) {

=begin comment

	    # This is a pain because PPIx::Regexp::Token requires a
	    # tokenizer object.
	    require PPIx::Regexp::Tokenizer;
	    require PPIx::Regexp::Token::Operator;
	    $obj = PPIx::Regexp::Token::Operator->__new(
		ALTERNATION,
		tokenizer	=> PPIx::Regexp::Tokenizer->new( ALTERNATION ),
	    );

=end comment

=cut

	    # DANGER WILL ROBINSON!
	    # This is a horrible encapsulation violation, which I get
	    # away with because I am using the object as a sentinel.

	    $obj = bless {
		content	=> ALTERNATION,
	    }, 'PPIx::Regexp::Token::Operator';
	}
	return $obj;
    }
}

sub raw_width {
    my ( $self ) = @_;
    return ( $self->__raw_width() )[ 0, 1 ];
}

# PRIVATE TO THIS PACKAGE.
# This is the machinery for raw_width(), but because the datum is needed
# internally it also returns the number of alternatives found.
sub __raw_width {
    my ( $self ) = @_;
    my ( $node_min, $node_max ) = ( INFINITY, 0 );
    my ( $raw_min, $raw_max ) = ( 0, 0 );
    my $alternatives = 0;
    foreach my $elem ( $self->elements(), _alternation_object() ) {
	if ( $elem->isa( 'PPIx::Regexp::Token::Operator' ) &&
	    $elem->content() eq ALTERNATION
	) {
	    $alternatives++;
	    defined $node_min
		and $node_min = defined $raw_min ?
		    min( $node_min, $raw_min ) :
		    undef;
	    $raw_min = 0;
	    defined $node_max
		and $node_max = defined $raw_max ?
		    max( $node_max, $raw_max ) :
		    undef;
	    $raw_max = 0;
	} else {
	    my ( $e_min, $e_max ) = $elem->width();
	    defined $raw_min
		and $raw_min = defined $e_min ? $raw_min + $e_min : undef;
	    defined $raw_max
		and $raw_max = defined $e_max ? $raw_max + $e_max : undef;
	}
    }
    return ( $node_min, $node_max, $alternatives );
}

# Help for nav();
sub __nav {
    my ( $self, $child ) = @_;
    refaddr( $child->parent() ) == refaddr( $self )
	or return;
    my ( $method, $inx ) = $child->__my_nav()
	or return;

    return ( $method => [ $inx ] );
}

sub __error {
    my ( $self, $msg, %arg ) = @_;
    defined $msg
	or $msg = 'Was class ' . ref $self;
    $self->ELEMENT_UNKNOWN()->__PPIX_ELEM__rebless( $self, error => $msg );
    foreach my $key ( keys %arg ) {
	$self->{$key} = $arg{$key};
    }
    return 1;
}

sub __perl_requirements {
    my ( $self ) = @_;
    unless ( $self->{perl_requirements} ) {
	my @req = $self->__perl_requirements_setup();
	foreach my $kid ( $self->children() ) {
	    push @req, $kid->__perl_requirements();
	}
	$self->{perl_requirements} = [ __merge_perl_requirements( @req ) ];
    }
    return @{ $self->{perl_requirements} };
}

sub _token_order {
    my ( $self ) = @_;
    my $order = 0;
    delete $self->{_token_order};
    foreach my $elem ( $self->tokens() ) {
	$self->{_token_order}{ refaddr $elem } = $order++;
    }
    return;
}

# Order two elements according to the position of their last tokens. The
# elements must both be descendants of the invocant or an exception is
# thrown. The return is equivalent to the space ship operator (<=>).
#
# For the moment at least this is private to the PPIx-Regexp package.
# It is needed by the width() functionality to (try to) determine which
# capture group a back reference refers to.
sub __token_post_order {
    my ( $self, $left, $right ) = @_;
    $self->{_token_order}
	or $self->_token_order();
    my @order;
    foreach ( $left, $right ) {
	ref $_
	    or confess 'Bug - Operand must be a PPIx::Regexp::Element';
	defined( my $inx = $self->{_token_order}{ refaddr( $_->last_token() ) } )
	    or confess 'Bug - Operand not descendant of invocant';
	push @order, $inx;
    }
    return $order[0] <=> $order[1];
}

# Called by the lexer once it has done its worst to all the tokens.
# Called as a method with the lexer as argument. The return is the
# number of parse failures discovered when finalizing.
sub __PPIX_LEXER__finalize {
    my ( $self, $lexer ) = @_;
    my $rslt = 0;
    foreach my $elem ( $self->elements() ) {
	$rslt += $elem->__PPIX_LEXER__finalize( $lexer );
    }
    return $rslt;
}

# Called by the lexer to record the capture number.
sub __PPIX_LEXER__record_capture_number {
    my ( $self, $number ) = @_;
    foreach my $kid ( $self->children() ) {
	$number = $kid->__PPIX_LEXER__record_capture_number( $number );
    }
    return $number;
}

1;

__END__

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=PPIx-Regexp>,
L<https://github.com/trwyant/perl-PPIx-Regexp/issues>, or in
electronic mail to the author.

=head1 AUTHOR

Thomas R. Wyant, III F<wyant at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009-2023, 2025 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :
