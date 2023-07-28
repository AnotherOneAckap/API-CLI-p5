# ABSTRACT: Does the actual request to the API
use strict;
use warnings;
use 5.010;
package API::CLI::Request;

our $VERSION = '0.000'; # VERSION

use Moo;

has openapi => ( is => 'ro' );
has method => ( is => 'ro' );
has path => ( is => 'ro' );
has req => ( is => 'rw' );
has url => ( is => 'rw' );
has verbose => ( is => 'ro' );

sub from_openapi {
    my ($class, %args) = @_;

    my $method = $args{method};
    my $path = delete $args{path};
    my $opt = delete $args{options};
    my $params = delete $args{parameters};

    my $self = $class->new(
        openapi => delete $args{openapi},
        method => delete $args{method},
        path => $path,
        %args,
    );

    my $url;

    my $openapi = $self->openapi;

    if ($openapi->{openapi} =~ /^3\.0\.[0-9]+/) {
        my $default_server = $openapi->{servers}[0];
        my $base_url;

        # server could be specified by index or by base url
        # index in a list made of
        # - servers in specification, see https://spec.openapis.org/oas/v3.0.3#openapi-object
        # - servers in Path Item Object, see https://spec.openapis.org/oas/v3.0.3#fixed-fields-6
        if (defined $opt->{server}) {
            if ($opt->{server} =~ /^[0-9]+$/) {
                my $global_servers = $openapi->{servers} || [];
                my $local_servers = $openapi->{paths}{$path}{servers} || [];
                my @all_servers = (@$global_servers, @$local_servers);
                my $server = $all_servers[ $opt->{server} ];
                die "Chosen server does not exists" unless defined $server;
                $base_url = $server->{url};
            }
            else {
                $base_url = $opt->{server};
            }
        }
        else {
            $base_url = $openapi->{servers}[0]{url};
        }

        $url = URI->new($base_url);
    }
    else {
      my ($basePath,$host,$scheme);
      $host     = $self->openapi->{host};
      $scheme   = $self->openapi->{schemes}->[0];
      $basePath = $self->openapi->{basePath} // '';
      $basePath = '' if $basePath eq '/';
      $url      = URI->new("$scheme://$host$basePath$path");
    }

    my %query;
    for my $name (sort keys %$opt) {
        my $value = $opt->{ $name };
        if ($name =~ s/^q-//) {
            $query{ $name } = $value;
        }
    }
    $url->query_form(%query);
    $self->url($url);

    my $req = HTTP::Request->new( $self->method => $self->url );
    $self->req($req);

    return $self;
}

sub request {
    my ($self) = @_;

    my $ua = LWP::UserAgent->new;
    my $req = $self->req;
    my $res = $ua->request($req);
    my $code = $res->code;
    my $content = $res->decoded_content;
    my $status = $res->status_line;

    my $ct = $res->content_type;
    my $out = $self->verbose ? "Response: $status ($ct)\n" : undef;
    my $data;
    my $ok = 0;
    if ($res->is_success) {
        $ok = 1;
        if ($ct eq 'application/json') {
            my $coder = JSON::XS->new->ascii->pretty->allow_nonref;
            $data = $coder->decode($content);
            $content = $coder->encode($data);
        }
    }

    return ($ok, $out, $content);
}

sub content {
    shift->req->content(@_);
}

sub header {
    shift->req->header(@_);
}

1;

__END__

=pod

=head1 NAME

API::CLI::Request = Does the actual request to the API

=head1 METHODS

=over 4

=item content

    $req->content($data);

Sets POST/PUT/PATCH content


=item from_openapi

=item header

=item method

=item openapi

=item path

=item req

=item request

=item url

=item verbose

=back

=cut
