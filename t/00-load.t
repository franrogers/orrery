#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Curses::Orrery' ) || print "Bail out!\n";
}

diag( "Testing Curses::Orrery $Curses::Orrery::VERSION, Perl $], $^X" );
