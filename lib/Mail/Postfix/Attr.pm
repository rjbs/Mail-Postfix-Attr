package Mail::Postfix::Attr;

use strict;
use warnings;

use Carp ;

our $VERSION = '0.03';

my %codecs = (

	'0'	=> [ \&encode_0, \&decode_0 ],
	'64'	=> [ \&encode_64, \&decode_64 ],
	'plain'	=> [ \&encode_plain, \&decode_plain ],
) ;

sub new {

	my ( $class, %args ) = @_ ;

	my $self = bless {}, $class ;

	my $codec_ref = $codecs{ $args{'codec'} } || $codecs{ 'plain' } ;

	$self->{'sock_path'} = $args{'path'} ;
	$self->{'inet'} = $args{'inet'} ;

	( $self->{'encode'}, $self->{'decode'} ) = @{$codec_ref} ;

	return $self ;
}

sub send {

	my ( $self ) = shift ;

	my $handle ;

	if ( $self->{'sock_path'} ) {

		require IO::Socket::UNIX ;

		$handle = IO::Socket::UNIX->new( $self->{'sock_path'} ) ;

		$handle or croak
"Mail::Postfix::Attr can't connect to '$self->{'sock_path'}' $!\n" ;
	}
	elsif ( $self->{'inet'} ) {

		require IO::Socket::INET ;

		$handle = IO::Socket::INET->new( $self->{'inet'} ) ;

		$handle or croak
"Mail::Postfix::Attr can't connect to '$self->{'inet'}' $!\n" ;

	}
	else {
		croak "must have 'path' or 'inet' set to use send" ;
	}

	my $attr_text = $self->encode( @_ ) ;

	my $cnt = syswrite( $handle, $attr_text ) ;

#print "ERR $!\n" unless defined $cnt ;
#print "sent $cnt [$attr_text]\n" ;

	sysread( $handle, my $attr_buf, 64000 ) ;

#print "SEND READ [$attr_buf]\n" ;

	my @result = $self->decode( $attr_buf );

	return map { @$_ } @result;
}

sub encode {
	my ( $self ) = @_ ;
	goto $self->{'encode'} ;
}

sub decode {
	my ( $self ) = @_ ;
	goto $self->{'decode'} ;
}

sub encode_0 {

	my( $self ) = shift ;

	my $attr_text ;

	while( my( $attr, $val ) = splice( @_, 0, 2 ) ) {

		$attr_text .= "$attr\0$val\0" ;
	}

	return "$attr_text\0" ;
}

sub encode_64 {

	my( $self ) = shift ;

	my $attr_text ;

	require MIME::Base64 ;

	while( my( $attr, $val ) = splice( @_, 0, 2 ) ) {

		$attr_text .= MIME::Base64::encode_base64( $attr, '' ) . ':' .
			      MIME::Base64::encode_base64( $val, '' ) . "\n" ;

	}

	return "$attr_text\n" ;
}

sub encode_plain {

	my( $self ) = shift ;

	my $attr_text ;

	while( my( $attr, $val ) = splice( @_, 0, 2 ) ) {

		$attr_text .= "$attr=$val\n" ;
	}

	return "$attr_text\n" ;
}



sub decode_0 {

	my( $self, $text ) = @_ ;

	my @attrs ;

	foreach my $section ( split /(?<=\0\0)/, $text ) {

		push( @attrs, [ split /\0/, $section ] ) ;
	}

	return @attrs ;
}

sub decode_64 {

	my( $self, $text ) = @_ ;

	require MIME::Base64 ;

	my @attrs ;

	foreach my $section ( split /(?<=\n\n)/, $text ) {

		push( @attrs, [ map MIME::Base64::decode_base64 $_,
					$section =~ /^([^:]+):(.+)$/mg ] ) ;
	}

	return @attrs ;
}

sub decode_plain {

	my( $self, $text ) = @_ ;

	my @attrs ;

	foreach my $section ( split /(?<=\n\n)/, $text ) {

		push( @attrs, [ split /[\n=]/, $section ] ) ;
	}

	return @attrs ;
}

1;
__END__

=head1 NAME

Mail::Postfix::Attr - Encode and decode Postfix attributes

