use warnings;
use strict;

use URL::Encode qw(url_encode);
use File::Spec;
use ZeroMQ qw(:all);
use YAML qw(LoadFile);
use JSON;

my $config  = LoadFile('config.yaml');
my $context = ZeroMQ::Context->new;
my $socket  = do {
    my $s = $context->socket(ZMQ_SUB);
    $s->setsockopt(ZMQ_SUBSCRIBE, '');
    $s->connect($config->{bridge} || 'tcp://127.0.0.1:6668');
    $s;
};

my $data_dir = $config->{data} || './data';
mkdir $data_dir unless -d $data_dir;
chdir $data_dir or die "Cannot chdir to $data_dir: $!";

while (my $msg = decode_json($socket->recv->data)) {
    my $chan = url_encode($msg->{channel});
    mkdir $chan unless -d $chan;
    my $current = File::Spec->catfile($chan, 'current');

    open my $fh, '>>', $current 
        or warn "Cannot open $current for appending: $!";
    print {$fh} join("\t", @{$msg}{qw(timestamp sender message)}), "\n"
        or warn "Cannot write to $current: $!";
    close $fh
        or warn "Cannot close $current: $!";

    my $size = (stat $current)[7];
    if ($size >= 1024*8) {
        my $archive = File::Spec->catfile($chan, $msg->{timestamp});
        rename($current, $archive);
        system('gzip', $archive);
    }
}
