package Curses::Orrery;

use strict;
use warnings;
use 5.12.0;

use Astro::Coords::Planet;
use Astro::MoonPhase;
use Astro::Telescope;
use Curses;
use DateTime;
use I18N::Langinfo qw(langinfo CODESET);
use List::Util qw(min);
use List::MoreUtils qw(firstidx sort_by);
use Math::Trig qw(pi deg2rad);
use POSIX qw(round);
use Switch;

our $VERSION = '0.10';


sub new {
    my ($class, %args) = @_;
    my $self = {};

    # telescope is the sole required argument
    $self->{telescope} = $args{telescope}
                       // die('telescope is required');

    # populate things
    $self->{datetime}  = $args{datetime};

    # default azimuth range is 0..2*pi in northern hemisphere, -pi..pi in 
    # the southern. default elevation range is always -pi/2..pi/2
    $self->{range} = $args{range};
    $self->{range} //= $self->{telescope}->lat > 0
                     ? [  0, 2*pi, -pi/2, pi/2]
                     : [-pi,   pi, -pi/2, pi/2];

    # use @PLANETS table to populate data structures
    my @planets;
    foreach my $planet_name (@Astro::Coords::Planet::PLANETS) {
        my $planet = Astro::Coords::Planet->new($planet_name);
        $planet->telescope($self->{telescope});
        $planet->datetime($self->{datetime});
        push @planets, $planet;
    }
    $self->{planets} = \@planets;

    # select a planet if the user specified an index or ref
    $self->{index} = $args{selected_index};
    if (defined $args{selected}) {
        my $i = firstidx { $_ == $args{selected} } @planets;
        $self->{index} = $i if $i != -1;
    }

    # cache the local time zone for later, because lookup is slow.
    # note that $self->datetime should always be UTC
    $self->{time_zone} = $args{time_zone} || 'local';
    if ($self->{time_zone} eq 'local') {
        $self->{time_zone} = DateTime::TimeZone->new(name => 'local');
    }

    # init curses
    initscr;
    $stdscr->keypad(1);
    curs_set 0;
    noecho;
    $self->{unicode} = $args{unicode} // &_test_unicode;

    return bless $self, $class;
}

sub DESTROY {
    endwin;
}

sub _test_unicode {
    # is the current codeset a Unicode one?
    return 0 if langinfo(CODESET) !~ /^utf|^ucs/i;

    # is our curses wide-aware?
    # or does it treat UTF-8 as byte sequences?
    addstring 0, 0, "\x{FEFF}";
    getyx my $y, my $x;
    return $y * $COLS + $x;
};

sub datetime {
    my $self = shift;
    if (@_) {
        $self->{datetime} = shift;

        for my $planet (@{$self->{planets}}) {
            $planet->datetime($self->{datetime});
        }
    }
    return $self->{datetime} || DateTime->now;
}

sub datetime_local {
    my $self = shift;
    my $dt = $self->datetime->clone;
    return $dt->set_time_zone($self->{time_zone});
}

sub usenow {
    my $self = shift;
    if (@_) {
        if (shift) {
            $self->datetime(undef);
        }
        else {
            $self->{datetime} //= (DateTime->now);
        }
    }
    return !defined $self->{datetime};
}

sub planets {
    my $self = shift;
    return @{$self->{planets}};
}

sub _planet_symbol {
    my $self = shift;
    my $planet = shift;

    my %abbrevs = (sun     => 'S', mercury => 'M', venus   => 'v',
                   moon    => 'L', mars    => 'm', jupiter => 'j',
                   saturn  => 's', uranus  => 'u', neptune => 'n');
    my %symbols = (sun     => "\x{2609}", mercury => "\x{263f}",
                   venus   => "\x{2640}", moon    => "\x{263D}",
                   mars    => "\x{2642}", jupiter => "\x{2643}",
                   saturn  => "\x{2644}", uranus  => "\x{2645}",
                   neptune => "\x{2646}");

    return $self->{unicode}
         ? $symbols{$planet->name}
         : $abbrevs{$planet->name};
}

sub _planet_draw_order {
    my $self = shift;

    # planet draw order, farthest to nearest
    my @draw_order = qw(neptune uranus  saturn
                        jupiter mars    sun
                        venus   mercury moon);
    $self->{draw_order} //= [sort_by { my $n = $_->name;
                                       firstidx { $_ eq $n } @draw_order
                                     } $self->planets];
    return @{$self->{draw_order}};
}

sub selected {
    my $self = shift;
    if (@_) {
        my $planet = shift;
       
        my $i = firstidx { $_ == $planet } $self->planets;
        $self->{index} = $i != -1
                       ? $i
                       : undef;
    }
    return $self->{planets}->[$self->{index}];
}

