#!perl

use Test::Most tests => 7;

use Curses qw(newterm);
use DateTime;
use IO::Pty;
use Term::VT102;
use Scalar::Util qw(blessed);


# set up a dummy screen (80x24) for curses to use
my $pty = IO::Pty->new;
unless (my $pid = fork) {
    $pty->close_slave;
    my $vt = Term::VT102->new(cols => 80, rows => 24);
    $vt->callback_set('OUTPUT', sub { print $pty $_[2]; });
    while (<$pty>) { $vt->process($_); }
    exit;
}
my $slave = $pty->slave;
my $screen = newterm('vt100', $slave, $slave)
    or BAIL_OUT(q{couldn't initialize curses});

# lat/long/alt/date and its known positions on an 80x24 terminal
my ($known_lat, $known_long, $known_alt) = (-15.75, -69.42, 3812);
my $known_date = DateTime->new(year => 2020, month => 2, day => 7);
my @known_positions = ([14, 16],
                       [12, 18], [ 9, 21], [ 8, 50], [18,  5],
                       [17, 10], [16, 12], [ 6, 28], [10, 19]);


use_ok('Curses::Orrery');
    ok(my $orrery = Curses::Orrery->new(lat    => $known_lat,
                                        long   => $known_long,
                                        alt    => $known_alt,
                                        screen => $screen));
isa_ok($orrery->planets, 'ARRAY');
cmp_ok(my @planets = @{$orrery->planets}, '==', 9);
subtest 'planets' => sub {
    foreach (@planets) {
        isa_ok($_, 'Astro::Coords::Planet');
    }
};
cmp_ok($orrery->datetime($known_date), '==', $known_date);
subtest 'positions' => sub {
    foreach my $n (0 .. @{$orrery->planets} - 1) {
        my ($known_line, $known_col) = @{$known_positions[$n]};
        my ($az, $el) = $orrery->planets->[$n]->azel;

        cmp_ok($orrery->_el_line($el), '==', $known_line);
        cmp_ok($orrery->_az_col ($az), '==', $known_col);
    }
};
