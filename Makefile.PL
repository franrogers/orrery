use 5.008;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Curses::Orrery',
    VERSION_FROM     => 'lib/Curses/Orrery.pm',
    EXE_FILES        => ['bin/orrery'],
    MIN_PERL_VERSION => 5.10.0,
    PREREQ_PM        => {
        'Astro::Coords'    => '0.20',
        'Astro::MoonPhase' => '0.60',
        'Astro::Telescope' => '0.71',
        'Curses'           => '1.36',
        'DateTime'         => '1.51',
        'Math::Units'      => '1.3',
        'Switch'           => '2.17',
    },
);