=head1 SYNOPSIS

  use Mail::Postfix::Attr;

  my $pf_attr = Mail::Postfix::Attr->new( 'codec' => '0',
					  'path' => '/tmp/postfix_sock' ) ;


  my $pf_attr = Mail::Postfix::Attr->new( 'codec' => 'plain',
					  'inet' => 'localhost:9999' ) ;

  my @result_attrs = $pf_attr->send( 'foo' => 4, 'bar' => 'blah' ) ;

  my $attr_text = $pf_attr->encode( 'foo' => 4, 'bar' => 'blah' ) ;

  my @attrs = $pf_attr->decode( $attr_text ) ;

=head1 DESCRIPTION

Mail::Postfix::Attr supports encoding and decoding of the three
formats of attributes used in the postfix MTA. Attributes are used by
postfix to communicate with various of its services such as the verify
program. These formats are:

  plain	- key=value\n	(a collection of attributes has an \n appended)
  0	- key\0value\0	(a collection of attributes has a \0 appended)
  64	- base64(key):base64(value)\n
			(a collection of attributes has an \n appended)

These formats are from the specifications in the postfix source files
in the src/util directory:

  attr_scan0.c
  attr_scan64.c
  attr_scan_plain.c
  attr_print0.c
  attr_print64.c
  attr_print_plain.c 	

If you run 'make test' (after building postfix) in this directory it will build these programs which can be used to test this Perl module:

  attr_scan0
  attr_scan64
  attr_scan_plain
  attr_print0
  attr_print64
  attr_print_plain

=head2 new() method 

	my $pf_attr = Mail::Postfix::Attr->new( 'codec' => '0',
					  'path' => '/tmp/postfix_sock' ) ;

The new method takes a list of key/value arguments.

	codec	=> <codec_type>
	path	=> <unix_socket_path>
	inet	=> <host:port>

	codec_type is one of '0', '64' or 'plain'. It defaults to
	'plain' if not set or it is not in the allowed codec set.

	The <unix_socket_path> argument is the unix domain socket that
	will be used to send a message to a postfix service. The
	message will be encoded and its response decoded with the
	selected codec.

	The <inet> argument is the internet domain address that will
	be used to send a message to a postfix service. It must be in
	the form of "host:port" where host can be a hostname or IP
	address and port can be a number or a name in
	/etc/services. The message will be encoded and its response
	decoded with the selected codec.

=head2 send() method 

The send method is passed a list of postfix attribute key/value
pairs. It first connects to a postfix service using the UNIX or INET
socket. It then encodes the attributes using the selected codec and
writes that data to the socket. It then reads from the socket to EOF
and decodes that data with the codec and returns that list of
attribute key/value pairs to the caller.

  my @result_attrs = $pf_attr->send( 'foo' => 4, 'bar' => 'blah' ) ;

=head2 encode() method 

The encode method takes a list of key/values and encodes it according
to the selected codec. It returns a single string which has the
encoded text of the attribute/value pairs. Each call will create a
single attribute section which is terminated by an extra separator
char.

  my $attr_text = $pf_attr->encode( 'foo' => 4, 'bar' => 'blah' ) ;

You can also call each encoder directly as a class method:

  my $attr_text = Mail::Postfix::Attr->encode_0( 'foo' => 4, 'bar' => 'blah' ) ;
  my $attr_text =
	Mail::Postfix::Attr->encode_64( 'foo' => 4, 'bar' => 'blah' ) ;
  my $attr_text =
	Mail::Postfix::Attr->encode_plain( 'foo' => 4, 'bar' => 'blah' ) ;

=head2 decode() method 

The decode method takes a single string of encoded attributes and
decodes it into a list of attribute sections. Each section is decoded
into a list of attribute/value pairs. It returns a list of array
references, each of which has the attribute/value pairs of one
attribute section.

  my @attrs = $pf_attr->decode( $attr_text ) ;

You can also call each decoder directly as a class method:

  my @attrs = Mail::Postfix::Attr->decode_0( $attr_text ) ;
  my @attrs = Mail::Postfix::Attr->decode_64( $attr_text ) ;
  my @attrs = Mail::Postfix::Attr->decode_plain( $attr_text ) ;

=head1 EXAMPLES

  # talk to the verify(8) service available in Postfix v2.
  # 
  # perl -MMail::Postfix::Attr -le 'print for Mail::Postfix::Attr
           ->new (codec=>0, path=>"/var/spool/postfix/private/verify")
           ->send(request=>query=>address=>shift)'
          postmaster@localhost

  status
  0
  recipient_status
  0
  reason
  aliased to root

=head1 AUTHOR

Uri Guttman, uri@stemsystems.com

=cut