sub selected_index {
    my $self = shift;
    if (@_) {
        $self->{index} = shift;
        $self->{index} %= scalar $self->planets
            if defined($self->{index});
    }
    return $self->{index};
}

sub range {
    my $self = shift;
    if (@_) {
        my ($min_az, $max_az, $min_el, $max_el) = @_;
        $self->{range} = [$min_az, $max_az, $min_el, $max_el];
    }
    return $self->{range};
}

sub _azel_yx {
    my $self = shift;
    my $az = shift;
    my $el = shift;

    my ($min_az, $max_az, $min_el, $max_el) = @{$self->{range}};

    $az = -2*pi + $az if $az > $max_az;
   
    my $y = round($LINES - $LINES * ($el - $min_el) / ($max_el - $min_el));
    my $x = round(         $COLS  * ($az - $min_az) / ($max_az - $min_az));

    return ($y, $x);
}

sub _az_x {
    my $self = shift;
    my $az = shift;

    my ($y, $x) = $self->_azel_yx($az, 0);

    return $x;
}

sub _el_y {
    my $self = shift;
    my $el = shift;
    
    my ($y, $x) = $self->_azel_yx(0, $el);

    return $y;
}

sub draw {
    my $self = shift;

    clear;

    $self->_draw_axes;

    foreach my $planet ($self->_planet_draw_order) {
        $self->_draw_planet($planet);
    }

    $self->_draw_selection;

    $self->_draw_status;

    refresh;
}

sub _draw_axes {
    my $self = shift;

    # x axis
    my $y_line = $self->_el_y(0);
    hline($y_line, 0, ACS_HLINE, $COLS);
    foreach my $az (45, 90, 135, 180, 225, 270, 315) {
        my $x_label = $self->_az_x(deg2rad($az));

        if ($az == 90) {
            addstring $y_line, $x_label, 'E';
        }
        elsif ($az == 270) {
            addstring $y_line, $x_label, 'W';
        }
        else {
            addch     $y_line, $x_label, ACS_PLUS;
        }
    }

    # y axes (one each at due north and due south)
    foreach my $az (0, pi) {
        my $x_line = $self->_az_x($az);

        next if $az == $self->{range}->[0]
             || $az == $self->{range}->[1];

        vline       0, $x_line, ACS_VLINE, $LINES;
        addch $y_line, $x_line, ACS_PLUS;

        foreach my $el (-60, -30, 0, 30, 60) {
            my $y_label = $self->_el_y(deg2rad($el));
            if (!$el) {
                addch     $y_label, $x_line, ACS_PLUS;
            } else {
                addstring $y_label, $x_line - 2, sprintf('% 2d', $el);
                addch     $y_label, $x_line + 1, ACS_DEGREE;
            }
        }
    }
}

sub _draw_planet {
    my $self = shift;
    my $planet = shift;

    my ($az, $el) = $planet->azel;
    my ($y, $x) = $self->_azel_yx($az->radians, $el->radians);
    
    addstring $y, $x, $self->_planet_symbol($planet);
}

sub _draw_selection {
    my $self = shift;

    return if !defined $self->{index};

    my $planet = $self->{planets}->[$self->{index}];

    my ($az, $el) = $planet->azel;

    # redraw the planet in reverse video
    attron(A_REVERSE);
    $self->_draw_planet($planet);
    attroff(A_REVERSE);

    # top left display
    # name
    addstring 0, 0, $planet->name;

    # az/el
    addstring 2, 2, 'azimuth:';
    addstring 2, 13, sprintf('% 3d', $az->degrees);
    addch     2, 16, ACS_DEGREE;
    addstring 3, 0, 'elevation:';
    addstring 3, 13, sprintf('% 3d', $el->degrees);
    addch     3, 16, ACS_DEGREE;

    # rise/transit/set
    # first find the nearest transit
    my $transit = $planet->meridian_time(nearest => 1);

    # then pick the rise/set in the same cycle
    my $prev_rise = $planet->rise_time(event => -1);
    my $next_rise = $planet->rise_time(event =>  1);
    my $prev_set  = $planet->set_time (event => -1);
    my $next_set  = $planet->set_time (event =>  1);
    my $rise = $transit > $next_rise ? $next_rise : $prev_rise;
    my $set  = $transit < $prev_set  ? $prev_set  : $next_set;

    # print the date alongside the time if it isn't same-day
    my $event_time = sub {
        my $dt = shift->clone->set_time_zone($self->{time_zone});
        
        my $today = $self->datetime_local->truncate(to => 'day');

        if (!defined $dt) {
            return 'never';
        }
        elsif ($dt->clone->truncate(to => 'day') == $today) {
            return $dt->strftime('%R');
        }
        else {
            return $dt->strftime('%R %d %b');
        }
    };
    
    addstring 5,  5, 'rise:';
    addstring 5, 11, &{$event_time}($rise);
    addstring 6,  2, 'transit:';
    addstring 6, 11, &{$event_time}($transit);
    addstring 7,  6, 'set:';
    addstring 7, 11, &{$event_time}($set);
}

