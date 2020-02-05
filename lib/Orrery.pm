package Orrery;

use strict;
use warnings;

use Astro::Coords;
use Astro::Coords::Planet;
use Astro::MoonPhase;
use Astro::Telescope;
use Curses;
use DateTime;
use I18N::Langinfo qw(langinfo CODESET);
use Math::Trig qw(pi deg2rad rad2deg);
use POSIX qw(round strftime);

our $VERSION = '1.00';


my %abbrevs = (moon    => 'L',
               sun     => 'S',
               mercury => 'M',
               venus   => 'v',
               mars    => 'm',
               jupiter => 'j',
               saturn  => 's',
               uranus  => 'u',
               neptune => 'n');
my %symbols = (moon    => "\x{263D}",
               sun     => "\x{2609}",
               mercury => "\x{263f}",
               venus   => "\x{2640}",
               mars    => "\x{2642}",
               jupiter => "\x{2643}",
               saturn  => "\x{2644}",
               uranus  => "\x{2645}",
               neptune => "\x{2646}");
my $unicode = langinfo(CODESET) =~ /^utf|^ucs/i;

sub new {
    my ($class, %args) = @_;
    my $self = {};

    $self->{telescope} = $args{telescope};
    $self->{datetime} = $args{datetime};

    $self->{range} = $args{range};
    if (!defined $self->{range}) {
        $self->{range} = $self->{telescope}->lat > 0
                       ? [  0, 2*pi, -pi/2, pi/2]
                       : [-pi,   pi, -pi/2, pi/2]
    }

    my @planets;
    foreach my $planet_name (@Astro::Coords::Planet::PLANETS) {
        my $planet = Astro::Coords->new(planet => $planet_name);
        $planet->telescope($self->{telescope});
        $planet->datetime($self->{datetime});

        push @planets, $planet;
    }
    $self->{planets} = \@planets;

    $self->{win} = Curses->new;
    $self->{win}->keypad(1);
    curs_set 0;
    noecho;
    $self->{win}->getmaxyx(my $maxy, my $maxx);
    $self->{maxyx} = [$maxy, $maxx];

    return bless $self, $class;
}

sub DESTROY {
    my $self = shift;

    endwin;
}

sub _resize {
    my $self = shift;

    endwin;
    refresh;
    my ($maxy, $maxx);
    $self->{win}->getmaxyx($maxy, $maxx);
    $self->{maxyx} = [$maxy, $maxx];
}

sub datetime {
    my $self = shift;
    if (@_) {
        $self->{datetime} = shift;

        for my $planet (@{$self->{planets}}) {
            $planet->datetime($self->{datetime});
        }
    }
    return $self->{datetime};
}

sub _azel_to_yx {
    my $self = shift;
    my $az = shift;
    my $el = shift;

    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($min_az, $max_az, $min_el, $max_el) = @{$self->{range}};
    $az = -2*pi + $az if $az > $max_az;

    # TODO: make this less hairy
    my $view_az = $min_az + ($max_az - $min_az) / 2;
    my $view_el = $min_el + ($max_el - $min_el) / 2;
    my $view_width = ($max_az - $min_az) / (2*pi);
    my $view_height = ($max_el - $min_el) / pi;

    my $y = round($maxy / 2 - (1 / $view_height) * (($el / (pi/2)) - ($view_el / (pi/2))) * ($maxy / 2));
    my $x = round($maxx / 2 + (1 / $view_width ) * (($az / (pi*2)) - ($view_az / (pi*2))) * $maxx);

    return ($y, $x);
}

sub _az_to_x {
    my $self = shift;
    my $az = shift;

    my ($y, $x) = $self->_azel_to_yx($az, 0);

    return $x;
}

sub _el_to_y {
    my $self = shift;
    my $el = shift;
    
    my ($y, $x) = $self->_azel_to_yx(0, $el);

    return $y;
}

sub draw {
    my $self = shift;

    my $win = $self->{win};
    $win->clear;

    $self->_draw_axes;

    foreach my $planet (reverse @{$self->{planets}}) {
        $self->_draw_planet($planet);
    }

    $self->_draw_status;

    $win->refresh;
}

sub _draw_axes {
    my $self = shift;

    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my $y_line = $self->_el_to_y(0);
    $win->hline($y_line, 0, ACS_HLINE, $maxx);

    foreach my $az (45, 90, 135, 180, 225, 270, 315) {
        my $x_label = $self->_az_to_x(deg2rad($az));

        if ($az == 90) {
            $win->addstring($y_line, $x_label, 'E');
        }
        elsif ($az == 270) {
            $win->addstring($y_line, $x_label, 'W');
        }
        else {
            $win->addch($y_line, $x_label, ACS_PLUS);
        }
    }

    foreach my $x_line (map { $self->_az_to_x($_) } (0, pi)) {
        next if $x_line == $self->{range}->[0]
             || $x_line == $self->{range}->[1];

        $win->vline(0, $x_line, ACS_VLINE, $maxy);
        $win->addch($y_line, $x_line, ACS_PLUS);

        foreach my $el (-60, -30, 0, 30, 60) {
            my $y_label = $self->_el_to_y(deg2rad($el));
            if (!$el) {
                $win->addch($y_label, $x_line, ACS_PLUS);
            } else {
                $win->addstring($y_label, $x_line - 2, sprintf('% 2d', $el));
                $win->addch($y_label, $x_line + 1, ACS_DEGREE);
            }
        }
    }
}

