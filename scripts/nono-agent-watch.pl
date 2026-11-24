# nono-agent の bwrap 内で動き、読み取り専用マウントが外れたら fd 8 で外側へ知らせる。
# マウントは外側で実体が rename や削除で置き換わると外れる (git config、エディタの保存など)。
# 引数: <監視するパス...> -- <実行するコマンド...>
use strict;
use warnings;
use IO::Poll qw(POLLPRI POLLERR);

my @paths;
while (@ARGV) {
    my $arg = shift @ARGV;
    last if $arg eq '--';
    push @paths, $arg;
}

my $pid = fork() // die "fork: $!";
if ($pid) {
    open(my $alert, '>&=', 8) or die "fd 8: $!";
    close($alert);
    exec { $ARGV[0] } @ARGV or die "exec $ARGV[0]: $!";
}

my $parent = getppid();
open(my $alert, '>&=', 8) or die "fd 8: $!";
open(my $info, '<', '/proc/self/mountinfo') or die "mountinfo: $!";
# 端末と標準入出力を掴んだままにしない
open(STDIN,  '<', '/dev/null');
open(STDOUT, '>', '/dev/null');
open(STDERR, '>', '/dev/null');

my $poll = IO::Poll->new;
$poll->mask($info => POLLPRI | POLLERR);
while (getppid() == $parent) {
    seek($info, 0, 0);
    my %read_only;
    while (my $line = <$info>) {
        my (undef, undef, undef, undef, $point, $options) = split / /, $line;
        $point =~ s/\\([0-7]{3})/chr(oct($1))/ge;
        $read_only{$point} = $options =~ /(?:^|,)ro(?:,|$)/;
    }
    for my $path (@paths) {
        next if $read_only{$path};
        syswrite($alert, "$path\n");
        exit 0;
    }
    $poll->poll(1);
}
