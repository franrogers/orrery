use 5.008;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Curses::Orrery',
    VERSION_FROM     => 'lib/Curses/Orrery.pm',
    EXE_FILES        => ['bin/orrery'],
    MIN_PERL_VERSION => 5.12.0,
    PREREQ_PM        => {
        'Astro::Coords'             => '0.20',
        'Astro::MoonPhase'          => '0.60',
        'Astro::Telescope'          => '0.71',
        'Curses'                    => '1.36',
        'DateTime'                  => '1.51',
        'List::MoreUtils'           => '0.428',
        'Math::Units'               => '1.3',
        'Moose'                     => '2.2012',
        'MooseX::Types'             => '0.50',
        'MooseX::Types::Structured' => '0.36',
        'Switch'                    => '2.17',
    },
);
