use warnings;
use strict;

use AnyEvent;
use AnyEvent::IRC::Client;
use YAML qw(LoadFile);
use JSON;
use ZeroMQ qw(:all);
use Time::HiRes;

my $config  = LoadFile('config.yaml');
my %clients;
my ($info_watcher, $info_json, $botstamp, %bot_info);

# Timestamps are always in MILLISECONDS since the epoch. Why? Because its a
# reasonable resolution for chat (things happen within the same second all the
# time, but very rarely within the same millisecond), and because it's the
# native Javascript Date resolution. Why does that matter? One of our clients
# is server-side javascript, and our transport is JSON, so it kind of fits.
sub timestamp {
    my ($s, $u) = Time::HiRes::gettimeofday();
    int($s * 1000 + $u/1000);
}

{
    my $context = ZeroMQ::Context->new;
    {
        my $live = $context->socket(ZMQ_PUB);
        $live->bind($config->{live} || 'tcp://127.0.0.1:6668');
        sub notify {
            my %args = @_;
            $args{timestamp} = timestamp();
            $live->send(encode_json \%args);
        }
    }

    {
        my $info = $context->socket(ZMQ_REP);
        $info->bind($config->{info} || 'tcp://127.0.0.1:8666');

        my %dispatch = (
            'timestamp' => sub { $botstamp },
            'channels'  => sub { $info_json },
        );

        sub respond {
            $info_watcher = AE::io $info->getsockopt(ZMQ_FD), 0, sub {
                while(my $msg = $info->recv(ZMQ_NOBLOCK)) {
                    my $respond  = $dispatch{$msg->data};
                    my $response = $respond
                        ? $respond->()
                        : '{"error":"bad request"}';
                    $info->send($response);
                }
            };
        }
    }
}

for my $spec (@{ $config->{irc} }) {
    my $port = $spec->{port} ||= 6667;
    my $nick = $spec->{nick} ||= 'capnbridgr';
    my %channels;
    for my $entry (@{ $spec->{channels} }) {
        # normalizing the just-a-string case
        $entry = { name => $entry, channel => "\#$entry" }
            unless ref $entry eq 'HASH';

        $channels{ $entry->{channel} } = $entry->{name};

        # so we can report to info clients what we're listening to
        my %info = (channel => $entry->{channel});
        @info{qw(host nick port)} = @{$spec}{qw(host nick port)};
        $bot_info{ $entry->{name} } = \%info;
    }
    my $client = AnyEvent::IRC::Client->new;
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

$botstamp  = encode_json({ timestamp => timestamp() });
$info_json = encode_json(\%bot_info);
respond();

AE::cv->wait;
for my $spec (values %clients) {
    my $msg = $spec->{quit} || 'Shutting down.';
    $spec->{client}->disconnect($msg);
}

undef $info_watcher;
