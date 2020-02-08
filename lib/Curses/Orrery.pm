package Curses::Orrery;

use warnings;
use Moo;
use Types::Standard qw(ArrayRef Bool InstanceOf Int Num Tuple);

use Astro::Coords::Angle;
use Astro::Coords::Planet;
use Astro::MoonPhase;
use Astro::Telescope;
use Curses;
use DateTime;
use DateTime::TimeZone;
use I18N::Langinfo qw(CODESET langinfo);
use Math::Trig qw(deg2rad pi);
use POSIX qw(round);
use Scalar::Util qw(looks_like_number);
use Switch;

=head1 NAME

Curses::Orrery - Plot the positions of the sun, moon, and planets in the sky

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    use Curses::Orrery;

    $orrery = Curses::Orrery->new(lat  => -15.75,
                                  long => -69.42,
                                  alt  => 3812);
    $orrery->run;

=head1 DESCRIPTION

C<Curses::Orrery> is a geocentric orrery using C<Curses>: given a latitude,
longitude, and optional altitude, it plots on the terminal the positions of the
sun, moon and planets in the sky.

When run, the user can select each individual body for information on its
position and rise/transit/set times, and can also step the movement
hour-by-hour.

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

C<lat> and C<long> are required: they can be decimal degrees, strings of format
C<'(-)DD:MM:SS'>, or L<Astro::Coords::Angle> objects. C<alt>, which is
optional, is the altitude in meters.

    use Curses::Orrery;

    my $orrery = Curses::Orrery->new(lat  => -15.75,
                                     long => -69.42,
                                     alt  => 3812);
    $orrery->run;

You may also specify initial values for the C<datetime>, C<range>,
C<selection_index>, and C<time_zone> attributes.

