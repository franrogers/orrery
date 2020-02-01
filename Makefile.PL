use 5.008;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME            => 'Orrery',
    VERSION_FROM    => 'lib/Orrery.pm',
    EXE_FILES       => ['bin/orrery'],
    PREREQ_PM       => {
        'Astro::Coords' => '0',
        'Astro::Telescope' => '0',
        'Curses' => '0',
    },
);
