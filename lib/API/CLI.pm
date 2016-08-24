use strict;
use warnings;
use 5.010;
package API::CLI;

use base 'App::Spec::Run';

use URI;
use YAML::XS ();
use LWP::UserAgent;
use HTTP::Request;
use App::Spec;
use JSON::XS;
use API::CLI::Request;

use Moo;

has dir => ( is => 'ro' );
has openapi => ( is => 'ro' );
has spec => ( is => 'rw' );

my $appspec_skeleton_data = do { local $/; <DATA> };
my $appspec_skeleton;

sub BUILD {
    my ($self, $args) = @_;
    $self->build_appspec(
        name => $args->{name},
    );
}

sub add_auth {
    my ($self, $req) = @_;
    my $appconfig = $self->read_appconfig;
    my $token = $appconfig->{token};
    $req->header(Authorization => "Bearer $token");
}

sub read_appconfig {
    my ($self) = @_;
    my $dir = $self->dir;
    my $appconfig = YAML::XS::LoadFile("$dir/config.yaml");
}


sub build_appspec {
    my ($self, %args) = @_;
    unless ($appspec_skeleton) {
        eval {
            $appspec_skeleton = YAML::XS::Load($appspec_skeleton_data);
            1;
        } or die "Couldn't load appspec skeleton from DATA: $@";
    }
    my $skeleton = $appspec_skeleton;

    my $openapi = $self->openapi;
    my $spec = $self->spec || {};
    $spec = { %$skeleton, %$spec };

    my $paths = $openapi->{paths};
    my $subcommands = $spec->{subcommands} = {};

    for my $path (sort keys %$paths) {
        my $methods = $paths->{ $path };
        for my $method (sort keys %$methods) {

            my $config = $methods->{ $method };
            $spec->{name} = $args{name};
            $spec->{title} //= $openapi->{info}->{title};
            $spec->{description} = $openapi->{info}->{description};

            my @parameters;
            my @options;
            if (my $params = $config->{parameters}) {
                for my $p (@$params) {
                    my $appspec_param = $self->param2appspec($p);
                    if ($p->{in} eq 'path') {
                        push @parameters, $appspec_param;
                    }
                    elsif ($p->{in} eq 'query') {
                        push @options, $appspec_param;
                    }
                }
            }

            my $apicall = $subcommands->{ uc $method } ||= {
                op => 'apicall',
                summary => "\U$method\E call",
                subcommands => {},
            };
            my $desc = $config->{description};
            $desc =~ s/\n.*//s;
            if (length $desc > 30) {
                $desc = substr($desc, 0, 50) . '...';
            }
            my $subcmd = $apicall->{subcommands}->{ $path } ||= {
                summary => $desc,
                parameters => \@parameters,
                options => \@options,
            };

        }
    }

    my $appspec = App::Spec->read($spec);
#    warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$appspec], ['appspec']);

    $self->spec($appspec);
}

sub param2appspec {
    my ($self, $p) = @_;
    my $type = $p->{type};
    my $required = $p->{required};
    my $item = {
        name => $p->{name},
        type => $type,
        required => $required,
        summary => $p->{description},
        $p->{enum} ? (enum => $p->{enum}) : (),
    };
    if ($p->{in} eq 'path') {
    }
    elsif ($p->{in} eq 'query') {
        $item->{name} = "q-" . $item->{name};
    }
    return $item;
}

sub apicall {
    my ($self) = @_;
    my ($method, $path) = @{ $self->commands };
    my $params = $self->parameters;
    my $opt = $self->options;
    warn __PACKAGE__.':'.__LINE__.": apicall($method $path)\n";
    warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$params], ['params']);
    warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$opt], ['opt']);
    $path =~ s{(?::(\w+)|\{(\w+)\})}{$params->{ $1 // $2 }}g;
    warn __PACKAGE__.':'.__LINE__.": apicall($method $path)\n";

    my $REQ = API::CLI::Request->from_openapi(
        openapi => $self->openapi,
        method => $method,
        path => $path,
        options => $opt,
        parameters => $params,
    );

    $self->add_auth($REQ);

    if ($method =~ m/^(POST|PUT|PATCH|DELETE)$/) {
        my $data_file = $opt->{'data-file'};
        if (defined $data_file) {
            open my $fh, '<', $data_file or die "Could not open '$data_file': $!";
            my $data = do { local $/; <$fh> };
            close $fh;
            $REQ->content($data);
        }
    }

    my ($ok, $out, $content) = $REQ->request;
    unless ($ok) {
        $out = $self->error($out);
    }
    warn $out;
    say $content;

}

1;

__DATA__
---
appspec: { version: 0.001 }
options:
  - name: debug
    type: bool
    description: Debug
  - name: data-file
    type: file
    description: File with data for POST/PUT/PATCH/DELETE requests