sub _draw_planet {
    my $self = shift;
    my $planet = shift;

    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($az, $el) = $planet->azel;
    my ($y, $x) = $self->_azel_to_yx($az->radians, $el->radians);
    $x %= $maxx;
    
    $win->addstring($y, $x, $unicode ? $symbols{$planet->name}
                                     : $abbrevs{$planet->name});
}

sub _draw_status {
    my $self = shift;

    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($lat_sign,   $lat_d,  $lat_m,  $lat_s) =
        $self->{telescope}->lat->components;
    my ($long_sign, $long_d, $long_m, $long_s) =
        $self->{telescope}->long->components;
    my $alt = $self->{telescope}->alt;

    my $lower_left = sprintf("%3d %02d'%02d\"%s %3d %02d'%02d\"%s  %4dm",
                             $lat_d,   $lat_m,  $lat_s,
                             $lat_sign  eq '+' ? 'N' : 'S',
                             $long_d, $long_m, $long_s,
                             $long_sign eq '+' ? 'E' : 'W',
                             $alt);
    $win->addstring($maxy - 1, 0, $lower_left);
    $win->addch($maxy - 1, 3, ACS_DEGREE);
    $win->addch($maxy - 1, 15, ACS_DEGREE);

    my $dt = $self->datetime;
    my $fixed_time = defined $dt;
    $dt = defined $dt
        ? $dt->clone->set_time_zone('local')
        : DateTime->now(time_zone => 'local');

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
    $win->addstring($maxy - 2, $maxx - length($lower_right2), $lower_right2);

    my $lower_right = sprintf('%s',
                              $dt->strftime('%a %F %R'));
    $win->addstring($maxy - 1, $maxx - length($lower_right), $lower_right);
    $win->addch($maxy - 1, $maxx - 23, ACS_BULLET)
        if $fixed_time;

    if ($unicode) {
        $win->addstring($maxy - 2, $maxx - 22, "\x{263D}");
        $win->addstring($maxy - 1, $maxx - 22, "\x{2609}");
    }
}
    
sub _show_help {
    my $self = shift;
  
    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($helpwin_maxy, $helpwin_maxx) = (15, 68);
    my $helpwin = $win->derwin($helpwin_maxy,
                               $helpwin_maxx,
                               $maxy / 2 - $helpwin_maxy / 2,
                               $maxx / 2 - $helpwin_maxx / 2);
    $helpwin->clear;
    $helpwin->box(ACS_VLINE, ACS_HLINE);
    $helpwin->addch(0, $helpwin_maxx / 2, ACS_TTEE);
    $helpwin->addch($helpwin_maxy - 1, $helpwin_maxx / 2, ACS_BTEE);
    $helpwin->vline(1, $helpwin_maxx / 2, ACS_VLINE, $helpwin_maxy - 2);

    my $x = 2;
    my $y = 1;
    $helpwin->addstring($y++, $x, 'planets:');
    for my $planet (@{$self->{planets}}) {
        my $planet_name = $planet->name;
        $helpwin->addstring($y, $x+1, $unicode ? $symbols{$planet_name}
                                            : $abbrevs{$planet_name});
        $helpwin->addstring($y, $x+3, $planet_name);
        $y++;
    }

    $y = 1;
    $x = $helpwin_maxx / 2 + 2;
    $helpwin->addstring($y++, $x, 'key bindings:');
    $helpwin->addstring($y++, $x+1, 'h/l  go back/forward in time');
    $helpwin->addstring($y++, $x+1, 'n    go to the present time');
    $helpwin->addstring($y++, $x+1, '?    help');
    $helpwin->addstring($y++, $x+1, 'q    quit');

    $helpwin->getchar;
}

sub mainloop {
    my $self = shift;

    local $SIG{WINCH} = sub { $self->_resize };
    local $SIG{ALRM} = sub { 0 };

    while (1) {
        $self->draw;

        alarm (60 - time % 60);
        my ($ch, $key) = $self->{win}->getchar;

        if ($ch eq 'h') {
            my $dt = $self->datetime;
            if (!defined $dt) {
                $dt = DateTime->now();
            }

            if ($dt->minute || $dt->second || $dt->nanosecond) {
                $dt->set_minute(0);
                $dt->set_second(0);
                $dt->set_nanosecond(0);
            }
            else {
                $dt->subtract(hours => 1);
            }

            $self->datetime($dt);
        }
        if ($ch eq 'l') {
            my $dt = $self->datetime;
            if (!defined $dt) {
                $dt = DateTime->now();
            }

            if ($dt->minute || $dt->second || $dt->nanosecond) {
                $dt->set_minute(0);
                $dt->set_second(0);
                $dt->set_nanosecond(0);
            }
            $dt->add(hours => 1);

            $self->datetime($dt);
        }
        elsif ($ch eq 'n') {
            $self->datetime(undef);
        }
        elsif ($ch eq '?') {
            alarm 0;
            $self->_show_help;
        }
        elsif ($ch eq 'q') {
            return;
        }
    }
}

1;
