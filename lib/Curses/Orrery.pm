package Curses::Orrery;

use strict;
use warnings;

use Astro::Coords::Planet;
use Astro::MoonPhase;
use Astro::Telescope;
use Curses;
use DateTime;
use I18N::Langinfo qw(langinfo CODESET);
use Math::Trig qw(pi deg2rad);
use POSIX qw(round);

our $VERSION = '1.00';


my @PLANETS = (['sun',     3, 'S', "\x{2609}"],
               ['mercury', 2, 'M', "\x{263f}"],
               ['venus',   1, 'v', "\x{2640}"],
               ['moon',    0, 'L', "\x{263D}"],
               ['mars',    4, 'm', "\x{2642}"],
               ['jupiter', 5, 'j', "\x{2643}"],
               ['saturn',  6, 's', "\x{2644}"],
               ['uranus',  7, 'u', "\x{2645}"],
               ['neptune', 8, 'n', "\x{2646}"]);

sub new {
    my ($class, %args) = @_;
    my $self = {};

    $self->{unicode} = langinfo(CODESET) =~ /^utf|^ucs/i;

    $self->{telescope} = $args{telescope};
    $self->{datetime} = $args{datetime};

    $self->{range} = $args{range};
    if (!defined $self->{range}) {
        $self->{range} = $self->{telescope}->lat > 0
                       ? [  0, 2*pi, -pi/2, pi/2]
                       : [-pi,   pi, -pi/2, pi/2]
    }

    my (@planets, @draw_order, %symbols);
    foreach my $entry (@PLANETS) {
        my ($planet_name, $z_order, $abbrev, $symbol) = @$entry;

        my $planet = Astro::Coords::Planet->new($planet_name);
        $planet->telescope($self->{telescope});
        $planet->datetime($self->{datetime});
        push @planets, $planet;

        $draw_order[$z_order] = $planet;

        $symbols{$planet_name} = $self->{unicode} ? $symbol : $abbrev;
    }
    $self->{planets} = \@planets;
    $self->{draw_order} = \@draw_order;
    $self->{symbols} = \%symbols;

    $self->{index} = undef;

    $self->{time_zone} = $args{time_zone} || 'local';
    if ($self->{time_zone} eq 'local') {
        $self->{time_zone} = DateTime::TimeZone->new(name => 'local');
    }

    $self->{win} = Curses->new;
    $self->{win}->keypad(1);
    curs_set 0;
    noecho;
    $self->{win}->getmaxyx(my $maxy, my $maxx);
    $self->{maxyx} = [$maxy, $maxx];

    return bless $self, $class;
}

sub DESTROY {
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
        } elsif (!defined $self->{datetime}) {
            $self->datetime(DateTime->now);
        }
    }
    return !defined $self->{datetime};
}

sub planets {
    return @{shift->{planets}};
}

sub selected {
    my $self = shift;
    if (@_) {
        my $planet = shift;
        foreach my $n (0 .. scalar @{$self->{planets}}) {
            if ($planet == $self->{planets}->[$n]) {
                $self->{index} = $n;
                last;
            }
        }
    }
    return defined $self->{index} ? $self->{planets}->[$self->{index}] : undef;
}

