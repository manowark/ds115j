#!/usr/bin/perl
# ttymode-diag.pl — Read-only TIOCMGET diagnostic for DS115j /dev/ttyS1.
# No termios writes, no MCU bytes. Answers: does open-mode change modem lines?
use strict;
use warnings;

my $TTY = "/dev/ttyS1";

my @TIOCM = (
    [0x002, "DTR"], [0x004, "RTS"], [0x020, "CTS"], [0x040, "CD"], [0x080, "RI"], [0x100, "DSR"],
);

for my $t (
    ["O_RDONLY", 0],
    ["O_RDWR|O_NOCTTY|O_NONBLOCK", 2 | 0x100 | 0x800],
    ["O_RDWR|O_NOCTTY", 2 | 0x100],
) {
    my ($name, $flags) = @$t;
    my $fh;
    my $ok = sysopen($fh, $TTY, $flags);
    if (!$ok) {
        print "$name  open failed: $!\n";
        next;
    }
    my $buf = "\0\0\0\0";
    my $r = ioctl($fh, 0x5415, $buf);   # TIOCMGET
    if (!$r) {
        print "$name  TIOCMGET failed: $!\n";
    } else {
        my $m = unpack("I", $buf);
        my @set = map { $_->[1] } grep { $m & $_->[0] } @TIOCM;
        printf "%s  TIOCM=0x%04x  lines=[%s]\n", $name, $m, join(" ", @set);
    }
    close($fh);
}