sub _draw_status {
    my $self = shift;

    my $dt = $self->datetime_local;

    # bottom left: viewer long, lat, alt
    my ($lat_sign,   $lat_d,  $lat_m,  $lat_s) =
        $self->{telescope}->lat->components;
    my ($long_sign, $long_d, $long_m, $long_s) =
        $self->{telescope}->long->components;
    my $alt = $self->{telescope}->alt;

    my $lower_left = sprintf(q{%3d %02d'%02d"%s %3d %02d'%02d"%s %4dm},
                             $lat_d,   $lat_m,  $lat_s,
                             $lat_sign  eq '+' ? 'N' : 'S',
                             $long_d, $long_m, $long_s,
                             $long_sign eq '+' ? 'E' : 'W',
                             $alt);
    addstring $LINES - 1, 0, $lower_left;
    addch     $LINES - 1, 3, ACS_DEGREE;
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
    if (!$self->usenow) {
        addch $LINES - 1, $COLS - 23, ACS_BULLET;
    }

    if ($self->{unicode}) {
        addstring $LINES - 2, $COLS - 22, "\x{263D}";
        addstring $LINES - 1, $COLS - 22, "\x{2609}";
    }
}
    
sub _show_help {
    my $self = shift;

    # turn off the periodic SIGALRM in mainloop
    alarm 0;

    # terminal needs to be at least 60x13 to fit help on screen
    my ($helpwin_lines, $helpwin_cols) = (13, 60);
    return if $LINES < $helpwin_lines || $COLS < $helpwin_cols;

    # create the help window
    my $helpwin = $stdscr->derwin($helpwin_lines,
                                  $helpwin_cols,
                                  $LINES / 2 - $helpwin_lines / 2,
                                  $COLS  / 2 - $helpwin_cols  / 2);
    $helpwin->clear;
    $helpwin->box(ACS_VLINE, ACS_HLINE);

    # divide it with a vertical line 1/3 from the left
    $helpwin->addch(0, $helpwin_cols / 3, ACS_TTEE);
    $helpwin->addch($helpwin_lines - 1, $helpwin_cols / 3, ACS_BTEE);
    $helpwin->vline(1, $helpwin_cols / 3, ACS_VLINE, $helpwin_lines - 2);

    # populate the left side with a key to the planet symbols
    my $x = 2;
    my $y = 1;
    $helpwin->addstring($y++, $x, 'planets:');
    for my $planet (@{$self->{planets}}) {
        $helpwin->addstring($y, $x+1, $self->_planet_symbol($planet));
        $helpwin->addstring($y, $x+3, $planet->name);
        $y++;
    }

    # populate the right side with key-binding help
    $y = 1;
    $x = $helpwin_cols / 3 + 2;
    $helpwin->addstring($y++, $x, 'key bindings:');
    $helpwin->addstring($y++, $x+1, 'h/l  go back/forward in time');
    $helpwin->addstring($y++, $x+1, 'n    go to the present time');
    $helpwin->addstring($y++, $x+1, 'j/k  highlight next/previous planet');
    $helpwin->addstring($y++, $x+1, 'c    clear highlight');
    $helpwin->addstring($y++, $x+1, '?    help');
    $helpwin->addstring($y++, $x+1, 'q    quit');

    $helpwin->addstring($helpwin_lines - 2,
                        $helpwin_cols  - 27,
                        'press any key to continue');

    # wait for any key
    $helpwin->getchar;
}

sub mainloop {
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
            case ['h', KEY_LEFT] {
                $self->datetime($self->datetime
                                     ->truncate(to => 'hour')
                                     ->subtract(hours => 1));
            }
            case ['l', KEY_RIGHT] {
                $self->datetime($self->datetime
                                     ->truncate(to => 'hour')
                                     ->add(hours => 1));
            }
            case  'n'             { $self->usenow(1); }
            case ['j', KEY_DOWN]  {
                $self->selected_index(($self->selected_index // -1) + 1);
            }
            case ['k', KEY_UP]    {
                $self->selected_index(($self->selected_index ||  0) - 1);
            }
            case ['c', "\e"]      { $self->selected_index(undef); }

            case '?'              { $self->_show_help;  }
            case 'q'              { return; }
        }
    }
}

1;
