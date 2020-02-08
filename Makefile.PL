use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
    NAME             => 'Curses::Orrery',
    AUTHOR           => q{Fran Rogers <fran@violuma.net>},
    VERSION_FROM     => 'lib/Curses/Orrery.pm',
    ABSTRACT_FROM    => 'lib/Curses/Orrery.pm',
    LICENSE          => 'artistic_2',
    MIN_PERL_VERSION => '5.12.0',
    EXE_FILES        => ['bin/orrery'],
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '0',
    },
    TEST_REQUIRES => {
        'IO::Pty'     => '1.14',
        'Term::VT102' => '0.91',
        'Test::Most'  => '0.35',
    },
    PREREQ_PM => {
        'Astro::Coords'    => '0.20',
        'Astro::MoonPhase' => '0.60',
        'Astro::Telescope' => '0.71',
        'Curses'           => '1.36',
        'DateTime'         => '1.51',
        'Math::Units'      => '1.3',
        'Moo'              => '2.003006',
        'Type::Tiny'       => '1.008005',
        'Switch'           => '2.17',
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Curses-Orrery-*' },
);

# Compatibility with old versions of ExtUtils::MakeMaker
unless (eval { ExtUtils::MakeMaker->VERSION('6.64'); 1 }) {
    my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES} || {};
    @{$WriteMakefileArgs{PREREQ_PM}}{keys %$test_requires} = values %$test_requires;
}

unless (eval { ExtUtils::MakeMaker->VERSION('6.55_03'); 1 }) {
    my $build_requires = delete $WriteMakefileArgs{BUILD_REQUIRES} || {};
    @{$WriteMakefileArgs{PREREQ_PM}}{keys %$build_requires} = values %$build_requires;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION('6.52'); 1 };
delete $WriteMakefileArgs{MIN_PERL_VERSION}
    unless eval { ExtUtils::MakeMaker->VERSION('6.48'); 1 };
delete $WriteMakefileArgs{LICENSE}
    unless eval { ExtUtils::MakeMaker->VERSION('6.31'); 1 };

WriteMakefile(%WriteMakefileArgs);
