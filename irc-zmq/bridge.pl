use warnings;
use strict;

use AnyEvent;
use AnyEvent::IRC::Client;
use YAML qw(LoadFile);
use JSON;
use ZeroMQ qw(:all);

my $config  = LoadFile('config.yaml');
my %clients;

{
    my $context   = ZeroMQ::Context->new;
    my $sock      = $context->socket(ZMQ_PUB);
    my $zmq       = $config->{zmq};
    my $interface = $zmq->{interface} || '127.0.0.1';
    my $port      = $zmq->{port}      || '6668';
    $sock->bind("tcp://$interface:$port");

    sub notify {
        my %args = @_;
        $args{timestamp} = time();
        $sock->send(encode_json \%args);
    }
}

for my $spec (@{ $config->{irc} }) {
    my $port = $spec->{port} ||= 6667;
    my $nick = $spec->{nick} ||= 'capnbridgr';
    my %channels;
    for my $entry (@{ $spec->{channels} }) {
        $entry = { name => $entry, channel => "\#$entry" }
            unless ref $entry eq 'HASH';
        $channels{ $entry->{channel} } = $entry->{name};
    }
    my $client   = AnyEvent::IRC::Client->new;
    $client->reg_cb(
        registered => sub {
            $client->send_msg(JOIN => "$_") for keys %channels;
        }
    );
    $client->reg_cb(
        publicmsg => sub {
            my ($self, $tgt, $msg) = @_;
            local $_ = $msg->{prefix};
            s/!.*$//;
            notify(
                channel => $channels{$tgt},
                sender  => $_,
                message => $msg->{params}->[1],
            );
        }
    );
    $client->reg_cb(
        ctcp_action => sub {
            my ($self, $src, $tgt, $msg, $type) = @_;
            return unless $tgt =~ /^#/;
            notify(
                channel => $channels{$tgt},
                sender  => $src,
                message => "*$msg*",
            );
        }
    );
    $client->connect($spec->{host}, $port, { nick => $nick });
}


AE::cv->wait;
for my $spec (values %clients) {
    my $msg = $spec->{quit} || 'Shutting down.';
    $spec->{client}->disconnect($msg);
}