sub selected_index {
    my $self = shift;
    if (@_) {
        my $index = shift;
        $self->{index} = defined $index
                       ? $index % scalar @{$self->{planets}}
                       : undef;
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

sub _azel_to_yx {
    my $self = shift;
    my $az = shift;
    my $el = shift;

    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($min_az, $max_az, $min_el, $max_el) = @{$self->{range}};

    $az = -2*pi + $az if $az > $max_az;
   
    my $y = round($maxy - $maxy * ($el - $min_el) / ($max_el - $min_el));
    my $x = round(        $maxx * ($az - $min_az) / ($max_az - $min_az));

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

    foreach my $planet (reverse @{$self->{draw_order}}) {
        $self->_draw_planet($planet);
    }

    $self->_draw_selection;

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

    foreach my $az (0, pi) {
        my $x_line = $self->_az_to_x($az);

        next if $az == $self->{range}->[0]
             || $az == $self->{range}->[1];

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
    
    $win->addstring($y, $x, $self->{symbols}->{$planet->name});
}

sub _draw_selection {
    my $self = shift;

    return if !defined $self->{index};

    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my $planet = $self->{planets}->[$self->{index}];

    my ($az, $el) = $planet->azel;

    $win->attron(A_REVERSE);
    $self->_draw_planet($planet);
    $win->attroff(A_REVERSE);

    $win->addstring(0, 0, $planet->name);

    $win->addstring(2, 2, 'azimuth:');
    $win->addstring(2, 13, sprintf('% 3d', $az->degrees));
    $win->addch(2, 16, ACS_DEGREE);
    $win->addstring(3, 0, 'elevation:');
    $win->addstring(3, 13, sprintf('% 3d', $el->degrees));
    $win->addch(3, 16, ACS_DEGREE);

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

    my $transit = $planet->meridian_time(nearest => 1);

    my $prev_rise = $planet->rise_time(event => -1);
    my $next_rise = $planet->rise_time(event =>  1);
    my $prev_set  = $planet->set_time (event => -1);
    my $next_set  = $planet->set_time (event =>  1);

    my $rise = $transit > $next_rise ? $next_rise : $prev_rise;
    my $set  = $transit < $prev_set  ? $prev_set  : $next_set;
    
    $win->addstring(5,  5, 'rise:');
    $win->addstring(5, 11, &{$event_time}($rise));
    $win->addstring(6,  2, 'transit:');
    $win->addstring(6, 11, &{$event_time}($transit));
    $win->addstring(7,  6, 'set:');
    $win->addstring(7, 11, &{$event_time}($set));
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

    my $lower_left = sprintf(q{%3d %02d'%02d"%s %3d %02d'%02d"%s %4dm},
                             $lat_d,   $lat_m,  $lat_s,
                             $lat_sign  eq '+' ? 'N' : 'S',
                             $long_d, $long_m, $long_s,
                             $long_sign eq '+' ? 'E' : 'W',
                             $alt);
    $win->addstring($maxy - 1, 0, $lower_left);
    $win->addch($maxy - 1, 3, ACS_DEGREE);
    $win->addch($maxy - 1, 15, ACS_DEGREE);

    my $dt = $self->datetime_local;

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

    my $lower_right = sprintf('%s', $dt->strftime('%a %F %R'));
    $win->addstring($maxy - 1, $maxx - length($lower_right), $lower_right);
    $win->addch($maxy - 1, $maxx - 23, ACS_BULLET)
        if !$self->usenow;

    if ($self->{unicode}) {
        $win->addstring($maxy - 2, $maxx - 22, "\x{263D}");
        $win->addstring($maxy - 1, $maxx - 22, "\x{2609}");
    }
}
    
sub _show_help {
    my $self = shift;
  
    my $win = $self->{win};
    my ($maxy, $maxx) = @{$self->{maxyx}};

    my ($helpwin_maxy, $helpwin_maxx) = (13, 60);
    return if $maxy < $helpwin_maxy || $maxx < $helpwin_maxx;

    my $helpwin = $win->derwin($helpwin_maxy,
                               $helpwin_maxx,
                               $maxy / 2 - $helpwin_maxy / 2,
                               $maxx / 2 - $helpwin_maxx / 2);

    $helpwin->clear;
    $helpwin->box(ACS_VLINE, ACS_HLINE);
    $helpwin->addch(0, $helpwin_maxx / 3, ACS_TTEE);
    $helpwin->addch($helpwin_maxy - 1, $helpwin_maxx / 3, ACS_BTEE);
    $helpwin->vline(1, $helpwin_maxx / 3, ACS_VLINE, $helpwin_maxy - 2);

    my $x = 2;
    my $y = 1;
    $helpwin->addstring($y++, $x, 'planets:');
    for my $planet (@{$self->{planets}}) {
        my $planet_name = $planet->name;
        $helpwin->addstring($y, $x+1, $self->{symbols}->{$planet_name});
        $helpwin->addstring($y, $x+3, $planet_name);
        $y++;
    }

    $y = 1;
    $x = $helpwin_maxx / 3 + 2;
    $helpwin->addstring($y++, $x, 'key bindings:');
    $helpwin->addstring($y++, $x+1, 'h/l  go back/forward in time');
    $helpwin->addstring($y++, $x+1, 'n    go to the present time');
    $helpwin->addstring($y++, $x+1, 'j/k  highlight next/previous planet');
    $helpwin->addstring($y++, $x+1, 'c    clear highlight');
    $helpwin->addstring($y++, $x+1, '?    help');
    $helpwin->addstring($y++, $x+1, 'q    quit');

    $helpwin->addstring($helpwin_maxy - 2,
                        $helpwin_maxx - 27,
                        'press any key to continue');

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
        next if !defined $ch && !defined $key;

        if ($ch && $ch eq 'h' || !$ch && $key == KEY_LEFT) {
            $self->usenow(0);

            my $dt = $self->datetime;
            my $dt_hour = $dt->clone->truncate(to => 'hour');

            if ($dt > $dt_hour) {
                $self->datetime($dt_hour);
            }
            else {
                $self->datetime($dt->clone->subtract(hours => 1));
            }
        }
        if ($ch && $ch eq 'l' || !$ch && $key == KEY_RIGHT) {
            $self->usenow(0);

            my $dt = $self->datetime->clone->truncate(to => 'hour');
            $dt = $dt->clone->add(hours => 1);
            $self->datetime($dt);
        }
        elsif ($ch && $ch eq 'n') {
            $self->usenow(1);
        }
        elsif ($ch && $ch eq 'j' || !$ch && $key == KEY_DOWN) {
            my $index = $self->selected_index;
            $index = -1 if !defined $index;
            $self->selected_index(++$index);
        }
        elsif ($ch && $ch eq 'k' || !$ch && $key == KEY_UP) {
            my $index = $self->selected_index;
            $index = 0 if !defined $index;
            $self->selected_index(--$index);
        }
        elsif ($ch && $ch eq 'c' || $ch && $ch eq "\e") {
            $self->selected_index(undef);
        }
        elsif ($ch && $ch eq '?') {
            alarm 0;
            $self->_show_help;
        }
        elsif ($ch && $ch eq 'q') {
            return;
        }
    }
}

1;