By default, this constructor initializes L<Curses> on C<*STDIN>/C<STDOUT>.
Alternatively, you can specify a C<screen> argument (obtained from
L<Curses>'s C<newterm>). 

=cut

sub BUILD {
    my $self = shift;

    # configure curses
    $stdscr->keypad(1);
    curs_set 0;
    noecho;
}

sub DEMOLISH {
    endwin;
}

=back

=head2 Accessor Methods

=over 4

=item B<lat>

An L<Astro::Coords::Angle> corresponding to the latitude of the viewer.

=cut

has 'lat' => (
    is       => 'ro',
    isa      => InstanceOf['Astro::Coords::Angle'],
    required => 1,
    coerce   => \&_latlong_coerce,
);

=item B<long>

An L<Astro::Coords::Angle> corresponding to the longitude of the viewer.

=cut

has 'long' => (
    is       => 'ro',
    isa      => InstanceOf['Astro::Coords::Angle'],
    required => 1,
    coerce   => \&_latlong_coerce,
);

sub _latlong_coerce {
    my ($angle) = @_;
    if (!ref $angle) {
        $angle = Astro::Coords::Angle->new($angle,
                                           range => 'PI',
                                           units => looks_like_number($angle)
                                                  ? 'degrees'
                                                  : 'sexagesimal');
    }
    return $angle;
}

=item B<alt>

The altitude of the viewer in meters. Defaults to C<0> if not provided.

=cut

has 'alt' => (
    is      => 'ro',
    isa     => Num,
    default => 0,
);

=item B<datetime>

Get/set a L<DateTime> specifying a specific date to plot. If unset, the current
date/time will be plotted.

=cut

has 'datetime' => (
    is        => 'rw',
    isa       => InstanceOf['DateTime'],
    lazy      => 1,
    clearer   => 'clear_datetime',
    predicate => 'has_datetime',
    trigger   => \&_datetime_set,
);

sub _datetime_set {
    my ($self, $dt) = @_;

    foreach my $planet (@{$self->planets}) {
        $planet->usenow(0);
        $planet->datetime($dt);
    }
}

after 'clear_datetime' => sub {
    my $self = shift;

    foreach my $planet (@{$self->planets}) {
        $planet->datetime(undef);
        $planet->usenow(1);
    }
};

sub advance_to_next {
    my ($self, $time_part, $magnitude) = @_;
 
    my $dt = $self->has_datetime ? $self->datetime : DateTime->now;
    $dt = $dt->truncate(to => $time_part);
    $dt = $dt->add("${time_part}s", $magnitude);
    $self->datetime($dt);
}

=item B<time_zone>

A L<DateTime::TimeZone> corresponding to the viewer's local time zone,
for user output. Defaults to local time.

=cut

has 'time_zone' => (
    is      => 'rw',
    isa     => InstanceOf['DateTime::TimeZone'],
    default => sub { DateTime::TimeZone->new(name => 'local') },
);

=item B<range>

A four-element array reference specifying the range of positions to plot in
radians, of format C<[$min_azimuth, $max_azimuth, $min_elevation,
$max_elevation]>.

Defaults to C<[0, 2*pi, -pi, pi]> (putting due south in the center of the plot)
if the viewer is in the Northern Hemisphere, and C<-pi, pi, -pi. pi> if the
viewer is in the Southern (putting due north in the center of the plot).

=cut

has 'range' => (
    is      => 'rw',
    isa     => Tuple[Num, Num, Num, Num],
    lazy    => 1,
    default => \&_range_default,
);

sub _range_default {
    my $self = shift;

    return $self->lat > 0 ? [  0, 2*pi, -pi/2, pi/2]
                          : [-pi,   pi, -pi/2, pi/2];
}

=item B<planets>

An array reference of L<Astro::Coords::Planet> objects corresponding to the
seven non-Earth planets, Sun, and Moon. Each is populated with C<lat>, C<long>,
and C<alt>, and updated when C<datetime> is changed.

=cut

has 'planets' => (
    is       => 'ro',
    isa      => ArrayRef[InstanceOf['Astro::Coords::Planet']],
    lazy     => 1,
    init_arg => undef,
    builder  => '_planets_builder',
);

sub _planets_builder {
    my $self = shift;

    my $tel = Astro::Telescope->new(Name => 'orrery',
                                    Lat  => $self->lat,
                                    Long => $self->long,
                                    Alt  => $self->alt);

    my @planets;
    foreach my $planet_name (@Astro::Coords::Planet::PLANETS) {
        my $planet = Astro::Coords::Planet->new($planet_name);
        $planet->telescope($tel);
        if ($self->has_datetime) {
            $planet->datetime($self->datetime);
        }
        else {
            $planet->usenow(1);
        }
        push @planets, $planet;
    }
    return \@planets;
}

sub _planet_symbol {
    my ($self, $planet) = @_;

    my %abbrevs = (sun     => 'S', mercury => 'M', venus   => 'v',
                   moon    => 'L', mars    => 'm', jupiter => 'j',
                   saturn  => 's', uranus  => 'u', neptune => 'n');
    my %symbols = (sun     => "\x{2609}", mercury => "\x{263f}",
                   venus   => "\x{2640}", moon    => "\x{263D}",
                   mars    => "\x{2642}", jupiter => "\x{2643}",
                   saturn  => "\x{2644}", uranus  => "\x{2645}",
                   neptune => "\x{2646}");

    return $self->unicode
         ? $symbols{$planet->name}
         : $abbrevs{$planet->name};
}

=item B<selection_index>

An optional index specifying which planet is selected in the user interface.

=cut

has 'selection_index' => (
    is        => 'rw',
    isa       => Int,
    clearer   => 'clear_selection',
    predicate => 'has_selection',
    trigger   => \&_selection_index_set,
);

sub _selection_index_set {
    my ($self, $index) = @_;

    my $num_planets = @{$self->planets};
    if ($index >= $num_planets) {
        $self->selection_index($index % $num_planets);
    }
    elsif ($index < 0) {
        $self->selection_index($num_planets - 1);
    }
}

sub select_next {
    my $self = shift;
    $self->selection_index( $self->has_selection
                          ? $self->selection_index + 1
                          : 0);
}

sub select_prev {
    my $self = shift;
    $self->selection_index( $self->has_selection
                          ? $self->selection_index - 1
                          : @{$self->planets} - 1);
}

has 'screen' => (
    is      => 'ro',
    isa     => InstanceOf['Curses::Screen'],
    default => \&_screen_default,
);

sub _screen_default {
    # this is equivalent to initscr()
    return newterm($ENV{'TERM'}, *STDOUT, *STDIN);
}

=item B<unicode>

A Boolean value specifying whether to represent planets as planetary symbols if
true, or letters if false. Defaults to true if langinfo(CODESET)> is a Unicode
encoding.

=cut

has 'unicode' => (
    is      => 'rw',
    isa     => Bool,
    default => \&_unicode_default,
);

sub _unicode_default {
    return langinfo(CODESET) =~ /^utf|^ucs/i;
}

=back

=head2 General Methods

=over 4

=item B<draw>

Plots the planets on the screen.

=cut

sub draw {
    my $self = shift;

    clear;

    $self->_draw_axes;

    foreach my $planet (@{$self->planets}) {
        $self->_draw_planet($planet);
    }

    $self->_draw_selection;

    $self->_draw_status;

    refresh;
}

sub _az_col {
    my ($self, $az) = @_;
    my ($min_az, $max_az) = @{$self->range}[0,1];

    $az = $az->radians if ref $az;
    $az = -2*pi + $az  if $az > $max_az;

    return round($COLS * ($az - $min_az) / ($max_az - $min_az));
}

sub _el_line {
    my ($self, $el) = @_;
    my ($min_el, $max_el) = @{$self->range}[2,3];

    $el = $el->radians if ref $el;

    return round($LINES - $LINES * ($el - $min_el) / ($max_el - $min_el));
}

sub _draw_axes {
    my $self = shift;

    # x axis
    my $y_line = $self->_el_line(0);
    hline($y_line, 0, ACS_HLINE, $COLS);
    foreach my $az (45, 90, 135, 180, 225, 270, 315) {
        my $label_col = $self->_az_col(deg2rad($az));

        if ($az == 90) {
            addstring $y_line, $label_col, 'E';
        }
        elsif ($az == 270) {
            addstring $y_line, $label_col, 'W';
        }
        else {
            addch     $y_line, $label_col, ACS_PLUS;
        }
    }

    # y axes (one each at due north and due south)
    foreach my $az (0, pi) {
        my $x_col = $self->_az_col($az);

        next if $az == $self->range->[0]
             || $az == $self->range->[1];

        vline       0, $x_col, ACS_VLINE, $LINES;
        addch $y_line, $x_col, ACS_PLUS;

        foreach my $el (-60, -30, 0, 30, 60) {
            my $label_line = $self->_el_line(deg2rad($el));
            if (!$el) {
                addch $label_line, $x_col, ACS_PLUS;
            } else {
                addstring $label_line, $x_col - 2, sprintf('% 2d', $el);
                addch $label_line, $x_col + 1, ACS_DEGREE;
            }
        }
    }
}

sub _draw_planet {
    my ($self, $planet) = @_;

    my ($az, $el) = $planet->azel;

    my $col  = $self->_az_col($az);
    my $line = $self->_el_line($el);
    
    addstring $line, $col, $self->_planet_symbol($planet);
}

sub _draw_selection {
    my $self = shift;

    return if !$self->has_selection;

    my $planet = $self->planets->[$self->selection_index];

    my ($az, $el) = $planet->azel;

    # redraw the planet in reverse video
    attron(A_REVERSE);
    $self->_draw_planet($planet);
    attroff(A_REVERSE);

    # top left display
    # name
    addstring 0, 0, $planet->name;

    # az/el
    addstring 2,  2, 'azimuth:';
    addstring 2, 12, sprintf('% 4d', $az->degrees);
    addch     2, 16, ACS_DEGREE;
    addstring 3,  0, 'elevation:';
    addstring 3, 12, sprintf('% 4d', $el->degrees);
    addch     3, 16, ACS_DEGREE;
    
    # rise/transit/set
    # first find the nearest transit
    my $transit = $planet->meridian_time(nearest => 1);
    my $transit_day = $transit->clone->truncate(to => 'day');

    # then pick the rise/set in the same cycle
    my $prev_rise = $planet->rise_time(event => -1);
    my $next_rise = $planet->rise_time(event =>  1);
    my $prev_set  = $planet->set_time (event => -1);
    my $next_set  = $planet->set_time (event =>  1);
    my $rise = $transit > $next_rise ? $next_rise : $prev_rise;
    my $set  = $transit < $prev_set  ? $prev_set  : $next_set;

    # local times from here forward
    $transit->set_time_zone($self->time_zone);
    $rise->set_time_zone($self->time_zone);
    $set->set_time_zone($self->time_zone);

    addstring 5,  5, 'rise:';
    addstring 6,  2, 'transit:';
    addstring 7,  6, 'set:';
    my $line = 5;
    foreach my $event_time ($rise, $transit, $set) {
        if (!defined $event_time) {
            addstring $line++, 11, 'never';
            next;
        }

        addstring $line, 11, $event_time->strftime('%R');
        
        # print the date alongside the time if it isn't same-day
        if ($event_time->truncate(to => 'day') != $transit_day) {
            addstring $line, 17, $event_time->strftime('%d %b');
        }

        $line++;
    }
}

sub _draw_status {
    my $self = shift;

    my $dt = $self->has_datetime
           ? $self->datetime->clone
           : DateTime->now;
    $dt->set_time_zone($self->time_zone);

    # bottom left: viewer long, lat, alt
    my ($lat_sign,   $lat_d,  $lat_m,  $lat_s) =
        $self->lat->components;
    my ($long_sign, $long_d, $long_m, $long_s) =
        $self->long->components;
    my $alt = $self->alt;

    my $lower_left = sprintf(q{%3d %02d'%02d"%s %3d %02d'%02d"%s %4dm},
                             $lat_d,   $lat_m,  $lat_s,
                             $lat_sign  eq '+' ? 'N' : 'S',
                             $long_d, $long_m, $long_s,
                             $long_sign eq '+' ? 'E' : 'W',
                             $alt);
    addstring $LINES - 1,  0, $lower_left;
    addch     $LINES - 1,  3, ACS_DEGREE;
    addch     $LINES - 1, 15, ACS_DEGREE;

    # bottom right, line 1: moon phase, illum%
    my ($phase, $illum) = (phase($dt->epoch))[0..1];
    my $phase_name = $phase < 0.02 ? 'new' :
                     $phase < 0.24 ? 'waxing crescent' :
                     $phase < 0.26 ? 'first quarter' :
                     $phase < 0.49 ? 'waxing gibbous' :
                     $phase < 0.51 ? 'full' :
                     $phase < 0.74 ? 'waning gibbous' :
                     $phase < 0.76 ? 'last quarter' :
                     $phase < 0.99 ? 'waning crescent' :
                                     'new';
    my $lower_right2 = sprintf($illum < 1 ? '%s %2d%%': '%s --%',
                               $phase_name,
                               int($illum * 100));
    addstring $LINES - 2, $COLS - length($lower_right2), $lower_right2;

    # bottom right, line 2: solar time
    my $lower_right = sprintf('%s', $dt->strftime('%a %F %R'));
    addstring $LINES - 1, $COLS - length($lower_right), $lower_right;
    if ($self->has_datetime) {
        addch $LINES - 1, $COLS - 23, ACS_BULLET;
    }

    if ($self->unicode) {
        addstring $LINES - 2, $COLS - 22, "\x{263D}";
        addstring $LINES - 1, $COLS - 22, "\x{2609}";
    }
}

=item B<show_help>

Shows an informational dialog on the screen with a key to planetary symbols and
a list of key bindings. Waits for the user to press a key before returning.

=cut

sub show_help {
    my $self = shift;

    # terminal needs to be at least 60x13 to fit help on screen
    my ($help_lines, $help_cols) = (13, 60);
    return if $LINES < $help_lines || $COLS < $help_cols;

    # create the help window
    my $help = $stdscr->derwin($help_lines,
                               $help_cols,
                               $LINES / 2 - $help_lines / 2,
                               $COLS  / 2 - $help_cols  / 2);
    $help->clear;
    $help->box(ACS_VLINE, ACS_HLINE);

    # divide it with a vertical line 1/3 from the left
    my $divider_col = $help_cols / 3;
    $help->addch(              0, $divider_col, ACS_TTEE);
    $help->addch($help_lines - 1, $divider_col, ACS_BTEE);
    $help->vline(              1, $divider_col, ACS_VLINE, $help_lines - 2);

    # populate the left side with a key to the planet symbols
    my $syms = $help->derwin($help_lines - 2, $divider_col - 2, 1, 1);
    $syms->addstring(0, 1, 'planets:');
    for my $n (0 .. @{$self->planets} - 1) {
        my $planet = $self->planets->[$n];
        $syms->addstring($n+1, 2, $self->_planet_symbol($planet));
        $syms->addstring($n+1, 4, $planet->name);
    }

    # populate the right side with key-binding help
    my @binding_help = (['h/l', 'go back/forward in time'],
                        ['n',   'go to the present time'],
                        ['j/k', 'highlight next/previous planet'],
                        ['c',   'clear highlight'],
                        ['?',   'help'],
                        ['q',   'quit']);
    my $keys = $help->derwin($help_lines - 2,
                             $help_cols - $divider_col - 2,
                             1,
                             $divider_col + 1);
    $keys->addstring(0, 1, 'key bindings:');
    foreach my $n (1 .. @binding_help - 1) {
        $keys->addstring($n, 2, $binding_help[$n]->[0]);
        $keys->addstring($n, 7, $binding_help[$n]->[1]);
    }

    $help->addstring($help_lines - 2, $help_cols - 27,
                     'press any key to continue');

    # wait for any key
    $help->getchar;
}

=item B<run>

Draws the screen and waits for single-key commands from the user. Redraws the
screen after each user command, and at the top of each minute. Returns after
the user presses C<q>.

The available key bindings are:

    h/l  go back/forward in time
    n    go back to the present time
    j/k  highlight next/previous planet
    c    clear highlight
    ?    help
    q    quit

=cut

sub run {
    my $self = shift;

    # both signals will interrupt getchar, redraw immediately follows
    local $SIG{WINCH} = sub { endwin; }; # endwin required after SIGWINCH
    local $SIG{ALRM}  = sub { 0 };

    while (1) {
        # draw the screen
        $self->draw;

        # wait for a key, or redraw at the top of each minute
        alarm (60 - time % 60);
        my ($ch, $key) = getchar;
        next if !defined $ch && !defined $key;

        switch ($ch || $key) {
            case ['h', KEY_LEFT]  { $self->advance_to_next('hour', -1); }
            case ['l', KEY_RIGHT] { $self->advance_to_next('hour',  1); }
            case  'n'             { $self->clear_datetime; }
            case ['j', KEY_DOWN]  { $self->select_next; }
            case ['k', KEY_UP]    { $self->select_prev; }
            case ['c', "\e"]      { $self->clear_selection; }
            case '?'              { alarm 0;
                                    $self->show_help;  }
            case 'q'              { return; }
        }
    }
}

=back

=head1 AUTHOR

Fran Rogers, C<< <fran at violuma.net> >>

=head1 SEE ALSO

L<Astro::Coords>; L<DateTime>

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2020 by Fran Rogers.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut

1; # End of Curses::Orrery
